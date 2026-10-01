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

    [pscustomobject]@{
        PASS = $true
        SQLite = $version
        Schema = $schema.value
        QueryResult = $result[0].computer
        Database = $dbPath
        ProductionMemoryTouched = $false
    } | Format-List
} finally {
    Close-LfoSqliteDatabase $store
}
