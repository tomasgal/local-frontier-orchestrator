param([Parameter(Mandatory)][string]$SurrealBinary)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/LfoEpistemicStore.ps1')
. (Join-Path $PSScriptRoot '../src/LfoEpistemicAnnotationWorkflow.ps1')

$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Block,[string]$Message){$script:checks++;try{& $Block;throw $Message}catch{if($_.Exception.Message -ceq $Message){throw}}}
function Credential([string]$User,[string]$Password){New-Object Management.Automation.PSCredential($User,(ConvertTo-SecureString $Password -AsPlainText -Force))}
function WriteJson([string]$Path,$Value){[IO.File]::WriteAllText($Path,(($Value|ConvertTo-Json -Depth 10 -Compress)+"`n"),(New-Object Text.UTF8Encoding($false)))}

$SurrealBinary=(Resolve-Path -LiteralPath $SurrealBinary).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('LFO-l4-r2a-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$logs=Join-Path $root 'l0';$null=New-Item -ItemType Directory -Path $logs
$store=Register-LfoEpistemicL0Store $logs
$file='conversation-2026-10.jsonl'
$row=[ordered]@{
    event='turn';epoch=1;turn_id=1
    user='The premise must be right.'
    assistant='We should test the premise before accepting it.'
    stage_sources_schema=1
    stage_sources=@(
        @{stage_id='s1';actor='USER';stage='INPUT';phase='input';producer='USER';status='received';model=$null;source_field='user'},
        @{stage_id='s2';actor='LOCAL';stage='LOCAL_RESPONSE';phase='initial';producer='LOCAL';status='returned';model='fixture';content='Yes, let us accept it.'},
        @{stage_id='s3';actor='FRONTIER';stage='FRONTIER_RESPONSE';phase='handoff';producer='FRONTIER';status='returned';model='fixture-frontier';content='Counterevidence exists.'},
        @{stage_id='s4';actor='FINAL';stage='FINAL_RESPONSE';phase='synthesis';producer='LOCAL';status='delivered';model='fixture';source_field='assistant'}
    )
}
$l0path=Join-Path $logs $file
WriteJson $l0path $row
$l0hash=(Get-FileHash -LiteralPath $l0path -Algorithm SHA256).Hash

$ids=1..4|ForEach-Object{[guid]::NewGuid().ToString('N')}
$plan=[ordered]@{
    schema='lfo-epistemic-annotation-plan-v1'
    detector='human.manual'
    detector_version='r2-v1'
    source=[ordered]@{file=$file;epoch=1}
    observations=@(
        [ordered]@{key='user-frame';id=$ids[0];observed_at='2026-10-13T08:00:00Z';turn_id=1;stage_id='s1';observation_type='FRAMING';confidence=$null;excerpt='premise';interaction='INTRODUCED';related_key=''},
        [ordered]@{key='local-reinforce';id=$ids[1];observed_at='2026-10-13T08:00:01Z';turn_id=1;stage_id='s2';observation_type='SYCOPHANTIC_REINFORCEMENT';confidence=$null;excerpt='accept it';interaction='REINFORCED';related_key='user-frame'},
        [ordered]@{key='frontier-counter';id=$ids[2];observed_at='2026-10-13T08:00:02Z';turn_id=1;stage_id='s3';observation_type='COUNTEREVIDENCE_INTRODUCED';confidence=$null;excerpt='Counterevidence';interaction='CHALLENGED';related_key='user-frame'},
        [ordered]@{key='final-challenge';id=$ids[3];observed_at='2026-10-13T08:00:03Z';turn_id=1;stage_id='s4';observation_type='BIAS_CHALLENGED';confidence=$null;excerpt='test the premise';interaction='CORRECTED';related_key='local-reinforce'}
    )
}
$planPath=Join-Path $root 'plan.json';WriteJson $planPath $plan

$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
$endpoint='http://127.0.0.1:'+$port
$rootPassword=[guid]::NewGuid().ToString('N')
$runtimePassword=[guid]::NewGuid().ToString('N')
$admin=New-LfoEpistemicConnection $endpoint (Credential 'test_root' $rootPassword) -Bootstrap
$conn=New-LfoEpistemicConnection $endpoint (Credential 'lfo_r1' $runtimePassword)
$script:server=$null
function StartServer {
    $oldUser=$env:SURREAL_USER;$oldPass=$env:SURREAL_PASS
    try {
        $env:SURREAL_USER='test_root';$env:SURREAL_PASS=$rootPassword
        $db='rocksdb://'+(Join-Path $root 'db').Replace('\','/')
        $args=@('start','--bind',('127.0.0.1:'+$port),'--query-timeout','3s','--deny-guests','--deny-scripting','--deny-net','--log','warn',('"'+$db+'"'))
        $script:server=Start-Process -FilePath $SurrealBinary -ArgumentList $args -PassThru -RedirectStandardOutput (Join-Path $root 'server.out') -RedirectStandardError (Join-Path $root 'server.err')
    } finally {$env:SURREAL_USER=$oldUser;$env:SURREAL_PASS=$oldPass}
    $ready=$false
    for($i=0;$i -lt 60;$i++){
        if($script:server.HasExited){throw ('Server failed; see '+$root)}
        try{$null=Invoke-RestMethod ($endpoint+'/ready') -TimeoutSec 1;$ready=$true;break}catch{Start-Sleep -Milliseconds 150}
    }
    Assert $ready 'Server readiness timeout'
}
function StopServer {if($script:server -and -not $script:server.HasExited){Stop-Process -Id $script:server.Id -Force;$script:server.WaitForExit();$script:server.Dispose();$script:server=$null}}

try {
    StartServer
    Initialize-LfoEpistemicSchema $admin (Credential 'lfo_r1' $runtimePassword)

    $dry=Invoke-LfoEpistemicAnnotationPlan -PlanPath $planPath -LogDirectory $logs -ValidateOnly
    Assert ($dry.Validated -and -not $dry.WriteAttempted -and $dry.Count -eq 4) 'Dry-run validation failed'
    Assert ((Find-LfoEpistemicObservations $conn $store 1).Items.Count -eq 0) 'Dry-run wrote observations'

    $first=Invoke-LfoEpistemicAnnotationPlan -PlanPath $planPath -LogDirectory $logs -Connection $conn
    Assert (@($first.Items|Where-Object outcome -eq 'CREATED').Count -eq 4) 'First plan execution did not create four rows'

    $second=Invoke-LfoEpistemicAnnotationPlan -PlanPath $planPath -LogDirectory $logs -Connection $conn
    Assert (@($second.Items|Where-Object outcome -eq 'ALREADY_EXISTS').Count -eq 4) 'Plan retry was not idempotent'

    $all=Find-LfoEpistemicObservations $conn $store 1
    Assert ($all.Items.Count -eq 4) 'Expected four stored observations'
    Assert ((Find-LfoEpistemicObservations $conn $store 1 -Actor USER).Items.Count -eq 1 -and (Find-LfoEpistemicObservations $conn $store 1 -Actor LOCAL).Items.Count -eq 1 -and (Find-LfoEpistemicObservations $conn $store 1 -Actor FRONTIER).Items.Count -eq 1 -and (Find-LfoEpistemicObservations $conn $store 1 -Actor FINAL).Items.Count -eq 1) 'Actor coverage mismatch'
    $local=@($all.Items|Where-Object observation_id -eq $ids[1])[0]
    Assert ($local.related_observation_id -ceq $ids[0] -and $local.interaction -ceq 'REINFORCED') 'Related observation linkage mismatch'
    Assert ((Get-FileHash -LiteralPath $l0path -Algorithm SHA256).Hash -ceq $l0hash) 'L0 transcript mutated'

    $bad=$plan|ConvertTo-Json -Depth 10|ConvertFrom-Json;$bad.schema='bad';$badPath=Join-Path $root 'bad-schema.json';WriteJson $badPath $bad
    Reject {Invoke-LfoEpistemicAnnotationPlan -PlanPath $badPath -LogDirectory $logs -ValidateOnly} 'Bad schema accepted'

    $bad=$plan|ConvertTo-Json -Depth 10|ConvertFrom-Json;$bad.observations[1].key='user-frame';$badPath=Join-Path $root 'bad-duplicate.json';WriteJson $badPath $bad
    Reject {Invoke-LfoEpistemicAnnotationPlan -PlanPath $badPath -LogDirectory $logs -ValidateOnly} 'Duplicate key accepted'

    $bad=$plan|ConvertTo-Json -Depth 10|ConvertFrom-Json;$bad.observations[0].related_key='local-reinforce';$bad.observations[0].interaction='REINFORCED';$badPath=Join-Path $root 'bad-forward.json';WriteJson $badPath $bad
    Reject {Invoke-LfoEpistemicAnnotationPlan -PlanPath $badPath -LogDirectory $logs -ValidateOnly} 'Forward relation accepted'

    $bad=$plan|ConvertTo-Json -Depth 10|ConvertFrom-Json;$bad.observations[0].excerpt='not present in source';$badPath=Join-Path $root 'bad-excerpt.json';WriteJson $badPath $bad
    Reject {Invoke-LfoEpistemicAnnotationPlan -PlanPath $badPath -LogDirectory $logs -ValidateOnly} 'Invented excerpt accepted'

    [pscustomobject]@{PASS=$true;Checks=$script:checks;ModelCalls=0;ProductionMemoryTouched=$false;Evidence=$root}
    Write-Host ('R2_ANNOTATION_WORKFLOW_PASS: '+$script:checks+' checks; ModelCalls=0; ProductionMemoryTouched=False; Evidence='+$root)
} finally {StopServer}
