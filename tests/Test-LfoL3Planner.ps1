# L3-R3 offline acceptance: tag-driven candidate narrowing, safe dedupe and context budget.
# TEMP-only. No Ollama, network, production memory or Qwen runtime integration.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
foreach ($relative in @('src\LfoMemoryStore.ps1','src\LfoL3Store.ps1','src\LfoL3Planner.ps1')) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $repoRoot $relative),[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        throw ("Syntax FAIL {0}: {1}" -f $relative,(($errors | ForEach-Object Message) -join '; '))
    }
}
. (Join-Path $repoRoot 'src\LfoMemoryStore.ps1')
. (Join-Path $repoRoot 'src\LfoL3Store.ps1')
. (Join-Path $repoRoot 'src\LfoL3Planner.ps1')

$root = Join-Path $env:TEMP ('LFO-l3-r3-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $root)
$db = Open-LfoL3Store (Join-Path $root 'l3-index.db')
try {
    foreach ($r in @(
        @('topic','lfo','LFO',100,'r3-topic'),
        @('topic','retrocomputing','Amiga',100,'r3-topic'),
        @('entity','orion','ORION',100,'r3-entity'),
        @('kind','configuration','OS',100,'r3-kind'),
        @('kind','configuration','run',90,'r3-kind'),
        @('kind','decision','decided',100,'r3-kind')
    )) {
        Set-LfoL3TermRule $db $r[0] $r[1] $r[2] ([int]$r[3]) $r[4] $true
    }

    $l0os = Set-LfoL3Item $db 'conversation:1' 'L0' 'turn:10' 10 'eq:orion-os'
    $l2os = Set-LfoL3Item $db 'conversation:1' 'L2' 'fact:os' 10 'eq:orion-os'
    $l2ram = Set-LfoL3Item $db 'conversation:1' 'L2' 'fact:ram' 11 'eq:orion-ram'
    $decision = Set-LfoL3Item $db 'conversation:1' 'L0' 'turn:12' 12 'eq:lfo-decision'
    $retro = Set-LfoL3Item $db 'conversation:1' 'L0' 'turn:13' 13 'eq:retro-amiga'
    $excluded = Set-LfoL3Item $db 'conversation:1' 'L0' 'turn:14' 14 'eq:orion-old'

    foreach ($item in @($l0os,$l2os,$l2ram,$decision,$excluded)) {
        [void](Set-LfoL3Facet $db $item.id 'topic' 'lfo' 1 'r3-seed')
    }
    foreach ($item in @($l0os,$l2os,$l2ram,$excluded)) {
        [void](Set-LfoL3Facet $db $item.id 'entity' 'orion' 1 'r3-seed')
    }
    foreach ($item in @($l0os,$l2os,$l2ram,$excluded)) {
        [void](Set-LfoL3Facet $db $item.id 'kind' 'configuration' 1 'r3-seed')
    }
    [void](Set-LfoL3Facet $db $decision.id 'kind' 'decision' 1 'r3-seed')
    [void](Set-LfoL3Facet $db $retro.id 'topic' 'retrocomputing' 1 'r3-seed')
    [void](Set-LfoL3Facet $db $excluded.id 'retrieval' 'exclude' 1 'r3-seed')
    [void](Set-LfoL3Facet $db $l2os.id 'retrieval' 'priority' 1 'r3-seed')

    $query = 'For LFO, what OS does ORION run?'
    $classification = Get-LfoL3Classification $db $query
    if ($classification.Status -ne 'ok') { throw 'R3 query did not classify.' }

    $evidence = @(
        [pscustomobject]@{ SourceLayer='L0'; SourceRef='turn:10'; Text='Earlier discussion: ORION runs Debian 13 as the current operating system.' },
        [pscustomobject]@{ SourceLayer='L2'; SourceRef='fact:os'; Text='ORION.os = Debian 13' },
        [pscustomobject]@{ SourceLayer='L2'; SourceRef='fact:ram'; Text='ORION.ram_gb = 64' },
        [pscustomobject]@{ SourceLayer='L0'; SourceRef='turn:12'; Text='We decided that L3 should use a separate SQLite index.' },
        [pscustomobject]@{ SourceLayer='L0'; SourceRef='turn:13'; Text='Amiga 1200 uses Kickstart ROM.' },
        [pscustomobject]@{ SourceLayer='L0'; SourceRef='turn:14'; Text='Old ORION operating-system note that must be excluded.' }
    )

    $plan = New-LfoL3ContextPlan $db 'conversation:1' $query $classification $evidence 2 80
    if ($plan.Status -ne 'ok') { throw "R3 plan status: $($plan.Status)" }
    if ($plan.SelectedCount -gt 2 -or $plan.PacketChars -gt 80) { throw 'R3 budget invariant failed.' }
    if ($plan.Packet -notmatch '^ORION\.os = Debian 13') { throw ('R3 failed to prefer compact L2 OS evidence: ' + $plan.Packet) }
    if ($plan.Packet -match 'Earlier discussion|Amiga|must be excluded') { throw 'R3 packet leaked duplicate/irrelevant/excluded evidence.' }
    if ($plan.Packet -match 'topic|entity|kind|source_ref|retrieval') { throw 'R3 internal metadata leaked into model-visible packet.' }
    if ($plan.DuplicateDrops -lt 1) { throw 'R3 did not deduplicate exact-equivalent L0/L2 evidence.' }
    if ($plan.InputCandidateChars -le $plan.PacketChars -or $plan.DroppedChars -le 0) {
        throw 'R3 did not reduce candidate evidence characters.'
    }

    $unknownClass = Get-LfoL3Classification $db 'What happened yesterday?'
    $fallback = New-LfoL3ContextPlan $db 'conversation:1' 'What happened yesterday?' $unknownClass $evidence 2 80
    if ($fallback.Status -ne 'no_query_facets' -or $fallback.SelectedCount -ne 0 -or $fallback.Packet -ne '') {
        throw 'R3 unknown query did not request baseline fallback.'
    }

    $tiny = New-LfoL3ContextPlan $db 'conversation:1' $query $classification $evidence 2 8
    if ($tiny.Status -ne 'budget_empty' -or $tiny.Packet -ne '') {
        throw 'R3 tiny budget should return no partial evidence.'
    }

    $crossClass = Get-LfoL3Classification $db 'Compare LFO with Amiga.'
    $crossCandidates = @(Get-LfoL3CandidateItems $db 'conversation:1' $crossClass 48)
    if (@($crossCandidates | Where-Object { $_.SourceRef -eq 'turn:13' }).Count -ne 1 -or
        @($crossCandidates | Where-Object { $_.SourceRef -eq 'turn:12' }).Count -ne 1) {
        throw 'R3 cross-topic candidate union failed.'
    }

    # Regression: equally relevant L0 and L2 evidence without an equivalence
    # fingerprint must prefer L2 authority over lexical verbosity.
    Set-LfoL3TermRule $db 'entity' 'vega' 'VEGA' 100 'r3-entity' $true
    $l0vega = Set-LfoL3Item $db 'conversation:1' 'L0' 'turn:15' 15 $null
    $l2vega = Set-LfoL3Item $db 'conversation:1' 'L2' 'fact:vega-os' 15 $null
    foreach ($item in @($l0vega,$l2vega)) {
        [void](Set-LfoL3Facet $db $item.id 'topic' 'lfo' 1 'r3-seed')
        [void](Set-LfoL3Facet $db $item.id 'entity' 'vega' 1 'r3-seed')
        [void](Set-LfoL3Facet $db $item.id 'kind' 'configuration' 1 'r3-seed')
    }
    $vegaQuery = 'For LFO, what OS does VEGA run?'
    $vegaClass = Get-LfoL3Classification $db $vegaQuery
    $vegaEvidence = @(
        [pscustomobject]@{ SourceLayer='L0'; SourceRef='turn:15'; Text='VEGA now definitely runs Fedora 42 as the operating system and this is a verbose narrative.' },
        [pscustomobject]@{ SourceLayer='L2'; SourceRef='fact:vega-os'; Text='VEGA.os = Fedora 42' }
    )
    $vegaPlan = New-LfoL3ContextPlan $db 'conversation:1' $vegaQuery $vegaClass $vegaEvidence 1 200
    if ($vegaPlan.Status -ne 'ok' -or $vegaPlan.SelectedCount -ne 1 -or
        $vegaPlan.Selected[0].SourceLayer -ne 'L2' -or $vegaPlan.Packet -notmatch '^VEGA\.os = Fedora 42
        PASS = $true
        CandidateCount = $plan.CandidateCount
        ResolvedCandidates = $plan.ResolvedCandidates
        SelectedCount = $plan.SelectedCount
        CandidateChars = $plan.InputCandidateChars
        PacketChars = $plan.PacketChars
        DroppedChars = $plan.DroppedChars
        DuplicateDrops = $plan.DuplicateDrops
        BudgetDrops = $plan.BudgetDrops
        InternalMetadataVisible = $false
        UnknownFallsBack = $true
        NoPartialTruncation = $true
        CrossTopicUnion = $true
        ModelCalls = 0
        ProductionMemoryTouched = $false
        TempFixture = $root
    } | Format-List
} finally {
    Close-LfoSqliteDatabase $db
}
) {
        throw ('R3 authority ordering failed: ' + ($vegaPlan | ConvertTo-Json -Depth 5 -Compress))
    }

    [pscustomobject]@{
        PASS = $true
        CandidateCount = $plan.CandidateCount
        ResolvedCandidates = $plan.ResolvedCandidates
        SelectedCount = $plan.SelectedCount
        CandidateChars = $plan.InputCandidateChars
        PacketChars = $plan.PacketChars
        DroppedChars = $plan.DroppedChars
        DuplicateDrops = $plan.DuplicateDrops
        BudgetDrops = $plan.BudgetDrops
        InternalMetadataVisible = $false
        UnknownFallsBack = $true
        NoPartialTruncation = $true
        CrossTopicUnion = $true
        ModelCalls = 0
        ProductionMemoryTouched = $false
        TempFixture = $root
    } | Format-List
} finally {
    Close-LfoSqliteDatabase $db
}
