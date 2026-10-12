# L3 automatic post-turn indexer acceptance.
# TEMP-only. No Ollama, network or production memory.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
foreach ($relative in @('src\LfoMemoryStore.ps1','src\LfoStructuredRetrieval.ps1','src\LfoL3Store.ps1','src\LfoL3Planner.ps1','src\LfoL3Runtime.ps1','src\LfoL3Indexer.ps1')) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $relative),[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw ("Syntax FAIL {0}: {1}" -f $relative,(($errors | ForEach-Object Message) -join '; ')) }
}

. (Join-Path $repoRoot 'src\LfoMemoryStore.ps1')
. (Join-Path $repoRoot 'src\LfoStructuredRetrieval.ps1')
. (Join-Path $repoRoot 'src\LfoL3Store.ps1')
. (Join-Path $repoRoot 'src\LfoL3Planner.ps1')
. (Join-Path $repoRoot 'src\LfoL3Runtime.ps1')
. (Join-Path $repoRoot 'src\LfoL3Indexer.ps1')

$root = Join-Path $env:TEMP ('LFO-l3-indexer-' + [guid]::NewGuid().ToString('N'))
$state = Join-Path $root 'state'
$logs = Join-Path $root 'logs'
[void](New-Item -ItemType Directory -Force -Path $state)
[void](New-Item -ItemType Directory -Force -Path $logs)
$l2Path = Join-Path $state 'l2-memory.db'
$l3Path = Join-Path $state 'l3-index.db'
$topicRules = @([pscustomobject]@{ Topic='lfo'; Terms=@('LFO','Local Frontier Orchestrator'); Priority=100 })

function Add-TestConversationTurn([int]$TurnId,[string]$User,[string]$Assistant) {
    $row = [ordered]@{ event='turn'; timestamp=(Get-Date).ToString('o'); turn_id=$TurnId; epoch=1; route='LOCAL'; user=$User; assistant=$Assistant }
    [IO.File]::AppendAllText((Join-Path $logs 'conversation-2026-10.jsonl'),($row | ConvertTo-Json -Compress) + [Environment]::NewLine)
}

$l2 = Open-LfoMemoryStore $l2Path
try {
    $first = Set-LfoMemoryAttribute $l2 'ORION' 'os' 'Debian 13' 1 'server' 'conversation:1'
    if ($first.Status -ne 'written') { throw "Turn1 L2 write failed: $($first.Status)" }
    $firstFact = @(Invoke-LfoSqliteQuery $l2 "SELECT id,subject_entity_id FROM current_facts WHERE scope_id='conversation:1' AND predicate='os';")[0]
} finally { Close-LfoSqliteDatabase $l2 }

Add-TestConversationTurn 1 'For LFO, ORION runs Debian 13.' 'Recorded.'
$r1 = Invoke-LfoL3PostTurnIndex 'For LFO, ORION runs Debian 13.' 'Recorded.' 1 1 $l2Path $l3Path $topicRules
if ($r1.Status -ne 'ok' -or -not $r1.TurnIndexed -or $r1.L2ItemsIndexed -ne 1) { throw ('Turn1 L3 indexing failed: ' + ($r1 | ConvertTo-Json -Compress)) }

$l3 = Open-LfoL3Store $l3Path
try {
    $entityKey = 'l2:' + [string][int64]$firstFact.subject_entity_id
    $c1 = Get-LfoL3Classification $l3 'For LFO, what OS does ORION run?'
    $topics = @($c1.Topics | ForEach-Object ValueKey)
    $entities = @($c1.Entities | ForEach-Object ValueKey)
    $kind = if ($null -eq $c1.Kind) { '' } else { [string]$c1.Kind.ValueKey }
    $predicates = @($c1.Predicates | ForEach-Object ValueKey)
    if ($topics -notcontains 'lfo' -or $entities -notcontains $entityKey -or
        $kind -ne 'configuration' -or $predicates -notcontains 'os') {
        throw ('Synced rules did not classify query: ' + ($c1 | ConvertTo-Json -Depth 6 -Compress))
    }

    $turnItem = @(Invoke-LfoSqliteQuery $l3 "SELECT id FROM l3_items WHERE source_layer='L0' AND source_ref='turn:1';")
    $factItem = @(Invoke-LfoSqliteQuery $l3 ("SELECT id FROM l3_items WHERE source_layer='L2' AND source_ref='fact:{0}';" -f [int64]$firstFact.id))
    if ($turnItem.Count -ne 1 -or $factItem.Count -ne 1) { throw 'Turn1 source refs were not indexed.' }

    $turnFacets = @(Get-LfoL3Facets $l3 $turnItem[0].id)
    $factFacets = @(Get-LfoL3Facets $l3 $factItem[0].id)
    if (@($turnFacets | Where-Object { $_.dimension -eq 'topic' -and $_.value_key -eq 'lfo' }).Count -ne 1) { throw 'L0 topic facet missing.' }
    if (@($turnFacets | Where-Object { $_.dimension -eq 'entity' -and $_.value_key -eq $entityKey }).Count -ne 1) { throw 'L0 entity facet missing.' }
    if (@($factFacets | Where-Object { $_.dimension -eq 'temporal' -and $_.value_key -eq 'current' }).Count -ne 1) { throw 'L2 current temporal facet missing.' }
    if (@($factFacets | Where-Object { $_.dimension -eq 'predicate' -and $_.value_key -eq 'os' }).Count -ne 1) { throw 'L2 predicate facet missing.' }
} finally { Close-LfoSqliteDatabase $l3 }

$l2 = Open-LfoMemoryStore $l2Path
try {
    $second = Set-LfoMemoryAttribute $l2 'ORION' 'os' 'Ubuntu 24.04' 2 'server' 'conversation:1'
    if ($second.Status -ne 'written') { throw "Turn2 L2 write failed: $($second.Status)" }
    $factsAfter = @(Invoke-LfoSqliteQuery $l2 "SELECT id,value_text,valid_to_turn,source_turn FROM facts WHERE scope_id='conversation:1' AND predicate='os' ORDER BY id;")
    if ($factsAfter.Count -ne 2) { throw 'Expected two OS history rows after correction.' }
    $oldId = [int64]$factsAfter[0].id
    $newId = [int64]$factsAfter[1].id
} finally { Close-LfoSqliteDatabase $l2 }

Add-TestConversationTurn 2 'For LFO, ORION now runs Ubuntu 24.04.' 'Updated.'
$r2 = Invoke-LfoL3PostTurnIndex 'For LFO, ORION now runs Ubuntu 24.04.' 'Updated.' 2 1 $l2Path $l3Path $topicRules
if ($r2.Status -ne 'ok' -or $r2.L2FactsTouched -ne 2 -or $r2.L2ItemsIndexed -ne 2) { throw ('Turn2 L3 indexing failed: ' + ($r2 | ConvertTo-Json -Compress)) }

$l3 = Open-LfoL3Store $l3Path
try {
    $oldItem = @(Invoke-LfoSqliteQuery $l3 ("SELECT id FROM l3_items WHERE source_layer='L2' AND source_ref='fact:{0}';" -f $oldId))[0]
    $newItem = @(Invoke-LfoSqliteQuery $l3 ("SELECT id FROM l3_items WHERE source_layer='L2' AND source_ref='fact:{0}';" -f $newId))[0]
    $oldFacets = @(Get-LfoL3Facets $l3 $oldItem.id)
    $newFacets = @(Get-LfoL3Facets $l3 $newItem.id)
    if (@($oldFacets | Where-Object { $_.dimension -eq 'temporal' -and $_.value_key -eq 'historical' }).Count -ne 1) { throw 'Old fact not historical.' }
    if (@($oldFacets | Where-Object { $_.dimension -eq 'retrieval' -and $_.value_key -eq 'exclude' }).Count -ne 1) { throw 'Old fact not excluded.' }
    if (@($newFacets | Where-Object { $_.dimension -eq 'temporal' -and $_.value_key -eq 'current' }).Count -ne 1) { throw 'New fact not current.' }
    if (@($newFacets | Where-Object { $_.dimension -eq 'retrieval' -and $_.value_key -eq 'exclude' }).Count -ne 0) { throw 'New fact incorrectly excluded.' }
} finally { Close-LfoSqliteDatabase $l3 }

$plan = Get-LfoL3RuntimeContextPlan 'For LFO, what OS does ORION run?' 'conversation:1' $l3Path $l2Path $logs 1 1 300
if ($plan.Status -ne 'ok' -or $plan.L2Count -ne 1 -or $plan.L2Text -notmatch 'ORION\.os = Ubuntu 24\.04' -or $plan.L2Text -match 'Debian 13') { throw ('Current-state runtime plan failed: ' + ($plan | ConvertTo-Json -Compress)) }

Add-TestConversationTurn 3 'Hello there.' 'Hello.'
$r3 = Invoke-LfoL3PostTurnIndex 'Hello there.' 'Hello.' 3 1 $l2Path $l3Path $topicRules
if ($r3.Status -ne 'ok' -or $r3.TurnIndexed) { throw 'Unclassified turn should remain absent from L3.' }

[pscustomobject]@{
    PASS = $true
    Turn1Indexed = $r1.TurnIndexed
    Turn2Indexed = $r2.TurnIndexed
    TopicRulesSynced = $r2.TopicRulesSynced
    EntityRulesSynced = $r2.EntityRulesSynced
    PredicateRulesSynced = $r2.PredicateRulesSynced
    L2FactsTouchedOnCorrection = $r2.L2FactsTouched
    OldFactHistoricalExcluded = $true
    NewFactCurrent = $true
    CurrentRuntimeValue = 'Ubuntu 24.04'
    UnknownTurnSkipped = (-not $r3.TurnIndexed)
    ModelCalls = 0
    ProductionMemoryTouched = $false
    TempFixture = $root
} | Format-List
