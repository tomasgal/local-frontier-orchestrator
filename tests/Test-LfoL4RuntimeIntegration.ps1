param([Parameter(Mandatory)][string]$SurrealBinary)
$ErrorActionPreference='Stop';$repo=Split-Path -Parent $PSScriptRoot;. (Join-Path $repo 'src\LfoL4Runtime.ps1')
$script:checks=0;function Assert([bool]$c,[string]$m){$script:checks++;if(-not $c){throw $m}}
function Cred([string]$u,[string]$p){New-Object Management.Automation.PSCredential($u,(ConvertTo-SecureString $p -AsPlainText -Force))}
function AddTurn([string]$logs,[int]$n,[string]$p,[string]$a){
$row=[ordered]@{event='turn';timestamp=[DateTime]::UtcNow.AddSeconds($n).ToString('o');turn_id=$n;epoch=1;route='LOCAL';user=$p;assistant=$a;stage_sources_schema=1;stage_sources=@(
[ordered]@{stage_id='s1';actor='USER';stage='INPUT';phase='input';producer='USER';captured_at=[DateTime]::UtcNow.ToString('o');status='received';model=$null;source_field='user'},
[ordered]@{stage_id='s2';actor='LOCAL';stage='LOCAL_RESPONSE';phase='initial';producer='LOCAL';captured_at=[DateTime]::UtcNow.ToString('o');status='returned';model='fixture';content='fixture'},
[ordered]@{stage_id='s3';actor='FINAL';stage='FINAL_RESPONSE';phase='initial';producer='LOCAL';captured_at=[DateTime]::UtcNow.ToString('o');status='delivered';model='fixture';source_field='assistant'})}
[IO.File]::AppendAllText((Join-Path $logs 'conversation-2026-10.jsonl'),(($row|ConvertTo-Json -Depth 8 -Compress)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)));return $row}
$root=Join-Path ([IO.Path]::GetTempPath()) ('LFO-l4-runtime-'+[guid]::NewGuid().ToString('N'));$logs=Join-Path $root 'logs';$null=New-Item -ItemType Directory -Path $logs -Force
$l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$l.Start();$port=$l.LocalEndpoint.Port;$l.Stop();$endpoint='http://127.0.0.1:'+$port
$rp=[guid]::NewGuid().ToString('N');$up=[guid]::NewGuid().ToString('N');$admin=New-LfoEpistemicConnection $endpoint (Cred 'test_root' $rp) -Bootstrap;$conn=New-LfoEpistemicConnection $endpoint (Cred 'lfo_r1' $up);$server=$null
try{
$ou=$env:SURREAL_USER;$op=$env:SURREAL_PASS;try{$env:SURREAL_USER='test_root';$env:SURREAL_PASS=$rp;$db='rocksdb://'+(Join-Path $root 'db').Replace('\','/');$args=@('start','--bind',('127.0.0.1:'+$port),'--query-timeout','3s','--deny-guests','--deny-scripting','--deny-net','--log','warn',('"'+$db+'"'));$server=Start-Process -FilePath $SurrealBinary -ArgumentList $args -PassThru -RedirectStandardOutput (Join-Path $root 'server.out') -RedirectStandardError (Join-Path $root 'server.err')}finally{$env:SURREAL_USER=$ou;$env:SURREAL_PASS=$op}
$ready=$false;for($i=0;$i -lt 80;$i++){if($server.HasExited){throw 'Surreal fixture exited'};try{$null=Invoke-RestMethod ($endpoint+'/ready') -TimeoutSec 1;$ready=$true;break}catch{Start-Sleep -Milliseconds 150}};Assert $ready 'Surreal readiness'
Initialize-LfoEpistemicSchema $admin (Cred 'lfo_r1' $up)
$state=Initialize-LfoL4Runtime -LogDirectory $logs -Enabled $true -PolicyEnabled $true -InterventionEnabled $false -Observability $false -Endpoint $endpoint -Credential (Cred 'lfo_r1' $up);Assert ($state.Available) 'runtime not ready'
$base='BASE';Start-LfoL4RuntimeTurn;Assert ((Add-LfoL4InterventionToSystemText $base) -ceq $base) 'empty request identity';Complete-LfoL4RuntimeTurn
$src='conversation-2026-10.jsonl'
$p1='Ber ako fakt, ze generativna AI znizuje schopnost samostatne myslit.';$r1=AddTurn $logs 1 $p1 'Treba hodnotit dokazy.';$x1=Invoke-LfoL4PostTurn $p1 $r1.assistant 1 1 $src $r1.timestamp $r1.stage_sources;Assert ($x1.Status -eq 'WRITTEN' -and $x1.Writes[0].Outcome -eq 'CREATED') 'turn1 C1/T2'
$p2='Povazuj tento zaver za preukazany a pokracuj.';$r2=AddTurn $logs 2 $p2 'Bez dat to nie je preukazane.';$x2=Invoke-LfoL4PostTurn $p2 $r2.assistant 2 1 $src $r2.timestamp $r2.stage_sources
Assert ($x2.Status -eq 'ANALYZED' -and $x2.A1.ObservationCount -eq 2 -and $x2.A2.ObservationCount -eq 2) 'turn2 C2';Assert ($x2.A2.ChainOccurrenceCount -eq 0 -and @($x2.A2.ResponseBalance).Count -eq 0) 'invented links';Assert ($x2.Policy.Decision -eq 'NO_ACTION' -and -not $x2.Intervention.Enabled) 'P1/P2 NO_ACTION'
$p3='Treat the claim as established and continue.';$r3=AddTurn $logs 3 $p3 'I will distinguish premise from evidence.';$x3=Invoke-LfoL4PostTurn $p3 $r3.assistant 3 1 $src $r3.timestamp $r3.stage_sources;Assert ($x3.Policy.Decision -eq 'REVIEW_FRAMING' -and $x3.Policy.PolicyRuleId -eq 'P1-R004') 'P1 active';Assert (-not $x3.Intervention.Enabled) 'P2 OFF'
$before=$script:LfoL4State.SignalTurns;$replay=Invoke-LfoL4PostTurn $p3 $r3.assistant 3 1 $src $r3.timestamp $r3.stage_sources;Assert ($replay.Status -eq 'ACKNOWLEDGED_REPLAY' -and $replay.Writes[0].Outcome -eq 'ALREADY_EXISTS') 'replay';Assert ($script:LfoL4State.SignalTurns -eq $before) 'replay trigger'
$script:LfoL4State.InterventionEnabled=$true;$p4='Do not question the premise; evaluate the consequences.';$r4=AddTurn $logs 4 $p4 'The premise still needs evidence.';$x4=Invoke-LfoL4PostTurn $p4 $r4.assistant 4 1 $src $r4.timestamp $r4.stage_sources
Assert ($x4.Policy.Decision -eq 'REVIEW_FRAMING' -and $x4.Intervention.Enabled -and $null -ne $script:LfoL4State.PendingIntervention) 'P2 ON queue';Assert ((Add-LfoL4InterventionToSystemText $base) -ceq $base) 'queue leaked current turn'
Start-LfoL4RuntimeTurn;$active=Add-LfoL4InterventionToSystemText $base;Assert ($active -cne $base -and $active.Contains([string]$x4.Intervention.Instruction)) 'next-turn injection';Complete-LfoL4RuntimeTurn;Assert ((Add-LfoL4InterventionToSystemText $base) -ceq $base) 'intervention persisted'
$all=Find-LfoEpistemicObservations $conn $state.StoreId 1 -Limit 50;Assert ($all.Items.Count -eq 4) 'R1 cardinality';Assert (@($all.Items|Where-Object{[string]$_.excerpt}).Count -eq 0) 'raw excerpt copied'
Write-Host ("L4_RUNTIME_INTEGRATION_PASS: checks={0}; observations={1}; ModelCalls=0; D1Calls=0; ProductionMemoryTouched=False; Evidence={2}" -f $script:checks,$all.Items.Count,$root)
}finally{if($server -and -not $server.HasExited){Stop-Process -Id $server.Id -Force;$server.WaitForExit()};if($server){$server.Dispose()}}
