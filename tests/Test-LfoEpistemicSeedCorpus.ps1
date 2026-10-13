param([Parameter(Mandatory)][string]$SurrealBinary)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/LfoEpistemicStore.ps1')
. (Join-Path $PSScriptRoot '../src/LfoEpistemicAnnotationWorkflow.ps1')

$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Credential([string]$User,[string]$Password){New-Object Management.Automation.PSCredential($User,(ConvertTo-SecureString $Password -AsPlainText -Force))}

$SurrealBinary=(Resolve-Path -LiteralPath $SurrealBinary).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('LFO-l4-r2b-'+[guid]::NewGuid().ToString('N'))
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

    $dry=Invoke-LfoEpistemicAnnotationPlan -PlanPath $planPath -LogDirectory $logs -ValidateOnly
    Assert ($dry.Count -eq 17 -and -not $dry.WriteAttempted) 'Seed dry-run mismatch'
    Assert ((Find-LfoEpistemicObservations $conn $store 1).Items.Count -eq 0) 'Seed dry-run wrote data'

    $first=Invoke-LfoEpistemicAnnotationPlan -PlanPath $planPath -LogDirectory $logs -Connection $conn
    Assert (@($first.Items|Where-Object outcome -eq 'CREATED').Count -eq 17) 'Seed create count mismatch'

    $all=@((Find-LfoEpistemicObservations $conn $store 1 -Limit 50).Items)
    Assert ($all.Count -eq 17) 'Seed readback count mismatch'
    Assert (@($all.actor|Sort-Object -Unique).Count -eq 4) 'Seed does not cover all four actors'
    Assert (@($all.interaction|Where-Object{$_}|Sort-Object -Unique).Count -eq 5) 'Seed does not cover all five interaction values'
    Assert (@($all.observation_type|Sort-Object -Unique).Count -ge 8) 'Seed type diversity too low'
    Assert (@($all|Where-Object related_observation_id).Count -eq 11) 'Seed related-link count mismatch'

    $resolved=0
    foreach($item in $all){
        $source=@{}
        foreach($p in $item.source.PSObject.Properties){$source[$p.Name]=$p.Value}
        $r=Resolve-LfoEpistemicSource -LogDirectory $logs -Source $source
        if($r.ContentSHA256 -cne [string]$item.source.content_sha256){throw 'Resolved source hash mismatch'}
        $resolved++
    }
    Assert ($resolved -eq 17) 'Not all seed observations resolved to L0'

    $retry=Invoke-LfoEpistemicAnnotationPlan -PlanPath $planPath -LogDirectory $logs -Connection $conn
    Assert (@($retry.Items|Where-Object outcome -eq 'ALREADY_EXISTS').Count -eq 17) 'Seed retry not idempotent'
    Assert ((Get-FileHash -LiteralPath $l0path -Algorithm SHA256).Hash -ceq $l0hash) 'Seed L0 mutated'

    $byActor=[ordered]@{}
    foreach($g in ($all|Group-Object actor|Sort-Object Name)){$byActor[$g.Name]=$g.Count}
    $byType=[ordered]@{}
    foreach($g in ($all|Group-Object observation_type|Sort-Object Name)){$byType[$g.Name]=$g.Count}
    $byInteraction=[ordered]@{}
    foreach($g in ($all|Group-Object interaction|Sort-Object Name)){$byInteraction[$g.Name]=$g.Count}
    $report=[ordered]@{
        schema='lfo-r2-seed-report-v1'
        synthetic_fixture=$true
        turns=6
        observations=$all.Count
        provenance_resolved=$resolved
        related_links=@($all|Where-Object related_observation_id).Count
        by_actor=$byActor
        by_type=$byType
        by_interaction=$byInteraction
        model_calls=0
        production_memory_touched=$false
        interpretation='Engineering corpus only; not behavioral prevalence or detector-quality evidence.'
    }
    $reportPath=Join-Path $root 'r2-seed-report.json'
    [IO.File]::WriteAllText($reportPath,(($report|ConvertTo-Json -Depth 8)+"`n"),(New-Object Text.UTF8Encoding($false)))
    Assert (Test-Path -LiteralPath $reportPath) 'Seed report missing'

    Write-Host ('R2_SEED_CORPUS_PASS: observations=17; turns=6; actors=4; interactions=5; provenance=17/17; links=11; ModelCalls=0; ProductionMemoryTouched=False; Evidence='+$root)
    [pscustomobject]@{PASS=$true;Checks=$script:checks;Observations=17;Turns=6;ProvenanceResolved=17;RelatedLinks=11;ModelCalls=0;ProductionMemoryTouched=$false;Evidence=$root}
}finally{StopServer}
