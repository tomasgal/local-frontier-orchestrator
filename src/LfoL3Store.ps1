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

CREATE TABLE IF NOT EXISTS l3_facets (
    item_id     INTEGER NOT NULL REFERENCES l3_items(id) ON DELETE CASCADE,
    dimension   TEXT NOT NULL CHECK (dimension IN ('topic','entity','kind','temporal','retrieval')),
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
VALUES ('schema_version', '1')
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
    if ($key -notin @('topic','entity','kind','temporal','retrieval')) {
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
