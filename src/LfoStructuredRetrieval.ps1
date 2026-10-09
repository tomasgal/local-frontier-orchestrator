# v9.4-dev4 stage 2: SELECT-only L2 retrieval by exact user-mentioned entity.
# This file is dot-sourced after LfoMemoryStore.ps1. No schema changes.

function Open-LfoMemoryReadOnly([string]$Path) {
    Initialize-LfoSqliteInterop
    $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $null }

    $handle = [IntPtr]::Zero
    # SQLite documented SQLITE_OPEN_READONLY flag = 0x00000001.
    $rc = [LfoWinSqlite]::sqlite3_open_v2($fullPath, [ref]$handle, 1, [IntPtr]::Zero)
    if ($rc -ne [LfoWinSqlite]::SQLITE_OK) {
        $message = Get-LfoSqliteError $handle
        if ($handle -ne [IntPtr]::Zero) { [void][LfoWinSqlite]::sqlite3_close_v2($handle) }
        throw ("SQLite read-only open failed (rc={0}): {1}" -f $rc, $message)
    }
    try {
        Assert-LfoSqliteRc $handle ([LfoWinSqlite]::sqlite3_busy_timeout($handle, 2500)) 'sqlite3_busy_timeout'
        return [pscustomobject]@{ Path = $fullPath; Handle = $handle }
    } catch {
        [void][LfoWinSqlite]::sqlite3_close_v2($handle)
        throw
    }
}

function Get-LfoMemoryRelevantCurrentFacts(
    $Connection,
    [string[]]$CandidateKeys,
    [string]$ScopeId,
    [int]$MaxItems = 6,
    [int]$MaxChars = 800
) {
    $empty = [pscustomobject]@{ Text=''; Count=0; CandidateKeys=0; EligibleEntities=0; Status='empty' }
    if ($null -eq $Connection -or [string]::IsNullOrWhiteSpace($ScopeId) -or
        $MaxItems -le 0 -or $MaxChars -le 0) { return $empty }

    $keys = @($CandidateKeys | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_.Length -ge 3 -and $_.Length -le 96
    } | Select-Object -Unique -First 48)
    if ($keys.Count -eq 0) { return $empty }

    $namePlaceholders = (1..$keys.Count | ForEach-Object { "?$_" }) -join ','
    $nameSql = @"
SELECT DISTINCT n.normalized_name AS candidate_key, n.entity_id
FROM entity_names n
WHERE n.normalized_name IN ($namePlaceholders)
ORDER BY n.normalized_name, n.entity_id;
"@
    $nameMatches = @(Invoke-LfoSqliteQuery $Connection $nameSql ([object[]]$keys))

    $ids = @()
    foreach ($key in $keys) {
        $matches = @($nameMatches | Where-Object { $_.candidate_key -ceq $key })
        # Ambiguous aliases must not silently select one entity.
        if ($matches.Count -ne 1) { continue }
        $id = [int64]$matches[0].entity_id
        if ($ids -notcontains $id) { $ids += $id }
        if ($ids.Count -ge 6) { break }
    }
    if ($ids.Count -eq 0) {
        return [pscustomobject]@{
            Text=''; Count=0; CandidateKeys=$keys.Count
            EligibleEntities=0; Status='no_unique_entity'
        }
    }

    $idPlaceholders = (1..$ids.Count | ForEach-Object { '?' + ($_ + 1) }) -join ','
    $limitParam = $ids.Count + 2
    $sql = @"
SELECT f.id, f.source_turn, f.scope_id, f.predicate, f.literal_type,
       f.value_text, f.value_integer, f.value_real, f.object_entity_id,
       (SELECT n.name FROM entity_names n WHERE n.entity_id=f.subject_entity_id ORDER BY n.id LIMIT 1) AS subject_name,
       (SELECT n.name FROM entity_names n WHERE n.entity_id=f.object_entity_id ORDER BY n.id LIMIT 1) AS object_name
FROM current_facts f
WHERE f.scope_id = ?1
  AND f.subject_entity_id IN ($idPlaceholders)
ORDER BY f.source_turn DESC, f.id DESC
LIMIT ?$limitParam;
"@
    $params = [object[]](@($ScopeId) + @($ids) + @([Math]::Min(128, [Math]::Max(16, 4 * $MaxItems))))
    $facts = @(Invoke-LfoSqliteQuery $Connection $sql $params)
    $lines = @()
    $used = 0
    foreach ($fact in $facts) {
        if ($null -ne $fact.object_entity_id) {
            $value = '-> ' + [string]$fact.object_name
        } else {
            $value = switch ([string]$fact.literal_type) {
                'integer' { [string]$fact.value_integer }
                'boolean' { if ([int64]$fact.value_integer -eq 0) { 'false' } else { 'true' } }
                'real' { ([double]$fact.value_real).ToString('G', [Globalization.CultureInfo]::InvariantCulture) }
                default { [string]$fact.value_text }
            }
        }
        $line = ('{0}.{1} = {2} [scope={3}; source_turn={4}]' -f
            [string]$fact.subject_name, [string]$fact.predicate,
            $value, [string]$fact.scope_id, [string]$fact.source_turn)
        $cost = $line.Length + $(if ($lines.Count -gt 0) { 1 } else { 0 })
        if (($used + $cost) -gt $MaxChars) { continue }
        $lines += $line
        $used += $cost
        if ($lines.Count -ge $MaxItems) { break }
    }
    return [pscustomobject]@{
        Text = ($lines -join "`n")
        Count = $lines.Count
        CandidateKeys = $keys.Count
        EligibleEntities = $ids.Count
        Status = 'ok'
    }
}
