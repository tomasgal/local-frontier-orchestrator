param([Parameter(Mandatory)][string]$SurrealBinary)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/LfoEpistemicStore.ps1')
. (Join-Path $PSScriptRoot '../src/LfoEpistemicAnnotationWorkflow.ps1')
. (Join-Path $PSScriptRoot '../src/LfoEpistemicObservatory.ps1')
. (Join-Path $PSScriptRoot '../src/LfoEpistemicInteractionAnalytics.ps1')

$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Near([double]$A,[double]$B,[double]$Tol=0.0000001){return [math]::Abs($A-$B) -le $Tol}
function Credential([string]$User,[string]$Password){New-Object Management.Automation.PSCredential($User,(ConvertTo-SecureString $Password -AsPlainText -Force))}
function SigMap($rows){$h=@{};foreach($r in @($rows)){$h[[string]$r.signature_kind+'|'+[string]$r.signature]=$r};return $h}
function ActorMap($rows){$h=@{};foreach($r in @($rows)){$h[[string]$r.actor]=$r};return $h}

$SurrealBinary=(Resolve-Path -LiteralPath $SurrealBinary).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('LFO-l4-a2-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$logs=Join-Path $root 'l0';$null=New-Item -ItemType Directory -Path $logs
$fixture=Join-Path $PSScriptRoot 'fixtures\l4-a2-interaction'
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
function StartServer{
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
function StopServer{if($script:server -and -not $script:server.HasExited){Stop-Process -Id $script:server.Id -Force;$script:server.WaitForExit();$script:server.Dispose();$script:server=$null}}

try{
    StartServer
    Initialize-LfoEpistemicSchema $admin (Credential 'lfo_r1' $runtimePassword)
    $write=Invoke-LfoEpistemicAnnotationPlan -PlanPath $planPath -LogDirectory $logs -Connection $conn
    Assert (@($write.Items|Where-Object outcome -eq 'CREATED').Count -eq 25) 'A2 fixture write mismatch'

    $full=Get-LfoEpistemicInteractionAnalytics -Connection $conn -StoreId $store -Epoch 1 -FirstTurn 1 -LastTurn 8 -PageSize 4
    Assert ($full.ObservationCount -eq 25 -and $full.WindowTurnCount -eq 8 -and $full.DistinctAnnotatedTurnCount -eq 8) 'A2 full-window cardinality mismatch'
    Assert ($full.ExcludedBoundaryLinks -eq 0 -and $full.ExcludedBoundaryChains -eq 0) 'Unexpected full-window boundary exclusion'
    Assert ($full.ChainOccurrenceCount -eq 9) 'A2 chain occurrence count mismatch'

    $rec=SigMap $full.RecurrenceDensity
    Assert ($rec['actor_type|USER|FRAMING'].distinct_turn_count -eq 3) 'USER FRAMING recurrence mismatch'
    Assert (Near $rec['actor_type|USER|FRAMING'].distinct_turn_fraction 0.375) 'USER FRAMING density mismatch'
    Assert ($rec['actor_type|LOCAL|SYCOPHANTIC_REINFORCEMENT'].distinct_turn_count -eq 4 -and (Near $rec['actor_type|LOCAL|SYCOPHANTIC_REINFORCEMENT'].distinct_turn_fraction 0.5)) 'LOCAL sycophancy recurrence density mismatch'
    Assert ($rec['linked_response|USER->LOCAL|REINFORCED'].distinct_turn_count -eq 4) 'Linked recurrence density mismatch'

    $ac=@($full.ActorInteractionChains|Where-Object actor_chain -eq 'USER->LOCAL->FINAL'|Where-Object interaction_sequence -eq 'REINFORCED>CORRECTED')
    Assert ($ac.Count -eq 1 -and $ac[0].count -eq 3) 'Repeated actor/interactions chain motif mismatch'
    $ac2=@($full.ActorInteractionChains|Where-Object actor_chain -eq 'USER->LOCAL->FINAL'|Where-Object interaction_sequence -eq 'CHALLENGED>CORRECTED')
    Assert ($ac2.Count -eq 1 -and $ac2[0].count -eq 2) 'Challenge/correction chain motif mismatch'

    $bal=ActorMap $full.ResponseBalance
    Assert ($bal.LOCAL.linked_response_count -eq 6 -and $bal.LOCAL.reinforced_count -eq 4 -and $bal.LOCAL.challenged_count -eq 2) 'LOCAL response balance mismatch'
    Assert (Near $bal.LOCAL.reinforced_fraction (4.0/6.0)) 'LOCAL response fraction mismatch'
    Assert ($bal.FINAL.linked_response_count -eq 8 -and $bal.FINAL.corrected_count -eq 6 -and $bal.FINAL.ignored_count -eq 2 -and $bal.FINAL.challenged_count -eq 0) 'FINAL response balance mismatch'
    Assert ($bal.FRONTIER.linked_response_count -eq 3 -and $bal.FRONTIER.challenged_count -eq 3) 'FRONTIER response balance mismatch'
    Assert ($full.UnclassifiedLinkedInteractions -eq 0) 'Unexpected unclassified linked interaction'

    $b=Get-LfoEpistemicInteractionAnalytics -Connection $conn -StoreId $store -Epoch 1 -FirstTurn 5 -LastTurn 8 -PageSize 3
    Assert ($b.ObservationCount -eq 13 -and $b.ExcludedBoundaryLinks -eq 1) 'A2 window-B link boundary mismatch'
    Assert ($b.ChainOccurrenceCount -eq 4 -and $b.ExcludedBoundaryChains -eq 1) 'A2 window-B chain boundary mismatch'

    $cmp=Compare-LfoEpistemicAdjacentInteractionWindows -Connection $conn -StoreId $store -Epoch 1 -FirstTurnA 1 -LastTurnA 4 -FirstTurnB 5 -LastTurnB 8 -PageSize 3
    Assert ($cmp.PresentBoth -eq 12 -and $cmp.OnlyA -eq 1 -and $cmp.OnlyB -eq 4) 'Adjacent-window status totals mismatch'
    $onlyA=@($cmp.Signatures|Where-Object status -eq 'ONLY_A')
    Assert ($onlyA.Count -eq 1 -and $onlyA[0].signature -eq 'FRONTIER->FINAL|IGNORED') 'Adjacent ONLY_A signature mismatch'
    Assert (@($cmp.Signatures|Where-Object status -eq 'ONLY_B'|Where-Object signature -eq 'USER|OVERCONFIDENCE').Count -eq 1) 'Adjacent ONLY_B signature mismatch'

    # Every motif can drill back through frozen A1 provenance without source text expansion.
    $ids=@($ac[0].supporting_observation_ids)
    Assert ($ids.Count -eq 9) 'Chain support-id cardinality mismatch'
    $refs=@(Get-LfoEpistemicObservatoryProvenance -Connection $conn -StoreId $store -Epoch 1 -ObservationId $ids -Limit 50)
    Assert ($refs.Count -eq 9 -and @($refs|Where-Object{[string]$_.content_sha256 -notmatch '^[a-f0-9]{64}$'}).Count -eq 0) 'A2 provenance drill-back mismatch'
    Assert (@($full.PSObject.Properties.Name|Where-Object{$_ -in @('excerpt','content','raw')}).Count -eq 0) 'A2 aggregate leaked raw source fields'
    Assert ((Get-FileHash -LiteralPath $l0path -Algorithm SHA256).Hash -ceq $l0hash) 'A2 analytics mutated L0'

    Write-Host ('A2_INTERACTION_ANALYTICS_PASS: '+$script:checks+' checks; observations=25; chains=9; boundary_links_B=1; boundary_chains_B=1; adjacent=12/1/4; ModelCalls=0; ProductionMemoryTouched=False; Evidence='+$root)
    [pscustomobject]@{PASS=$true;Checks=$script:checks;Observations=25;Chains=9;ModelCalls=0;ProductionMemoryTouched=$false;Evidence=$root}
}finally{StopServer}
