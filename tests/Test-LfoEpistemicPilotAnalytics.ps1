param([Parameter(Mandatory)][string]$SurrealBinary)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/LfoEpistemicStore.ps1')
. (Join-Path $PSScriptRoot '../src/LfoEpistemicAnnotationWorkflow.ps1')
. (Join-Path $PSScriptRoot '../src/LfoEpistemicPilotAnalytics.ps1')

$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Credential([string]$User,[string]$Password){New-Object Management.Automation.PSCredential($User,(ConvertTo-SecureString $Password -AsPlainText -Force))}
function ToMap($Rows){$h=@{};foreach($r in @($Rows)){$h[[string]$r.name]=[int]$r.count};return $h}

$SurrealBinary=(Resolve-Path -LiteralPath $SurrealBinary).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('LFO-l4-r2c-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$logs=Join-Path $root 'l0';$null=New-Item -ItemType Directory -Path $logs
$fixture=Join-Path $PSScriptRoot 'fixtures\l4-r2-seed'
Copy-Item -LiteralPath (Join-Path $fixture 'conversation-2026-10.jsonl') -Destination (Join-Path $logs 'conversation-2026-10.jsonl')
$planPath=Join-Path $fixture 'annotation-plan.json'
$store=Register-LfoEpistemicL0Store $logs
$l0path=Join-Path $logs 'conversation-2026-10.jsonl'
$l0hash=(Get-FileHash -LiteralPath $l0path -Algorithm SHA256).Hash

$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
$endpoint='http://127.0.0.1:'+$port
$rootPassword=[guid]::NewGuid().ToString('N');$runtimePassword=[guid]::NewGuid().ToString('N')
$admin=New-LfoEpistemicConnection $endpoint (Credential 'test_root' $rootPassword) -Bootstrap
$conn=New-LfoEpistemicConnection $endpoint (Credential 'lfo_r1' $runtimePassword)
$script:server=$null
function StartServer {
    $oldUser=$env:SURREAL_USER;$oldPass=$env:SURREAL_PASS
    try{
        $env:SURREAL_USER='test_root';$env:SURREAL_PASS=$rootPassword
        $db='rocksdb://'+(Join-Path $root 'db').Replace('\','/')
        $args=@('start','--bind',('127.0.0.1:'+$port),'--query-timeout','3s','--deny-guests','--deny-scripting','--deny-net','--log','warn',('"'+$db+'"'))
        $script:server=Start-Process -FilePath $SurrealBinary -ArgumentList $args -PassThru -RedirectStandardOutput (Join-Path $root 'server.out') -RedirectStandardError (Join-Path $root 'server.err')
    }finally{$env:SURREAL_USER=$oldUser;$env:SURREAL_PASS=$oldPass}
    $ready=$false
    for($i=0;$i -lt 60;$i++){
        if($script:server.HasExited){throw ('Server failed; see '+$root)}
        try{$null=Invoke-RestMethod ($endpoint+'/ready') -TimeoutSec 1;$ready=$true;break}catch{Start-Sleep -Milliseconds 150}
    }
    Assert $ready 'Server readiness timeout'
}
function StopServer {if($script:server -and -not $script:server.HasExited){Stop-Process -Id $script:server.Id -Force;$script:server.WaitForExit();$script:server.Dispose();$script:server=$null}}

try{
    StartServer
    Initialize-LfoEpistemicSchema $admin (Credential 'lfo_r1' $runtimePassword)
    $w=Invoke-LfoEpistemicAnnotationPlan -PlanPath $planPath -LogDirectory $logs -Connection $conn
    Assert (@($w.Items|Where-Object outcome -eq 'CREATED').Count -eq 17) 'Analytics fixture write mismatch'

    $a=Get-LfoEpistemicPilotAnalytics -Connection $conn -StoreId $store -Epoch 1 -PageSize 5
    Assert ($a.ObservationCount -eq 17 -and $a.LinkedObservationCount -eq 11) 'Analytics cardinality mismatch'

    $actor=ToMap $a.ByActor
    Assert ($actor.USER -eq 3 -and $actor.LOCAL -eq 5 -and $actor.FRONTIER -eq 3 -and $actor.FINAL -eq 6) 'Actor analytics mismatch'

    $interaction=ToMap $a.ByInteraction
    Assert ($interaction.INTRODUCED -eq 6 -and $interaction.REINFORCED -eq 2 -and $interaction.CHALLENGED -eq 4 -and $interaction.CORRECTED -eq 4 -and $interaction.IGNORED -eq 1) 'Interaction analytics mismatch'

    $type=ToMap $a.ByType
    Assert ($type.FRAMING -eq 1 -and $type.PRESUPPOSITION -eq 1 -and $type.ASYMMETRIC_EVIDENCE_REQUEST -eq 1 -and $type.SYCOPHANTIC_REINFORCEMENT -eq 2 -and $type.COUNTEREVIDENCE_INTRODUCED -eq 4 -and $type.BIAS_CHALLENGED -eq 4 -and $type.OVERCONFIDENCE -eq 1 -and $type.UNCERTAINTY_SUPPRESSION -eq 1 -and $type.COUNTEREVIDENCE_IGNORED -eq 1 -and $type.EPISTEMIC_RISK_SIGNAL -eq 1) 'Type analytics mismatch'

    $pattern=ToMap $a.LinkedPatterns
    Assert ($pattern['LOCAL->USER|REINFORCED'] -eq 2 -and $pattern['LOCAL->USER|CHALLENGED'] -eq 1 -and $pattern['FRONTIER->USER|CHALLENGED'] -eq 1 -and $pattern['FINAL->LOCAL|CORRECTED'] -eq 3 -and $pattern['FINAL->USER|CORRECTED'] -eq 1 -and $pattern['FINAL->USER|CHALLENGED'] -eq 1 -and $pattern['FRONTIER->LOCAL|CHALLENGED'] -eq 1 -and $pattern['FINAL->FRONTIER|IGNORED'] -eq 1) 'Linked-pattern analytics mismatch'

    Assert ((Get-FileHash -LiteralPath $l0path -Algorithm SHA256).Hash -ceq $l0hash) 'Analytics mutated L0'

    $reportPath=Join-Path $root 'r2-analytics-report.json'
    [IO.File]::WriteAllText($reportPath,(($a|ConvertTo-Json -Depth 10)+"`n"),(New-Object Text.UTF8Encoding($false)))
    Assert (Test-Path -LiteralPath $reportPath) 'Analytics report missing'

    Write-Host ('R2_ANALYTICS_PASS: observations=17; links=11; page_size=5; actor/type/interaction/linked-pattern aggregates exact; ModelCalls=0; ProductionMemoryTouched=False; Evidence='+$root)
    [pscustomobject]@{PASS=$true;Checks=$script:checks;Observations=17;Links=11;ModelCalls=0;ProductionMemoryTouched=$false;Evidence=$root}
}finally{StopServer}
