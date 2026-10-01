# Isolated v9.4-dev1 smoke test for the L2 SQLite substrate.
# Uses only a fresh TEMP database and does not touch LFO production memory.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$syntaxFiles = @(
    (Join-Path $repoRoot 'src\LfoStructuredMemory.ps1'),
    (Join-Path $repoRoot 'src\LfoMemoryStore.ps1'),
    (Join-Path $repoRoot 'src\QwenMemory.ps1'),
    (Join-Path $repoRoot 'src\QwenChat.ps1')
)
foreach ($syntaxFile in $syntaxFiles) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $syntaxFile,
        [ref]$tokens,
        [ref]$errors
    )
    if (@($errors).Count -gt 0) {
        throw ("PowerShell syntax error in {0}: {1}" -f $syntaxFile, (($errors | ForEach-Object Message) -join '; '))
    }
}

. (Join-Path $repoRoot 'src\LfoStructuredMemory.ps1')
. (Join-Path $repoRoot 'src\LfoMemoryStore.ps1')

$root = Join-Path $env:TEMP ('LFO-v9.4-l2-sqlite-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force -Path $root | Out-Null
$dbPath = Join-Path $root 'memory.db'

$store = Open-LfoMemoryStore $dbPath
try {
    $version = [LfoWinSqlite]::Utf8([LfoWinSqlite]::sqlite3_libversion())

    Start-LfoMemoryTransaction $store
    try {
        $coreId = Resolve-LfoMemoryEntityId $store 'Core' 'computer' 1
        $gpuId  = Resolve-LfoMemoryEntityId $store 'GTX1050' 'gpu' 1

        Invoke-LfoSqliteNonQuery $store @'
INSERT INTO facts(subject_entity_id, predicate, object_entity_id, valid_from_turn, source_turn)
VALUES (?1, ?2, ?3, ?4, ?5);
'@ @($coreId, 'has_gpu', $gpuId, 1, 1)

        Invoke-LfoSqliteNonQuery $store @'
INSERT INTO facts(subject_entity_id, predicate, literal_type, value_text, valid_from_turn, source_turn)
VALUES (?1, ?2, ?3, ?4, ?5, ?6);
'@ @($gpuId, 'vendor', 'text', 'NVIDIA', 1, 1)

        Invoke-LfoSqliteNonQuery $store @'
INSERT INTO facts(subject_entity_id, predicate, literal_type, value_integer, valid_from_turn, source_turn)
VALUES (?1, ?2, ?3, ?4, ?5, ?6);
'@ @($coreId, 'ram_gb', 'integer', 32, 1, 1)

        Complete-LfoMemoryTransaction $store
    } catch {
        Undo-LfoMemoryTransaction $store
        throw
    }

    $result = @(Invoke-LfoSqliteQuery $store @'
SELECT
    (SELECT n.name FROM entity_names n WHERE n.entity_id = c.id ORDER BY n.id LIMIT 1) AS computer
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

    if ($schema.value -ne '3') { throw "Unexpected schema version: $($schema.value)" }
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
    $orionId = Resolve-LfoMemoryEntityId $store 'ORION'
    $history = @(Invoke-LfoSqliteQuery $store @'
SELECT
    f.value_text,
    f.valid_from_turn,
    f.valid_to_turn,
    f.source_turn
FROM facts f
WHERE f.subject_entity_id = ?1
  AND f.predicate = 'os'
ORDER BY f.id;
'@ @($orionId))

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
    $coreAfterRestart = Resolve-LfoMemoryEntityId $store 'Core'
    $gpuAfterRestart = Resolve-LfoMemoryEntityId $store 'GTX1050'
    $relationAfterRestart = @(Invoke-LfoSqliteQuery $store @'
SELECT f.predicate, f.source_turn
FROM current_facts f
WHERE f.subject_entity_id = ?1
  AND f.predicate = ?2
  AND f.object_entity_id = ?3;
'@ @($coreAfterRestart, 'has_gpu', $gpuAfterRestart))

    if ($afterRestart.Count -ne 1 -or $afterRestart[0].Value -ne 'Ubuntu 24.04') {
        throw ('Restart persistence failed for attribute: ' + ($afterRestart | ConvertTo-Json -Compress))
    }
    if ($relationAfterRestart.Count -ne 1) {
        throw ('Restart persistence failed for relation: ' + ($relationAfterRestart | ConvertTo-Json -Compress))
    }

    # Surface names are mentions, not identity. Deterministic normalization may
    # resolve obvious formatting variants to the same opaque entity_id.
    $gpuAlias1 = Resolve-LfoMemoryEntityId $store 'GTX 1050' 'gpu' 22
    $gpuAlias2 = Resolve-LfoMemoryEntityId $store 'gtx-1050' 'gpu' 23
    if ($gpuAlias1 -ne $gpuAfterRestart -or $gpuAlias2 -ne $gpuAfterRestart) {
        throw 'Entity mention normalization created duplicate identities.'
    }
    $gpuNames = @(Invoke-LfoSqliteQuery $store @'
SELECT name, normalized_name
FROM entity_names
WHERE entity_id = ?1
ORDER BY id;
'@ @($gpuAfterRestart))
    if ($gpuNames.Count -lt 3) {
        throw "Expected surface-form history for GTX1050; got $($gpuNames.Count) names."
    }

    # Runtime-equivalent structured apply: one dense turn, one transaction.
    $applyParsed = ConvertFrom-LfoStructuredMemoryOps @(
        [pscustomobject]@{
            op = 'SET_INTEGER'
            subject = 'Core'
            subject_type = 'computer'
            predicate = 'ram_gb'
            target = '64'
            target_entity_type = ''
        },
        [pscustomobject]@{
            op = 'ADD_RELATION'
            subject = 'Core'
            subject_type = 'computer'
            predicate = 'has_gpu'
            target = 'GTX1050'
            target_entity_type = 'gpu'
        },
        [pscustomobject]@{
            op = 'SET_TEXT'
            subject = 'GTX1050'
            subject_type = 'gpu'
            predicate = 'vendor'
            target = 'NVIDIA'
            target_entity_type = ''
        }
    ) 6
    $applyResult = Apply-LfoStructuredMemoryOps $store $applyParsed 40 'conversation:3'
    if ($applyResult.Status -ne 'applied' -or $applyResult.AppliedCount -ne 3) {
        throw ('Structured apply failed: ' + ($applyResult | ConvertTo-Json -Depth 8 -Compress))
    }
    $appliedFacts = @(Invoke-LfoSqliteQuery $store @'
SELECT id
FROM facts
WHERE scope_id = 'conversation:3'
  AND valid_to_turn IS NULL;
'@)
    if ($appliedFacts.Count -ne 3) {
        throw "Expected 3 current facts in structured apply scope; got $($appliedFacts.Count)."
    }

    # Fail closed: one rejected op prevents the valid sibling from being written.
    $rejectParsed = ConvertFrom-LfoStructuredMemoryOps @(
        [pscustomobject]@{
            op = 'SET_TEXT'
            subject = 'Core'
            subject_type = 'computer'
            predicate = 'os'
            target = 'Windows 11'
            target_entity_type = ''
        },
        [pscustomobject]@{
            op = 'SET_INTEGER'
            subject = 'Core'
            subject_type = 'computer'
            predicate = 'ram_gb'
            target = 'not-a-number'
            target_entity_type = ''
        }
    ) 6
    $rejectResult = Apply-LfoStructuredMemoryOps $store $rejectParsed 41 'conversation:4'
    if ($rejectResult.Status -ne 'rejected' -or $rejectResult.AppliedCount -ne 0 -or $rejectResult.RejectedCount -ne 1) {
        throw ('Structured reject policy failed: ' + ($rejectResult | ConvertTo-Json -Depth 8 -Compress))
    }
    $rejectedScopeFacts = @(Invoke-LfoSqliteQuery $store @'
SELECT id
FROM facts
WHERE scope_id = 'conversation:4';
'@)
    if ($rejectedScopeFacts.Count -ne 0) {
        throw "Fail-closed structured set wrote $($rejectedScopeFacts.Count) facts."
    }

    # Scope isolation: the same logical key can have independent current state.
    Start-LfoMemoryTransaction $store
    try {
        $scopeA = Set-LfoMemoryAttribute $store 'ORION' 'os' 'Ubuntu 24.04' 30 'server' 'conversation:1'
        $scopeB = Set-LfoMemoryAttribute $store 'ORION' 'os' 'Debian 13' 1 'server' 'conversation:2'
        Complete-LfoMemoryTransaction $store
    } catch {
        Undo-LfoMemoryTransaction $store
        throw
    }

    $scopeAValue = @(Get-LfoMemoryCurrentAttribute $store 'ORION' 'os' 'conversation:1')
    $scopeBValue = @(Get-LfoMemoryCurrentAttribute $store 'ORION' 'os' 'conversation:2')
    if ($scopeAValue.Count -ne 1 -or $scopeAValue[0].Value -ne 'Ubuntu 24.04' -or
        $scopeBValue.Count -ne 1 -or $scopeBValue[0].Value -ne 'Debian 13') {
        throw 'L2 scope isolation failed.'
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
        RestartRelation = 'GTX1050'
        ScopeA = $scopeAValue[0].Value
        ScopeB = $scopeBValue[0].Value
        AliasSameEntity = ($gpuAlias1 -eq $gpuAfterRestart -and $gpuAlias2 -eq $gpuAfterRestart)
        EntityNameRows = $gpuNames.Count
        StructuredApply = $applyResult.Status
        StructuredAppliedCount = $applyResult.AppliedCount
        RejectedSet = $rejectResult.Status
        RejectedScopeFacts = $rejectedScopeFacts.Count
        SyntaxChecked = $true
        Database = $dbPath
        ProductionMemoryTouched = $false
    } | Format-List
} finally {
    Close-LfoSqliteDatabase $store
}
