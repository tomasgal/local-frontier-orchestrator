param([Parameter(Mandatory)][string]$SurrealBinary)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/LfoEpistemicStore.ps1')
function Assert($Value,[string]$Message) { if (-not $Value) { throw $Message }; $script:checks++ }
function Reject([scriptblock]$Action,[string]$Message) { $caught=$false;try { & $Action | Out-Null } catch { $caught=$true }; Assert $caught $Message }
function Credential([string]$User,[string]$Password) { return New-Object Management.Automation.PSCredential($User,(ConvertTo-SecureString $Password -AsPlainText -Force)) }
$script:checks=0
$root=Join-Path ([IO.Path]::GetTempPath()) ('LFO-l4-r1-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$logs=Join-Path $root 'l0'
$null=New-Item -ItemType Directory -Path $logs
$store=Register-LfoEpistemicL0Store $logs
Assert ((Register-LfoEpistemicL0Store $logs) -ceq $store) 'Unstable store identity'
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
$listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
$endpoint='http://127.0.0.1:'+$port
$rootPassword=[guid]::NewGuid().ToString('N')
$runtimePassword=[guid]::NewGuid().ToString('N')
$admin=New-LfoEpistemicConnection $endpoint (Credential 'test_root' $rootPassword) -Bootstrap
$conn=New-LfoEpistemicConnection $endpoint (Credential 'lfo_r1' $runtimePassword)
$script:server=$null
$script:startCount=0
function Start-FixtureServer {
    $script:startCount++
    $oldUser=$env:SURREAL_USER;$oldPass=$env:SURREAL_PASS
    try {
        $env:SURREAL_USER='test_root';$env:SURREAL_PASS=$rootPassword
        $db='rocksdb://'+(Join-Path $root 'db').Replace('\','/')
        $args=@('start','--bind',('127.0.0.1:'+$port),'--query-timeout','3s','--deny-guests','--deny-scripting','--deny-net','--log','warn',('"'+$db+'"'))
        $script:server=Start-Process -FilePath $SurrealBinary -ArgumentList $args -PassThru -RedirectStandardOutput (Join-Path $root ('server-'+$script:startCount+'.out')) -RedirectStandardError (Join-Path $root ('server-'+$script:startCount+'.err'))
    } finally { $env:SURREAL_USER=$oldUser;$env:SURREAL_PASS=$oldPass }
    $ready=$false
    for($i=0;$i -lt 60;$i++) {
        if($script:server.HasExited) { throw ('Server failed; see '+$root) }
        try { $null=Invoke-RestMethod ($endpoint+'/ready') -TimeoutSec 1;$ready=$true;break } catch { Start-Sleep -Milliseconds 150 }
    }
    Assert $ready 'Server readiness timeout'
}
function Stop-FixtureServer {
    if ($script:server -and -not $script:server.HasExited) { Stop-Process -Id $script:server.Id -Force;$script:server.WaitForExit();$script:server.Dispose();$script:server=$null }
}
$file='conversation-2026-10.jsonl'
$unicode='Premise '+[char]0x017E+[char]0x00F4+[char]::ConvertFromUtf32(0x1F52C)+"`nsecond line"
$row=[ordered]@{event='turn';epoch=1;turn_id=1;user=$unicode;assistant='Final answer';stage_sources_schema=1;stage_sources=@(
    @{stage_id='s1';actor='USER';stage='INPUT';phase='input';producer='USER';status='received';model=$null;source_field='user'},
    @{stage_id='s2';actor='LOCAL';stage='LOCAL_RESPONSE';phase='initial';producer='LOCAL';status='returned';model='fixture';content='Local answer'},
    @{stage_id='s3';actor='FRONTIER';stage='FRONTIER_RESPONSE';phase='handoff';producer='FRONTIER';status='returned';model=$null;content='Frontier answer'},
    @{stage_id='s4';actor='FINAL';stage='FINAL_RESPONSE';phase='synthesis';producer='LOCAL';status='delivered';model='fixture';source_field='assistant'})}
$l0path=Join-Path $logs $file
[IO.File]::WriteAllText($l0path,($row|ConvertTo-Json -Depth 8 -Compress)+"`n",(New-Object Text.UTF8Encoding($false)))
$l0hash=(Get-FileHash $l0path).Hash
$base=@{LogDirectory=$logs;SourceFile=$file;Epoch=1;TurnId=1;StageId='s1';ObservationType='FRAMING';Detector='fixture.manual';DetectorVersion='1';Excerpt=$unicode}
try {
    Start-FixtureServer
    Initialize-LfoEpistemicSchema $admin (Credential 'lfo_r1' $runtimePassword)
    $o=New-LfoEpistemicObservation @base
    $write=Add-LfoEpistemicObservation $conn $logs $o
    Assert ($write.outcome -ceq 'CREATED') ('Create failed: '+($write|ConvertTo-Json -Compress))
    $retry=Add-LfoEpistemicObservation $conn $logs $o
    Assert ($retry.outcome -ceq 'ALREADY_EXISTS') 'Retry not idempotent'
    $conflict=New-LfoEpistemicObservation @base -Id $o.observation_id -Confidence 0.7
    Assert ((Add-LfoEpistemicObservation $conn $logs $conflict).outcome -ceq 'CONFLICT') 'Duplicate conflict not detected'
    $stored=@(Get-LfoEpistemicObservation $conn $o.observation_id $store 1)
    Assert ($stored.Count -eq 1) ('Read cardinality mismatch: '+$stored.Count)
    Assert ($stored[0].excerpt -ceq $unicode) ('Unicode read mismatch: expected SHA256 '+(Get-LfoEpistemicHash $unicode)+'; actual '+(Get-LfoEpistemicHash $stored[0].excerpt))
    Assert ($null -eq $stored[0].confidence) 'Unknown confidence did not round-trip as null'
    Assert ($stored[0].status -ceq 'REPORTED' -and $stored[0].recorded_at) 'Record metadata missing'
    $orphan=New-LfoEpistemicObservation @base -Interaction REINFORCED -RelatedObservationId ([guid]::NewGuid().ToString('N'))
    Assert ((Add-LfoEpistemicObservation $conn $logs $orphan).outcome -ceq 'REJECTED') 'Dangling relation accepted'
    foreach($n in 2..4) {
        $p=$base.Clone();$p.StageId='s'+$n;$p.Excerpt=''
        $item=New-LfoEpistemicObservation @p -Interaction CHALLENGED -RelatedObservationId $o.observation_id
        Assert ((Add-LfoEpistemicObservation $conn $logs $item).outcome -ceq 'CREATED') 'Stage write failed'
    }
    $all=Find-LfoEpistemicObservations $conn $store 1
    Assert ($all.Items.Count -eq 4) 'Expected four observations'
    $page=Find-LfoEpistemicObservations $conn $store 1 -Limit 2
    $page2=Find-LfoEpistemicObservations $conn $store 1 -Limit 2 -AfterId $page.NextAfterId
    Assert ($page.Items.Count -eq 2 -and $page2.Items.Count -eq 2 -and @($page.Items.observation_id|Where-Object { $_ -in $page2.Items.observation_id }).Count -eq 0) 'Pagination repeats/misses rows'
    Assert ((Find-LfoEpistemicObservations $conn $store 1 -Actor FRONTIER).Items.Count -eq 1) 'Actor filter failed'
    Assert ((Find-LfoEpistemicObservations $conn $store 2).Items.Count -eq 0) 'Epoch isolation failed'
    Assert ((Find-LfoEpistemicObservations $conn ([guid]::NewGuid().ToString('N')) 1).Items.Count -eq 0) 'Store isolation failed'
    Reject { Find-LfoEpistemicObservations $conn $store 1 -Limit 201 } 'Unbounded query accepted'
    Reject { New-LfoEpistemicConnection 'http://example.com:8000' (Credential a b) } 'Remote endpoint accepted'
    Reject { New-LfoEpistemicObservation @base -Confidence ([double]::NaN) } 'NaN confidence accepted'
    $bad=$base.Clone();$bad.Excerpt='not present';Reject { New-LfoEpistemicObservation @bad } 'Invented excerpt accepted'
    $bad=$base.Clone();$bad.TurnId=2;Reject { New-LfoEpistemicObservation @bad } 'Missing source accepted'
    $bad=$base.Clone();$bad.SourceFile='../conversation-2026-10.jsonl';Reject { New-LfoEpistemicObservation @bad } 'Traversal accepted'
    $forged=$o|ConvertTo-Json -Depth 10|ConvertFrom-Json;$forged.actor='FINAL'
    Reject { Add-LfoEpistemicObservation $conn $logs $forged } 'Forged actor accepted'
    $badSource=@{};foreach($key in $o.source.Keys){$badSource[$key]=$o.source[$key]};$badSource.content_sha256=('0'*64)
    Reject { Resolve-LfoEpistemicSource $logs $badSource } 'Changed source hash accepted'
    Reject { Invoke-LfoEpistemicQuery $conn 'UPDATE observations SET status="CONFIRMED";' } 'Update permitted'
    Reject { Invoke-LfoEpistemicQuery $conn 'DELETE observations;' } 'Delete permitted'
    Reject { Invoke-LfoEpistemicQuery $conn 'CREATE observations:bad SET schema_version=2;' } 'Invalid schema accepted'
    $wrong=New-LfoEpistemicConnection $endpoint (Credential 'lfo_r1' 'wrong')
    Reject { Find-LfoEpistemicObservations $wrong $store 1 } 'Wrong password accepted'
    $cross=New-LfoEpistemicConnection $endpoint (Credential 'lfo_r1' $runtimePassword);$cross.Database='other'
    Reject { Invoke-LfoEpistemicQuery $cross 'RETURN 1;' } 'Runtime user escaped database'
    # Two independent PowerShell processes compete for exactly the same record ID.
    $concurrent=New-LfoEpistemicObservation @base
    $module=(Resolve-Path (Join-Path $PSScriptRoot '../src/LfoEpistemicStore.ps1')).Path
    $jobs=@()
    try {
        foreach($n in 1..2) {
            $jobs+=Start-Job -ScriptBlock {
                param($Module,$Endpoint,$Credential,$Logs,$File,$Id,$When)
                $ErrorActionPreference='Stop';. $Module
                $c=New-LfoEpistemicConnection $Endpoint $Credential
                $v=New-LfoEpistemicObservation -LogDirectory $Logs -SourceFile $File -Epoch 1 -TurnId 1 -StageId s1 -ObservationType FRAMING -Detector concurrent -DetectorVersion 1 -Id $Id -ObservedAt $When
                Add-LfoEpistemicObservation $c $Logs $v
            } -ArgumentList $module,$endpoint,$conn.Credential,$logs,$file,$concurrent.observation_id,$concurrent.observed_at
        }
        $null=$jobs|Wait-Job -Timeout 30
        Assert (@($jobs|Where-Object State -ne 'Completed').Count -eq 0) 'Concurrent clients failed/timed out'
        $outcomes=@($jobs|Receive-Job -ErrorAction Stop)
        Assert (@($outcomes|Where-Object outcome -eq 'CREATED').Count -eq 1) 'Concurrent create not unique'
        $c=New-LfoEpistemicObservation -LogDirectory $logs -SourceFile $file -Epoch 1 -TurnId 1 -StageId s1 -ObservationType FRAMING -Detector concurrent -DetectorVersion 1 -Id $concurrent.observation_id -ObservedAt $concurrent.observed_at
        Assert ((Add-LfoEpistemicObservation $conn $logs $c).outcome -ceq 'ALREADY_EXISTS') 'Concurrent retry did not converge'
    } finally { $jobs|Stop-Job;$jobs|Remove-Job -Force }
    # Stronger than a clean restart: abruptly terminate after acknowledged writes.
    Stop-FixtureServer
    Assert ((Add-LfoEpistemicObservation $conn $logs $o).outcome -ceq 'UNKNOWN') 'Outage falsely acknowledged'
    Start-FixtureServer
    Assert ((Find-LfoEpistemicObservations $conn $store 1).Items.Count -eq 5) 'Acknowledged rows lost on restart'
    Assert ((Add-LfoEpistemicObservation $conn $logs $o).outcome -ceq 'ALREADY_EXISTS') 'Restart retry duplicated row'
    Assert ((Get-FileHash $l0path).Hash -ceq $l0hash) 'L0 transcript mutated'
    [pscustomobject]@{PASS=$true;Checks=$script:checks;ModelCalls=0;ProductionMemoryTouched=$false;Evidence=$root}
} finally { Stop-FixtureServer }
