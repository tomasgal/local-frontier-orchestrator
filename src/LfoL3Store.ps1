# L3 selective tagged index storage substrate.
# Separate reconstructible SQLite database; never an authoritative fact store.
# This module intentionally reuses only the generic SQLite ABI/query helpers
# defined by LfoMemoryStore.ps1. It does not open, mutate or initialize L2.

function Assert-LfoL3SqlitePrerequisites {
    foreach ($name in @(
        'Open-LfoSqliteDatabase',
        'Close-LfoSqliteDatabase',
        'Invoke-LfoSqliteExec',
        'Invoke-LfoSqliteNonQuery',
        'Invoke-LfoSqliteQuery'
    )) {
        if ($null -eq (Get-Command $name -ErrorAction SilentlyContinue)) {
            throw "LfoL3Store requires generic SQLite helper '$name' from LfoMemoryStore.ps1."
        }
    }
}

function Initialize-LfoL3StoreSchema($Connection) {
    Invoke-LfoSqliteExec $Connection @'
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;

CREATE TABLE IF NOT EXISTS l3_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS l3_items (
    id                  INTEGER PRIMARY KEY,
    scope_id            TEXT NOT NULL,
    source_layer        TEXT NOT NULL CHECK (source_layer IN ('L0','L2')),
    source_ref          TEXT NOT NULL,
    source_turn         INTEGER NULL,
    content_fingerprint TEXT NULL,
    created_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(scope_id, source_layer, source_ref)
);

CREATE INDEX IF NOT EXISTS ix_l3_items_scope_layer
ON l3_items(scope_id, source_layer);

CREATE INDEX IF NOT EXISTS ix_l3_items_source_turn
ON l3_items(scope_id, source_turn);
'@

    $schemaRows = @(Invoke-LfoSqliteQuery $Connection "SELECT value FROM l3_meta WHERE key='schema_version';")
    $schemaVersion = if ($schemaRows.Count -eq 0) { 0 } else { [int]$schemaRows[0].value }
    if ($schemaVersion -notin @(0,2,3,4)) {
        throw "Unsupported L3 schema version $schemaVersion."
    }

    if ($schemaVersion -eq 2) {
        # v3 removes the physical dimension whitelist from SQLite. L3 is
        # reconstructible, but preserve the existing derived index during the
        # migration so an upgrade does not silently discard useful metadata.
        Invoke-LfoSqliteExec $Connection @'
PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;
DROP VIEW IF EXISTS l3_item_facets;

CREATE TABLE l3_facets_v3 (
    item_id     INTEGER NOT NULL REFERENCES l3_items(id) ON DELETE CASCADE,
    dimension   TEXT NOT NULL,
    value_key   TEXT NOT NULL,
    polarity    INTEGER NOT NULL CHECK (polarity IN (-1,1)),
    rule_id     TEXT NOT NULL,
    created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(item_id, dimension, value_key)
);
INSERT INTO l3_facets_v3
SELECT item_id, dimension, value_key, polarity, rule_id, created_at, updated_at
FROM l3_facets;
DROP TABLE l3_facets;
ALTER TABLE l3_facets_v3 RENAME TO l3_facets;

CREATE TABLE l3_terms_v3 (
    dimension  TEXT NOT NULL,
    value_key  TEXT NOT NULL,
    term_key   TEXT NOT NULL,
    priority   INTEGER NOT NULL DEFAULT 0,
    rule_id    TEXT NOT NULL,
    active     INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(dimension, value_key, term_key)
);
INSERT INTO l3_terms_v3
SELECT dimension, value_key, term_key, priority, rule_id, active, created_at, updated_at
FROM l3_terms;
DROP TABLE l3_terms;
ALTER TABLE l3_terms_v3 RENAME TO l3_terms;

UPDATE l3_meta SET value='3' WHERE key='schema_version';
COMMIT;
PRAGMA foreign_keys = ON;
'@
        $schemaVersion = 3
    }

    if ($schemaVersion -eq 3) {
        Invoke-LfoSqliteExec $Connection @'
CREATE TABLE IF NOT EXISTS l3_l0_locators (
    item_id      INTEGER PRIMARY KEY REFERENCES l3_items(id) ON DELETE CASCADE,
    source_file  TEXT NOT NULL,
    byte_offset  INTEGER NOT NULL CHECK (byte_offset >= 0),
    byte_length  INTEGER NOT NULL CHECK (byte_length > 0),
    updated_at   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_l3_l0_locators_file_offset
ON l3_l0_locators(source_file, byte_offset);
UPDATE l3_meta SET value='4' WHERE key='schema_version';
'@
        $schemaVersion = 4
    }

    Invoke-LfoSqliteExec $Connection @'
CREATE TABLE IF NOT EXISTS l3_facets (
    item_id     INTEGER NOT NULL REFERENCES l3_items(id) ON DELETE CASCADE,
    dimension   TEXT NOT NULL,
    value_key   TEXT NOT NULL,
    polarity    INTEGER NOT NULL CHECK (polarity IN (-1,1)),
    rule_id     TEXT NOT NULL,
    created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(item_id, dimension, value_key)
);

CREATE INDEX IF NOT EXISTS ix_l3_facets_lookup
ON l3_facets(dimension, value_key, polarity, item_id);

CREATE INDEX IF NOT EXISTS ix_l3_facets_item
ON l3_facets(item_id);

CREATE TABLE IF NOT EXISTS l3_terms (
    dimension  TEXT NOT NULL,
    value_key  TEXT NOT NULL,
    term_key   TEXT NOT NULL,
    priority   INTEGER NOT NULL DEFAULT 0,
    rule_id    TEXT NOT NULL,
    active     INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY(dimension, value_key, term_key)
);

CREATE INDEX IF NOT EXISTS ix_l3_terms_lookup
ON l3_terms(term_key, active, dimension);

CREATE INDEX IF NOT EXISTS ix_l3_terms_value
ON l3_terms(dimension, value_key, active);

CREATE TABLE IF NOT EXISTS l3_l0_locators (
    item_id      INTEGER PRIMARY KEY REFERENCES l3_items(id) ON DELETE CASCADE,
    source_file  TEXT NOT NULL,
    byte_offset  INTEGER NOT NULL CHECK (byte_offset >= 0),
    byte_length  INTEGER NOT NULL CHECK (byte_length > 0),
    updated_at   TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_l3_l0_locators_file_offset
ON l3_l0_locators(source_file, byte_offset);

CREATE VIEW IF NOT EXISTS l3_item_facets AS
SELECT
    i.id,
    i.scope_id,
    i.source_layer,
    i.source_ref,
    i.source_turn,
    i.content_fingerprint,
    f.dimension,
    f.value_key,
    f.polarity,
    f.rule_id
FROM l3_items i
LEFT JOIN l3_facets f ON f.item_id = i.id;

INSERT INTO l3_meta(key, value)
VALUES ('schema_version', '4')
ON CONFLICT(key) DO UPDATE SET value = excluded.value;
'@
}

function Open-LfoL3Store([string]$Path) {
    Assert-LfoL3SqlitePrerequisites
    $connection = Open-LfoSqliteDatabase $Path
    try {
        Initialize-LfoL3StoreSchema $connection
        return $connection
    } catch {
        Close-LfoSqliteDatabase $connection
        throw
    }
}

function Open-LfoL3ReadOnly([string]$Path) {
    Assert-LfoL3SqlitePrerequisites
    Initialize-LfoSqliteInterop
    $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $null }

    $handle = [IntPtr]::Zero
    $rc = [LfoWinSqlite]::sqlite3_open_v2($fullPath, [ref]$handle, 1, [IntPtr]::Zero)
    if ($rc -ne [LfoWinSqlite]::SQLITE_OK) {
        $message = Get-LfoSqliteError $handle
        if ($handle -ne [IntPtr]::Zero) { [void][LfoWinSqlite]::sqlite3_close_v2($handle) }
        throw ("L3 SQLite read-only open failed (rc={0}): {1}" -f $rc, $message)
    }
    try {
        Assert-LfoSqliteRc $handle ([LfoWinSqlite]::sqlite3_busy_timeout($handle, 2500)) 'sqlite3_busy_timeout'
        return [pscustomobject]@{ Path = $fullPath; Handle = $handle }
    } catch {
        [void][LfoWinSqlite]::sqlite3_close_v2($handle)
        throw
    }
}

function Start-LfoL3Transaction($Connection) {
    Invoke-LfoSqliteExec $Connection 'BEGIN IMMEDIATE;'
}

function Complete-LfoL3Transaction($Connection) {
    Invoke-LfoSqliteExec $Connection 'COMMIT;'
}

function Undo-LfoL3Transaction($Connection) {
    Invoke-LfoSqliteExec $Connection 'ROLLBACK;'
}

function ConvertTo-LfoL3Key([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }

    $formD = $Value.Trim().ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $formD.ToCharArray()) {
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($category -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }

    $plain = $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
    $key = $plain -replace '[^\p{L}\p{N}._:+-]+', '-'
    $key = $key -replace '^-+|-+$', ''
    return $key
}

function Assert-LfoL3FacetDimension([string]$Dimension) {
    $key = ConvertTo-LfoL3Key $Dimension
    if ($key -notin @('topic','entity','kind','predicate','temporal','retrieval')) {
        throw "Unsupported L3 facet dimension '$Dimension'."
    }
    return $key
}

function Set-LfoL3Item(
    $Connection,
    [string]$ScopeId,
    [string]$SourceLayer,
    [string]$SourceRef,
    [Nullable[int64]]$SourceTurn = $null,
    [string]$ContentFingerprint = $null
) {
    $scope = $ScopeId.Trim()
    $layer = $SourceLayer.Trim().ToUpperInvariant()
    $ref = $SourceRef.Trim()

    if ([string]::IsNullOrWhiteSpace($scope)) { throw 'L3 scope_id must not be empty.' }
    if ($layer -notin @('L0','L2')) { throw "L3 source_layer must be L0 or L2, got '$SourceLayer'." }
    if ([string]::IsNullOrWhiteSpace($ref)) { throw 'L3 source_ref must not be empty.' }

    $turn = if ($null -eq $SourceTurn) { $null } else { [int64]$SourceTurn }
    $fingerprint = if ([string]::IsNullOrWhiteSpace($ContentFingerprint)) { $null } else { $ContentFingerprint.Trim() }

    Invoke-LfoSqliteNonQuery $Connection @'
INSERT INTO l3_items(scope_id, source_layer, source_ref, source_turn, content_fingerprint)
VALUES (?1, ?2, ?3, ?4, ?5)
ON CONFLICT(scope_id, source_layer, source_ref) DO UPDATE SET
    source_turn = COALESCE(excluded.source_turn, l3_items.source_turn),
    content_fingerprint = COALESCE(excluded.content_fingerprint, l3_items.content_fingerprint),
    updated_at = CURRENT_TIMESTAMP;
'@ @($scope, $layer, $ref, $turn, $fingerprint)

    $rows = @(Invoke-LfoSqliteQuery $Connection @'
SELECT id, scope_id, source_layer, source_ref, source_turn, content_fingerprint
FROM l3_items
WHERE scope_id = ?1 AND source_layer = ?2 AND source_ref = ?3
LIMIT 1;
'@ @($scope, $layer, $ref))

    if ($rows.Count -ne 1) { throw 'L3 item upsert did not resolve exactly one row.' }
    return $rows[0]
}

function Set-LfoL3L0Locator(
    $Connection,
    [int64]$ItemId,
    [string]$SourceFile,
    [int64]$ByteOffset,
    [int64]$ByteLength
) {
    $file = [IO.Path]::GetFileName($SourceFile)
    if ([string]::IsNullOrWhiteSpace($file)) { throw 'L3 L0 locator source_file must not be empty.' }
    if ($ByteOffset -lt 0) { throw 'L3 L0 locator byte_offset must be >= 0.' }
    if ($ByteLength -le 0) { throw 'L3 L0 locator byte_length must be > 0.' }

    Invoke-LfoSqliteNonQuery $Connection @'
INSERT INTO l3_l0_locators(item_id, source_file, byte_offset, byte_length)
VALUES (?1, ?2, ?3, ?4)
ON CONFLICT(item_id) DO UPDATE SET
    source_file = excluded.source_file,
    byte_offset = excluded.byte_offset,
    byte_length = excluded.byte_length,
    updated_at = CURRENT_TIMESTAMP;
'@ @($ItemId,$file,$ByteOffset,$ByteLength)

    return @(Invoke-LfoSqliteQuery $Connection @'
SELECT item_id, source_file, byte_offset, byte_length
FROM l3_l0_locators
WHERE item_id = ?1
LIMIT 1;
'@ @($ItemId))[0]
}

function Get-LfoL3L0Locators(
    $Connection,
    [int64[]]$ItemIds
) {
    $ids = @($ItemIds | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
    if ($null -eq $Connection -or $ids.Count -eq 0) { return @() }

    $table = @(Invoke-LfoSqliteQuery $Connection "SELECT name FROM sqlite_master WHERE type='table' AND name='l3_l0_locators';")
    if ($table.Count -ne 1) { return @() }

    $placeholders = (1..$ids.Count | ForEach-Object { "?$_" }) -join ','
    return @(Invoke-LfoSqliteQuery $Connection @"
SELECT item_id, source_file, byte_offset, byte_length
FROM l3_l0_locators
WHERE item_id IN ($placeholders)
ORDER BY item_id;
"@ ([object[]]$ids))
}

function Set-LfoL3ExclusiveFacet(
    $Connection,
    [int64]$ItemId,
    [string]$Dimension,
    [string]$Value,
    [int]$Polarity,
    [string]$RuleId
) {
    $dimensionKey = Assert-LfoL3FacetDimension $Dimension
    Invoke-LfoSqliteNonQuery $Connection @'
DELETE FROM l3_facets
WHERE item_id = ?1 AND dimension = ?2;
'@ @($ItemId, $dimensionKey)
    return Set-LfoL3Facet $Connection $ItemId $dimensionKey $Value $Polarity $RuleId
}

function Set-LfoL3Facet(
    $Connection,
    [int64]$ItemId,
    [string]$Dimension,
    [string]$Value,
    [int]$Polarity,
    [string]$RuleId
) {
    $dimensionKey = Assert-LfoL3FacetDimension $Dimension
    $valueKey = ConvertTo-LfoL3Key $Value
    $rule = $RuleId.Trim()

    if ([string]::IsNullOrWhiteSpace($valueKey)) { throw 'L3 facet value must not be empty.' }
    if ($Polarity -notin @(-1,1)) { throw 'L3 facet polarity must be -1 or 1; absence represents unknown.' }
    if ([string]::IsNullOrWhiteSpace($rule)) { throw 'L3 facet rule_id must not be empty.' }

    Invoke-LfoSqliteNonQuery $Connection @'
INSERT INTO l3_facets(item_id, dimension, value_key, polarity, rule_id)
VALUES (?1, ?2, ?3, ?4, ?5)
ON CONFLICT(item_id, dimension, value_key) DO UPDATE SET
    polarity = excluded.polarity,
    rule_id = excluded.rule_id,
    updated_at = CURRENT_TIMESTAMP;
'@ @($ItemId, $dimensionKey, $valueKey, $Polarity, $rule)

    $rows = @(Invoke-LfoSqliteQuery $Connection @'
SELECT item_id, dimension, value_key, polarity, rule_id
FROM l3_facets
WHERE item_id = ?1 AND dimension = ?2 AND value_key = ?3
LIMIT 1;
'@ @($ItemId, $dimensionKey, $valueKey))

    if ($rows.Count -ne 1) { throw 'L3 facet upsert did not resolve exactly one row.' }
    return $rows[0]
}

function Remove-LfoL3Facet(
    $Connection,
    [int64]$ItemId,
    [string]$Dimension,
    [string]$Value
) {
    $dimensionKey = Assert-LfoL3FacetDimension $Dimension
    $valueKey = ConvertTo-LfoL3Key $Value
    if ([string]::IsNullOrWhiteSpace($valueKey)) { return }

    Invoke-LfoSqliteNonQuery $Connection @'
DELETE FROM l3_facets
WHERE item_id = ?1 AND dimension = ?2 AND value_key = ?3;
'@ @($ItemId, $dimensionKey, $valueKey)
}

function Get-LfoL3Facets($Connection, [int64]$ItemId) {
    return @(Invoke-LfoSqliteQuery $Connection @'
SELECT item_id, dimension, value_key, polarity, rule_id
FROM l3_facets
WHERE item_id = ?1
ORDER BY dimension, value_key;
'@ @($ItemId))
}

function Get-LfoL3ItemsByFacet(
    $Connection,
    [string]$ScopeId,
    [string]$Dimension,
    [string]$Value,
    [int]$Polarity = 1
) {
    $scope = $ScopeId.Trim()
    $dimensionKey = Assert-LfoL3FacetDimension $Dimension
    $valueKey = ConvertTo-LfoL3Key $Value

    if ([string]::IsNullOrWhiteSpace($scope)) { throw 'L3 scope_id must not be empty.' }
    if ([string]::IsNullOrWhiteSpace($valueKey)) { return @() }
    if ($Polarity -notin @(-1,1)) { throw 'L3 facet polarity must be -1 or 1.' }

    return @(Invoke-LfoSqliteQuery $Connection @'
SELECT
    i.id,
    i.scope_id,
    i.source_layer,
    i.source_ref,
    i.source_turn,
    i.content_fingerprint,
    f.dimension,
    f.value_key,
    f.polarity,
    f.rule_id
FROM l3_facets f
JOIN l3_items i ON i.id = f.item_id
WHERE i.scope_id = ?1
  AND f.dimension = ?2
  AND f.value_key = ?3
  AND f.polarity = ?4
ORDER BY COALESCE(i.source_turn, -1) DESC, i.id DESC;
'@ @($scope, $dimensionKey, $valueKey, $Polarity))
}

function Get-LfoL3StoreStats($Connection) {
    $items = @(Invoke-LfoSqliteQuery $Connection 'SELECT COUNT(*) AS n FROM l3_items;')
    $facets = @(Invoke-LfoSqliteQuery $Connection 'SELECT COUNT(*) AS n FROM l3_facets;')
    return [pscustomobject]@{
        Items = [int64]$items[0].n
        Facets = [int64]$facets[0].n
    }
}


# L3-R2 deterministic bounded tagging ---------------------------------------

function Assert-LfoL3RuleDimension([string]$Dimension) {
    $key = ConvertTo-LfoL3Key $Dimension
    if ($key -notin @('topic','entity','kind','predicate')) {
        throw "Unsupported L3 rule dimension '$Dimension'."
    }
    return $key
}

function Set-LfoL3TermRule(
    $Connection,
    [string]$Dimension,
    [string]$Value,
    [string]$Term,
    [int]$Priority = 0,
    [string]$RuleId = 'manual',
    [bool]$Active = $true
) {
    $dimensionKey = Assert-LfoL3RuleDimension $Dimension
    $valueKey = ConvertTo-LfoL3Key $Value
    $termKey = ConvertTo-LfoL3Key $Term
    $rule = $RuleId.Trim()

    if ([string]::IsNullOrWhiteSpace($valueKey)) { throw 'L3 rule value must not be empty.' }
    if ([string]::IsNullOrWhiteSpace($termKey)) { throw 'L3 rule term must not be empty.' }
    if ([string]::IsNullOrWhiteSpace($rule)) { throw 'L3 rule_id must not be empty.' }
    if ($Priority -lt -1000 -or $Priority -gt 1000) { throw 'L3 rule priority must be between -1000 and 1000.' }

    Invoke-LfoSqliteNonQuery $Connection @'
INSERT INTO l3_terms(dimension, value_key, term_key, priority, rule_id, active)
VALUES (?1, ?2, ?3, ?4, ?5, ?6)
ON CONFLICT(dimension, value_key, term_key) DO UPDATE SET
    priority = excluded.priority,
    rule_id = excluded.rule_id,
    active = excluded.active,
    updated_at = CURRENT_TIMESTAMP;
'@ @($dimensionKey, $valueKey, $termKey, $Priority, $rule, $(if ($Active) { 1 } else { 0 }))
}

function Get-LfoL3TextKeys(
    [string]$Text,
    [int]$MaxNGram = 4,
    [int]$MaxKeys = 96
) {
    if ([string]::IsNullOrWhiteSpace($Text) -or $MaxNGram -le 0 -or $MaxKeys -le 0) {
        return @()
    }

    # Tokens must start and end in a letter/number. Keep punctuation only
    # inside a token (for example foo.bar or a:b), never sentence-final
    # punctuation such as "passed." or "failed?".
    $tokens = @(
        [regex]::Matches($Text, '[\p{L}\p{N}](?:[\p{L}\p{N}._:+-]*[\p{L}\p{N}])?') |
        ForEach-Object { $_.Value } |
        Select-Object -First 48
    )
    if ($tokens.Count -eq 0) { return @() }

    $seen = @{}
    $keys = @()
    $largest = [Math]::Min([Math]::Min(4, $MaxNGram), $tokens.Count)

    # Longer phrases are emitted first so the most specific rules win ties.
    for ($size = $largest; $size -ge 1; $size--) {
        for ($i = 0; $i -le ($tokens.Count - $size); $i++) {
            $span = if ($size -eq 1) {
                [string]$tokens[$i]
            } else {
                (@($tokens[$i..($i + $size - 1)]) -join ' ')
            }
            $key = ConvertTo-LfoL3Key $span
            if ($key.Length -lt 2 -or $key.Length -gt 128) { continue }
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $keys += $key
            if ($keys.Count -ge $MaxKeys) { return @($keys) }
        }
    }
    return @($keys)
}

function Get-LfoL3Classification(
    $Connection,
    [string]$Text,
    [int]$MaxTopics = 2,
    [int]$MaxEntities = 3,
    [int]$MaxPredicates = 4
) {
    $maxTopicsBounded = [Math]::Min(2, [Math]::Max(0, $MaxTopics))
    $maxEntitiesBounded = [Math]::Min(3, [Math]::Max(0, $MaxEntities))
    $maxPredicatesBounded = [Math]::Min(4, [Math]::Max(0, $MaxPredicates))
    $keys = @(Get-LfoL3TextKeys $Text 4 96)

    if ($null -eq $Connection -or $keys.Count -eq 0) {
        return [pscustomobject]@{
            Status = 'no_match'
            QueryKeys = $keys.Count
            Topics = @()
            Entities = @()
            Predicates = @()
            Kind = $null
            Facets = @()
        }
    }

    $placeholders = (1..$keys.Count | ForEach-Object { "?$_" }) -join ','
    $sql = @"
SELECT dimension, value_key, term_key, priority, rule_id
FROM l3_terms
WHERE active = 1
  AND term_key IN ($placeholders);
"@
    $matches = @(Invoke-LfoSqliteQuery $Connection $sql ([object[]]$keys))
    if ($matches.Count -eq 0) {
        return [pscustomobject]@{
            Status = 'no_match'
            QueryKeys = $keys.Count
            Topics = @()
            Entities = @()
            Predicates = @()
            Kind = $null
            Facets = @()
        }
    }

    # Keep only the strongest matched rule per dimension/value pair.
    $best = @()
    foreach ($group in @($matches | Group-Object dimension, value_key)) {
        $winner = @(
            $group.Group |
            Sort-Object @{Expression='priority';Descending=$true},
                        @{Expression={([string]$_.term_key).Length};Descending=$true},
                        @{Expression='term_key';Descending=$false} |
            Select-Object -First 1
        )[0]
        $best += [pscustomobject]@{
            Dimension = [string]$winner.dimension
            ValueKey = [string]$winner.value_key
            MatchKey = [string]$winner.term_key
            Priority = [int]$winner.priority
            RuleId = [string]$winner.rule_id
        }
    }

    $topics = @(
        $best | Where-Object { $_.Dimension -eq 'topic' } |
        Sort-Object @{Expression='Priority';Descending=$true},
                    @{Expression={([string]$_.MatchKey).Length};Descending=$true},
                    @{Expression='ValueKey';Descending=$false} |
        Select-Object -First $maxTopicsBounded
    )
    $entities = @(
        $best | Where-Object { $_.Dimension -eq 'entity' } |
        Sort-Object @{Expression='Priority';Descending=$true},
                    @{Expression={([string]$_.MatchKey).Length};Descending=$true},
                    @{Expression='ValueKey';Descending=$false} |
        Select-Object -First $maxEntitiesBounded
    )
    $predicateRows = @(
        $best | Where-Object { $_.Dimension -eq 'predicate' } |
        Sort-Object @{Expression='Priority';Descending=$true},
                    @{Expression={([string]$_.MatchKey).Length};Descending=$true},
                    @{Expression='ValueKey';Descending=$false} |
        Select-Object -First $maxPredicatesBounded
    )
    $kindRows = @(
        $best | Where-Object { $_.Dimension -eq 'kind' } |
        Sort-Object @{Expression='Priority';Descending=$true},
                    @{Expression={([string]$_.MatchKey).Length};Descending=$true},
                    @{Expression='ValueKey';Descending=$false} |
        Select-Object -First 1
    )
    $kind = if ($kindRows.Count -eq 1) { $kindRows[0] } else { $null }
    $facets = @($topics) + @($entities) + @($predicateRows)
    if ($null -ne $kind) { $facets += $kind }

    return [pscustomobject]@{
        Status = $(if ($facets.Count -gt 0) { 'ok' } else { 'no_match' })
        QueryKeys = $keys.Count
        Topics = @($topics)
        Entities = @($entities)
        Predicates = @($predicateRows)
        Kind = $kind
        Facets = @($facets)
    }
}

function Add-LfoL3ClassificationToItem(
    $Connection,
    [int64]$ItemId,
    $Classification
) {
    if ($null -eq $Classification) { return 0 }
    $written = 0
    foreach ($facet in @($Classification.Facets)) {
        [void](Set-LfoL3Facet $Connection $ItemId ([string]$facet.Dimension) ([string]$facet.ValueKey) 1 ([string]$facet.RuleId))
        $written++
    }
    return $written
}
