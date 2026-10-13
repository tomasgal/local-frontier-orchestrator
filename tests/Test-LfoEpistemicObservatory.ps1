param([Parameter(Mandatory)][string]$SurrealBinary)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/LfoEpistemicStore.ps1')
. (Join-Path $PSScriptRoot '../src/LfoEpistemicAnnotationWorkflow.ps1')
. (Join-Path $PSScriptRoot '../src/LfoEpistemicObservatory.ps1')

$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Block,[string]$Message){$script:checks++;try{& $Block;throw $Message}catch{if($_.Exception.Message -ceq $Message){throw}}}
function Credential([string]$User,[string]$Password){New-Object Management.Automation.PSCredential($User,(ConvertTo-SecureString $Password -AsPlainText -Force))}
function Map($rows){$h=@{};foreach($r in @($rows)){$h[[string]$r.name]=$r};return $h}
function RecMap($rows){$h=@{};foreach($r in @($rows)){$h[[string]$r.signature]=$r};return $h}

$SurrealBinary=(Resolve-Path -LiteralPath $SurrealBinary).Path
$root=Join-Path ([IO.Path]::GetTempPath()) ('LFO-l4-a1b-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$logs=Join-Path $root 'l0';$null=New-Item -ItemType Directory -Path $logs
$fixture=Join-Path $PSScriptRoot 'fixtures\l4-a1-observatory'
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
    Assert (@($write.Items|Where-Object outcome -eq 'CREATED').Count -eq 12) 'A1 fixture write mismatch'

    # Q1 + Q2 + Q3, deliberately tiny page size to exercise pagination.
    $a=Get-LfoEpistemicObservatoryWindow -Connection $conn -StoreId $store -Epoch 1 -FirstTurn 1 -LastTurn 3 -PageSize 3
    Assert ($a.ObservationCount -eq 6 -and $a.DistinctAnnotatedTurnCount -eq 3) 'Window A cardinality mismatch'
    $actor=Map $a.CountsByActor
    Assert ($actor.USER.count -eq 3 -and $actor.LOCAL.count -eq 3) 'Window A actor counts mismatch'
    $int=Map $a.CountsByInteraction
    Assert ($int.INTRODUCED.count -eq 3 -and $int.REINFORCED.count -eq 2 -and $int.CHALLENGED.count -eq 1) 'Window A interaction counts mismatch'
    Assert ($a.ExcludedBoundaryLinks -eq 0) 'Unexpected boundary link in window A'
    $actorTransition=Map $a.ParentActorToChildActor
    $childInteraction=Map $a.ChildInteraction
    Assert ($actorTransition['USER->LOCAL'].count -eq 3) 'Semantic USER->LOCAL direction/count mismatch'
    Assert ($childInteraction.REINFORCED.count -eq 2 -and $childInteraction.CHALLENGED.count -eq 1) 'Child interaction transition counts mismatch'
    $ra=RecMap $a.Recurrence
    Assert ($ra['LOCAL|SYCOPHANTIC_REINFORCEMENT'].distinct_turn_count -eq 2) 'Actor/type recurrence mismatch'
    Assert ($ra['USER->LOCAL|REINFORCED'].distinct_turn_count -eq 2) 'Linked recurrence mismatch'

    # Chronology must be source turn order even though observed_at runs backwards.
    $provChron=Get-LfoEpistemicObservatoryProvenance -Connection $conn -StoreId $store -Epoch 1 -ObservationId @($a.SupportingObservationIds) -Limit 50
    Assert ($provChron[0].turn_id -eq 1 -and $provChron[-1].turn_id -eq 3) 'A1 chronology incorrectly followed observed_at'

    # Boundary semantics: t6 child points to a t4 parent, excluded from 5..6 window.
    $boundary=Get-LfoEpistemicObservatoryWindow -Connection $conn -StoreId $store -Epoch 1 -FirstTurn 5 -LastTurn 6 -PageSize 4
    Assert ($boundary.ObservationCount -eq 4 -and $boundary.ExcludedBoundaryLinks -eq 1) 'Cross-window link boundary mismatch'
    $boundaryInteraction=Map $boundary.ChildInteraction
    Assert (-not $boundaryInteraction.ContainsKey('IGNORED')) 'Cross-window link incorrectly counted as transition'

    # Window B 4..6 has all links in scope, including cross-turn t4 -> t6.
    $b=Get-LfoEpistemicObservatoryWindow -Connection $conn -StoreId $store -Epoch 1 -FirstTurn 4 -LastTurn 6 -PageSize 4
    Assert ($b.ObservationCount -eq 6 -and $b.ExcludedBoundaryLinks -eq 0) 'Window B cardinality/boundary mismatch'
    $rb=RecMap $b.Recurrence
    Assert ($rb['LOCAL|OVERCONFIDENCE'].distinct_turn_count -eq 2 -and $rb['FRONTIER|COUNTEREVIDENCE_INTRODUCED'].distinct_turn_count -eq 2) 'Window B recurrence mismatch'

    # Q4.
    $cmp=Compare-LfoEpistemicObservatoryWindows -Connection $conn -StoreId $store -Epoch 1 -FirstTurnA 1 -LastTurnA 3 -FirstTurnB 4 -LastTurnB 6 -PageSize 3
    $td=Map $cmp.CountDeltaByObservationType
    Assert ($td.OVERCONFIDENCE.delta -eq 2 -and $td.SYCOPHANTIC_REINFORCEMENT.delta -eq -2 -and $td.COUNTEREVIDENCE_INTRODUCED.delta -eq 2) 'Type delta mismatch'
    $id=Map $cmp.CountDeltaByInteraction
    Assert ($id.INTRODUCED.delta -eq 0 -and $id.REINFORCED.delta -eq -2 -and $id.CORRECTED.delta -eq 1 -and $id.IGNORED.delta -eq 1) 'Interaction delta mismatch'
    $rd=RecMap $cmp.DistinctTurnDeltaByRecurrenceSignature
    Assert ($rd['LOCAL|SYCOPHANTIC_REINFORCEMENT'].delta -eq -2 -and $rd['USER->LOCAL|REINFORCED'].delta -eq -2 -and $rd['LOCAL|OVERCONFIDENCE'].delta -eq 2 -and $rd['FRONTIER|COUNTEREVIDENCE_INTRODUCED'].delta -eq 2) 'Recurrence delta mismatch'
    Reject {Compare-LfoEpistemicObservatoryWindows -Connection $conn -StoreId $store -Epoch 1 -FirstTurnA 1 -LastTurnA 4 -FirstTurnB 4 -LastTurnB 6} 'Overlapping comparison accepted'

    # Q5: bounded references only, no excerpt/content.
    $ids=@($childInteraction.REINFORCED.supporting_observation_ids|Select-Object -First 2)
    $refs=@(Get-LfoEpistemicObservatoryProvenance -Connection $conn -StoreId $store -Epoch 1 -ObservationId $ids -Limit 2)
    Assert ($refs.Count -eq $ids.Count) 'Provenance drill-back cardinality mismatch'
    Assert (@($refs|Where-Object{[string]$_.content_sha256 -notmatch '^[a-f0-9]{64}$'}).Count -eq 0) 'Provenance hash missing'
    Assert (@($refs[0].PSObject.Properties.Name|Where-Object{$_ -in @('excerpt','content','observed_at','model')}).Count -eq 0) 'Provenance drill-back leaked non-contract fields'
    Reject {Get-LfoEpistemicObservatoryProvenance -Connection $conn -StoreId $store -Epoch 1 -ObservationId @($ids+$ids) -Limit 1} 'Provenance bound not enforced'

    Assert ((Get-FileHash -LiteralPath $l0path -Algorithm SHA256).Hash -ceq $l0hash) 'A1 analytics mutated L0'
    Write-Host ('A1_OBSERVATORY_IMPLEMENTATION_PASS: '+$script:checks+' checks; Q1-Q5 exact; boundary=1; ModelCalls=0; ProductionMemoryTouched=False; Evidence='+$root)
    [pscustomobject]@{PASS=$true;Checks=$script:checks;Questions=5;ModelCalls=0;ProductionMemoryTouched=$false;Evidence=$root}
}finally{StopServer}
