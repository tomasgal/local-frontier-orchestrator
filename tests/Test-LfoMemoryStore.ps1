# Isolated v9.4-dev1 smoke test for the L2 SQLite substrate.
# Uses only a fresh TEMP database and does not touch LFO production memory.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'src\LfoMemoryStore.ps1')

$root = Join-Path $env:TEMP ('LFO-v9.4-l2-sqlite-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
$dbPath = Join-Path $root 'memory.db'

$store = Open-LfoMemoryStore $dbPath
try {
    $version = [LfoWinSqlite]::Utf8([LfoWinSqlite]::sqlite3_libversion())

    Start-LfoMemoryTransaction $store
    try {
        Invoke-LfoSqliteNonQuery $store 'INSERT INTO entities(canonical_name, entity_type, created_turn) VALUES (?1, ?2, ?3);' @('Core', 'computer', 1)
        Invoke-LfoSqliteNonQuery $store 'INSERT INTO entities(canonical_name, entity_type, created_turn) VALUES (?1, ?2, ?3);' @('GTX1050', 'gpu', 1)

        $core = @(Invoke-LfoSqliteQuery $store 'SELECT id FROM entities WHERE canonical_name = ?1;' @('Core'))[0]
        $gpu  = @(Invoke-LfoSqliteQuery $store 'SELECT id FROM entities WHERE canonical_name = ?1;' @('GTX1050'))[0]

        Invoke-LfoSqliteNonQuery $store @'
INSERT INTO facts(subject_entity_id, predicate, object_entity_id, valid_from_turn, source_turn)
VALUES (?1, ?2, ?3, ?4, ?5);
'@ @([int64]$core.id, 'has_gpu', [int64]$gpu.id, 1, 1)

        Invoke-LfoSqliteNonQuery $store @'
INSERT INTO facts(subject_entity_id, predicate, literal_type, value_text, valid_from_turn, source_turn)
VALUES (?1, ?2, ?3, ?4, ?5, ?6);
'@ @([int64]$gpu.id, 'vendor', 'text', 'NVIDIA', 1, 1)

        Invoke-LfoSqliteNonQuery $store @'
INSERT INTO facts(subject_entity_id, predicate, literal_type, value_integer, valid_from_turn, source_turn)
VALUES (?1, ?2, ?3, ?4, ?5, ?6);
'@ @([int64]$core.id, 'ram_gb', 'integer', 32, 1, 1)

        Complete-LfoMemoryTransaction $store
    } catch {
        Undo-LfoMemoryTransaction $store
        throw
    }

    $result = @(Invoke-LfoSqliteQuery $store @'
SELECT c.canonical_name AS computer
FROM entities c
JOIN current_facts cg
  ON cg.subject_entity_id = c.id
 AND cg.predicate = 'has_gpu'
JOIN entities g
  ON g.id = cg.object_entity_id
JOIN current_facts gv
  ON gv.subject_entity_id = g.id
 AND gv.predicate = 'vendor'
WHERE c.entity_type = 'computer'
  AND gv.value_text = ?1;
'@ @('NVIDIA'))

    $schema = @(Invoke-LfoSqliteQuery $store "SELECT value FROM meta WHERE key = 'schema_version';")[0]

    if ($schema.value -ne '1') { throw "Unexpected schema version: $($schema.value)" }
    if ($result.Count -ne 1 -or $result[0].computer -ne 'Core') {
        throw ('Unexpected relational query result: ' + ($result | ConvertTo-Json -Compress))
    }

    # Stable L2 operation contract: deterministic set, duplicate suppression,
    # provenance, and historical supersession.
    Start-LfoMemoryTransaction $store
    try {
        $first = Set-LfoMemoryAttribute $store 'ORION' 'os' 'Debian 12' 10 'server'
        $duplicate = Set-LfoMemoryAttribute $store 'ORION' 'os' 'Debian 12' 11 'server'
        $replacement = Set-LfoMemoryAttribute $store 'ORION' 'os' 'Ubuntu 24.04' 12 'server'
        Complete-LfoMemoryTransaction $store
    } catch {
        Undo-LfoMemoryTransaction $store
        throw
    }

    $current = @(Get-LfoMemoryCurrentAttribute $store 'ORION' 'os')
    $history = @(Invoke-LfoSqliteQuery $store @'
SELECT
    f.value_text,
    f.valid_from_turn,
    f.valid_to_turn,
    f.source_turn
FROM facts f
JOIN entities e ON e.id = f.subject_entity_id
WHERE e.canonical_name = 'ORION'
  AND f.predicate = 'os'
ORDER BY f.id;
'@)

    if ($first.Status -ne 'written') { throw "First SET was not written: $($first.Status)" }
    if ($duplicate.Status -ne 'duplicate') { throw "Duplicate SET was not suppressed: $($duplicate.Status)" }
    if ($replacement.Status -ne 'written') { throw "Replacement SET was not written: $($replacement.Status)" }
    if ($current.Count -ne 1 -or $current[0].Value -ne 'Ubuntu 24.04' -or $current[0].SourceTurn -ne 12) {
        throw ('Unexpected current attribute: ' + ($current | ConvertTo-Json -Compress))
    }
    if ($history.Count -ne 2) {
        throw "Expected exactly 2 historical rows after duplicate suppression; got $($history.Count)"
    }
    if ($history[0].value_text -ne 'Debian 12' -or $history[0].valid_to_turn -ne 12 -or
        $history[1].value_text -ne 'Ubuntu 24.04' -or $null -ne $history[1].valid_to_turn) {
        throw ('Unexpected supersession history: ' + ($history | ConvertTo-Json -Compress))
    }

    # Typed values and relation API.
    Start-LfoMemoryTransaction $store
    try {
        $ram = Set-LfoMemoryAttribute $store 'Core' 'ram_gb' 32 20 'computer'
        $enabled = Set-LfoMemoryAttribute $store 'Core' 'enabled' $true 20 'computer'
        $temp = Set-LfoMemoryAttribute $store 'Core' 'temp_limit_c' ([double]83.5) 20 'computer'
        $relation = Add-LfoMemoryRelation $store 'Core' 'has_gpu' 'GTX1050' 20 'computer' 'gpu'
        $relationDuplicate = Add-LfoMemoryRelation $store 'Core' 'has_gpu' 'GTX1050' 21 'computer' 'gpu'
        Complete-LfoMemoryTransaction $store
    } catch {
        Undo-LfoMemoryTransaction $store
        throw
    }

    $ramNow = @(Get-LfoMemoryCurrentAttribute $store 'Core' 'ram_gb')
    $enabledNow = @(Get-LfoMemoryCurrentAttribute $store 'Core' 'enabled')
    $tempNow = @(Get-LfoMemoryCurrentAttribute $store 'Core' 'temp_limit_c')

    if ($ram.Status -notin @('written','duplicate')) { throw "Unexpected RAM status: $($ram.Status)" }
    if ($enabled.Status -ne 'written') { throw "Boolean SET failed: $($enabled.Status)" }
    if ($temp.Status -ne 'written') { throw "Real SET failed: $($temp.Status)" }
    if ($relation.Status -notin @('written','duplicate')) { throw "Relation ADD failed: $($relation.Status)" }
    if ($relationDuplicate.Status -ne 'duplicate') { throw "Duplicate relation was not suppressed: $($relationDuplicate.Status)" }
    if ($ramNow.Count -ne 1 -or $ramNow[0].ValueType -ne 'integer' -or $ramNow[0].Value -ne 32) {
        throw ('Integer round-trip failed: ' + ($ramNow | ConvertTo-Json -Compress))
    }
    if ($enabledNow.Count -ne 1 -or $enabledNow[0].ValueType -ne 'boolean' -or $enabledNow[0].Value -ne $true) {
        throw ('Boolean round-trip failed: ' + ($enabledNow | ConvertTo-Json -Compress))
    }
    if ($tempNow.Count -ne 1 -or $tempNow[0].ValueType -ne 'real' -or [Math]::Abs([double]$tempNow[0].Value - 83.5) -gt 0.0001) {
        throw ('Real round-trip failed: ' + ($tempNow | ConvertTo-Json -Compress))
    }

    # Close/reopen validates persistence independently of the live connection.
    Close-LfoSqliteDatabase $store
    $store = Open-LfoMemoryStore $dbPath

    $afterRestart = @(Get-LfoMemoryCurrentAttribute $store 'ORION' 'os')
    $relationAfterRestart = @(Invoke-LfoSqliteQuery $store @'
SELECT s.canonical_name AS subject, f.predicate, o.canonical_name AS object, f.source_turn
FROM current_facts f
JOIN entities s ON s.id = f.subject_entity_id
JOIN entities o ON o.id = f.object_entity_id
WHERE s.canonical_name = ?1
  AND f.predicate = ?2
  AND o.canonical_name = ?3;
'@ @('Core', 'has_gpu', 'GTX1050'))

    if ($afterRestart.Count -ne 1 -or $afterRestart[0].Value -ne 'Ubuntu 24.04') {
        throw ('Restart persistence failed for attribute: ' + ($afterRestart | ConvertTo-Json -Compress))
    }
    if ($relationAfterRestart.Count -ne 1) {
        throw ('Restart persistence failed for relation: ' + ($relationAfterRestart | ConvertTo-Json -Compress))
    }

    [pscustomobject]@{
        PASS = $true
        SQLite = $version
        Schema = $schema.value
        RelationalQuery = $result[0].computer
        AttributeSet = $first.Status
        DuplicateSet = $duplicate.Status
        ReplacementSet = $replacement.Status
        CurrentValue = $current[0].Value
        CurrentSourceTurn = $current[0].SourceTurn
        HistoricalRows = $history.Count
        IntegerValue = $ramNow[0].Value
        BooleanValue = $enabledNow[0].Value
        RealValue = $tempNow[0].Value
        RelationDuplicate = $relationDuplicate.Status
        RestartAttribute = $afterRestart[0].Value
        RestartRelation = $relationAfterRestart[0].object
        Database = $dbPath
        ProductionMemoryTouched = $false
    } | Format-List
} finally {
    Close-LfoSqliteDatabase $store
}
