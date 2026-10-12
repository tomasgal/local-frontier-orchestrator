# L3-R1 offline acceptance: separate reconstructible SQLite metadata store.
# TEMP-only. No Ollama, network, production memory or L2 schema change.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

foreach ($relative in @('src\LfoMemoryStore.ps1','src\LfoL3Store.ps1')) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $repoRoot $relative),
        [ref]$tokens,
        [ref]$errors
    )
    if (@($errors).Count -gt 0) {
        throw ("Syntax FAIL {0}: {1}" -f $relative, (($errors | ForEach-Object Message) -join '; '))
    }
}

. (Join-Path $repoRoot 'src\LfoMemoryStore.ps1')
. (Join-Path $repoRoot 'src\LfoL3Store.ps1')

$root = Join-Path $env:TEMP ('LFO-l3-r1-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $root)
$l2Path = Join-Path $root 'l2-memory.db'
$l3Path = Join-Path $root 'l3-index.db'

# Positive control: create an isolated L2 database and one accepted fact.
$l2 = Open-LfoMemoryStore $l2Path
try {
    $l2Write = Set-LfoMemoryAttribute $l2 'ORION' 'os' 'Debian 13' 7 'server' 'conversation:1'
    if ($l2Write.Status -ne 'written') { throw "L2 positive control failed: $($l2Write.Status)" }
} finally {
    Close-LfoSqliteDatabase $l2
}
$l2HashBefore = (Get-FileHash -LiteralPath $l2Path -Algorithm SHA256).Hash

$l3 = Open-LfoL3Store $l3Path
try {
    $schema = @(Invoke-LfoSqliteQuery $l3 "SELECT value FROM l3_meta WHERE key='schema_version';")
    if ($schema.Count -ne 1 -or $schema[0].value -ne '2') {
        throw 'Unexpected L3 schema version.'
    }

    Start-LfoL3Transaction $l3
    try {
        $turn = Set-LfoL3Item $l3 'conversation:1' 'L0' 'turn:101' 101 'sha256:turn101'
        $fact = Set-LfoL3Item $l3 'conversation:1' 'L2' 'fact:1' 7 'sha256:fact1'

        [void](Set-LfoL3Facet $l3 $turn.id 'topic' 'LFO' 1 'r1-test')
        [void](Set-LfoL3Facet $l3 $turn.id 'topic' 'Retrocomputing' -1 'r1-test')
        [void](Set-LfoL3Facet $l3 $turn.id 'entity' 'ORION' 1 'r1-test')
        [void](Set-LfoL3Facet $l3 $turn.id 'kind' 'Decision' 1 'r1-test')
        [void](Set-LfoL3Facet $l3 $turn.id 'temporal' 'Current' 1 'r1-test')
        [void](Set-LfoL3Facet $l3 $turn.id 'topic' 'Temporary' 1 'r1-test')

        [void](Set-LfoL3Facet $l3 $fact.id 'topic' 'LFO' 1 'r1-test')
        [void](Set-LfoL3Facet $l3 $fact.id 'entity' 'l2:1' 1 'r1-test')
        [void](Set-LfoL3Facet $l3 $fact.id 'kind' 'Configuration' 1 'r1-test')
        [void](Set-LfoL3Facet $l3 $fact.id 'retrieval' 'Priority' 1 'r1-test')

        # Unknown is represented by absence, not by a synthetic zero tag.
        Remove-LfoL3Facet $l3 $turn.id 'topic' 'Temporary'

        Complete-LfoL3Transaction $l3
    } catch {
        Undo-LfoL3Transaction $l3
        throw
    }

    # Repeated indexing must update the same source row, not create a duplicate.
    $turnAgain = Set-LfoL3Item $l3 'conversation:1' 'L0' 'turn:101' 101 'sha256:turn101-v2'
    if ([int64]$turnAgain.id -ne [int64]$turn.id) {
        throw 'L3 source upsert created a duplicate item.'
    }

    # Same source_ref in a different scope is intentionally a different item.
    $turnOtherScope = Set-LfoL3Item $l3 'conversation:2' 'L0' 'turn:101' 101 'sha256:turn101'
    [void](Set-LfoL3Facet $l3 $turnOtherScope.id 'topic' 'LFO' 1 'r1-test')

    $positive = @(Get-LfoL3ItemsByFacet $l3 'conversation:1' 'topic' 'lfo' 1)
    $negative = @(Get-LfoL3ItemsByFacet $l3 'conversation:1' 'topic' 'retrocomputing' -1)
    $otherScope = @(Get-LfoL3ItemsByFacet $l3 'conversation:2' 'topic' 'lfo' 1)
    $removed = @(Get-LfoL3ItemsByFacet $l3 'conversation:1' 'topic' 'temporary' 1)
    $turnFacets = @(Get-LfoL3Facets $l3 $turn.id)
    $stats = Get-LfoL3StoreStats $l3

    if ($positive.Count -ne 2) { throw "Expected 2 positive LFO items in scope 1, got $($positive.Count)." }
    if ($negative.Count -ne 1 -or $negative[0].source_ref -ne 'turn:101') {
        throw 'Explicit negative topic membership failed.'
    }
    if ($otherScope.Count -ne 1) { throw 'L3 scope isolation failed.' }
    if ($removed.Count -ne 0) { throw 'Removed facet did not return to unknown/absent state.' }
    if (@($turnFacets | Where-Object { $_.dimension -eq 'topic' -and $_.value_key -eq 'temporary' }).Count -ne 0) {
        throw 'Unknown facet was persisted instead of represented by absence.'
    }
    if ($stats.Items -ne 3 -or $stats.Facets -ne 10) {
        throw ("Unexpected L3 counts: items={0}, facets={1}" -f $stats.Items,$stats.Facets)
    }

    Close-LfoSqliteDatabase $l3
    $l3 = Open-LfoL3Store $l3Path

    $restart = @(Get-LfoL3ItemsByFacet $l3 'conversation:1' 'entity' 'orion' 1)
    if ($restart.Count -ne 1 -or $restart[0].source_ref -ne 'turn:101') {
        throw 'L3 restart persistence failed.'
    }
} finally {
    Close-LfoSqliteDatabase $l3
}

# L3 operations must not mutate the physically separate L2 database.
$l2HashAfter = (Get-FileHash -LiteralPath $l2Path -Algorithm SHA256).Hash
if ($l2HashAfter -cne $l2HashBefore) {
    throw 'L3 R1 mutated the isolated L2 database.'
}

# Reconstructibility check: deleting only L3 loses no L0/L2 authority.
foreach ($path in @($l3Path, ($l3Path + '-wal'), ($l3Path + '-shm'))) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
$rebuilt = Open-LfoL3Store $l3Path
try {
    $empty = Get-LfoL3StoreStats $rebuilt
    if ($empty.Items -ne 0 -or $empty.Facets -ne 0) {
        throw 'Fresh L3 rebuild was not empty.'
    }
} finally {
    Close-LfoSqliteDatabase $rebuilt
}

[pscustomobject]@{
    PASS = $true
    SchemaVersion = 2
    PositiveTopicItems = $positive.Count
    NegativeTopicItems = $negative.Count
    ScopeIsolation = ($otherScope.Count -eq 1)
    UnknownByAbsence = ($removed.Count -eq 0)
    RestartPersistence = $true
    L2HashUnchanged = ($l2HashAfter -ceq $l2HashBefore)
    Reconstructible = $true
    ModelCalls = 0
    ProductionMemoryTouched = $false
    TempFixture = $root
} | Format-List
