# v9.4 L2 structured-memory storage substrate.
# Thin PowerShell -> Windows winsqlite3.dll ABI pipe.
# No LFO memory semantics belong in the native interop layer.

function Initialize-LfoSqliteInterop {
    if ('LfoWinSqlite' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class LfoWinSqlite
{
    public const int SQLITE_OK = 0;
    public const int SQLITE_ROW = 100;
    public const int SQLITE_DONE = 101;

    public const int SQLITE_INTEGER = 1;
    public const int SQLITE_FLOAT = 2;
    public const int SQLITE_TEXT = 3;
    public const int SQLITE_BLOB = 4;
    public const int SQLITE_NULL = 5;

    public const int SQLITE_OPEN_READWRITE = 0x00000002;
    public const int SQLITE_OPEN_CREATE = 0x00000004;

    public static readonly IntPtr SQLITE_TRANSIENT = new IntPtr(-1);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_libversion();

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_open_v2(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string filename,
        out IntPtr db,
        int flags,
        IntPtr zVfs);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_close_v2(IntPtr db);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_errmsg(IntPtr db);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_busy_timeout(IntPtr db, int milliseconds);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_exec(
        IntPtr db,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string sql,
        IntPtr callback,
        IntPtr arg,
        out IntPtr errmsg);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void sqlite3_free(IntPtr p);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_prepare_v2(
        IntPtr db,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string sql,
        int nByte,
        out IntPtr statement,
        IntPtr tail);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_step(IntPtr statement);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_finalize(IntPtr statement);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_reset(IntPtr statement);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_clear_bindings(IntPtr statement);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_bind_null(IntPtr statement, int index);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_bind_int64(IntPtr statement, int index, long value);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_bind_double(IntPtr statement, int index, double value);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_bind_text(
        IntPtr statement,
        int index,
        [MarshalAs(UnmanagedType.LPUTF8Str)] string value,
        int nByte,
        IntPtr destructor);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_column_count(IntPtr statement);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_column_name(IntPtr statement, int index);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_column_type(IntPtr statement, int index);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern long sqlite3_column_int64(IntPtr statement, int index);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern double sqlite3_column_double(IntPtr statement, int index);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_column_text(IntPtr statement, int index);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_column_blob(IntPtr statement, int index);

    [DllImport("winsqlite3.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_column_bytes(IntPtr statement, int index);

    public static string Utf8(IntPtr p)
    {
        if (p == IntPtr.Zero) return null;
        int len = 0;
        while (Marshal.ReadByte(p, len) != 0) len++;
        if (len == 0) return String.Empty;
        byte[] bytes = new byte[len];
        Marshal.Copy(p, bytes, 0, len);
        return Encoding.UTF8.GetString(bytes);
    }
}
'@
}

function Get-LfoSqliteError([IntPtr]$Database) {
    if ($Database -eq [IntPtr]::Zero) { return 'SQLite error (database handle unavailable).' }
    return [LfoWinSqlite]::Utf8([LfoWinSqlite]::sqlite3_errmsg($Database))
}

function Assert-LfoSqliteRc([IntPtr]$Database, [int]$ReturnCode, [string]$Operation) {
    if ($ReturnCode -ne [LfoWinSqlite]::SQLITE_OK) {
        throw ("{0} failed (SQLite rc={1}): {2}" -f $Operation, $ReturnCode, (Get-LfoSqliteError $Database))
    }
}

function Open-LfoSqliteDatabase([string]$Path) {
    Initialize-LfoSqliteInterop

    $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
    $parent = Split-Path -Parent $fullPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $db = [IntPtr]::Zero
    $flags = [LfoWinSqlite]::SQLITE_OPEN_READWRITE -bor [LfoWinSqlite]::SQLITE_OPEN_CREATE
    $rc = [LfoWinSqlite]::sqlite3_open_v2($fullPath, [ref]$db, $flags, [IntPtr]::Zero)
    if ($rc -ne [LfoWinSqlite]::SQLITE_OK) {
        $message = Get-LfoSqliteError $db
        if ($db -ne [IntPtr]::Zero) { [void][LfoWinSqlite]::sqlite3_close_v2($db) }
        throw ("sqlite3_open_v2 failed (rc={0}): {1}" -f $rc, $message)
    }

    Assert-LfoSqliteRc $db ([LfoWinSqlite]::sqlite3_busy_timeout($db, 2500)) 'sqlite3_busy_timeout'

    return [pscustomobject]@{
        Path = $fullPath
        Handle = $db
    }
}

function Close-LfoSqliteDatabase($Connection) {
    if ($null -eq $Connection -or $Connection.Handle -eq [IntPtr]::Zero) { return }
    $rc = [LfoWinSqlite]::sqlite3_close_v2([IntPtr]$Connection.Handle)
    if ($rc -ne [LfoWinSqlite]::SQLITE_OK) {
        throw ("sqlite3_close_v2 failed (rc={0}): {1}" -f $rc, (Get-LfoSqliteError ([IntPtr]$Connection.Handle)))
    }
    $Connection.Handle = [IntPtr]::Zero
}

function Invoke-LfoSqliteExec($Connection, [string]$Sql) {
    if ([string]::IsNullOrWhiteSpace($Sql)) { return }

    $err = [IntPtr]::Zero
    $rc = [LfoWinSqlite]::sqlite3_exec(
        [IntPtr]$Connection.Handle,
        $Sql,
        [IntPtr]::Zero,
        [IntPtr]::Zero,
        [ref]$err)

    if ($rc -ne [LfoWinSqlite]::SQLITE_OK) {
        $message = if ($err -ne [IntPtr]::Zero) {
            [LfoWinSqlite]::Utf8($err)
        } else {
            Get-LfoSqliteError ([IntPtr]$Connection.Handle)
        }
        if ($err -ne [IntPtr]::Zero) { [LfoWinSqlite]::sqlite3_free($err) }
        throw ("sqlite3_exec failed (rc={0}): {1}" -f $rc, $message)
    }

    if ($err -ne [IntPtr]::Zero) { [LfoWinSqlite]::sqlite3_free($err) }
}

function Set-LfoSqliteBindings([IntPtr]$Statement, [object[]]$Parameters) {
    if ($null -eq $Parameters) { return }

    for ($i = 0; $i -lt $Parameters.Count; $i++) {
        $index = $i + 1
        $value = $Parameters[$i]

        if ($null -eq $value) {
            $rc = [LfoWinSqlite]::sqlite3_bind_null($Statement, $index)
        } elseif ($value -is [bool]) {
            $rc = [LfoWinSqlite]::sqlite3_bind_int64($Statement, $index, $(if ($value) { 1 } else { 0 }))
        } elseif ($value -is [byte] -or $value -is [int16] -or $value -is [int32] -or $value -is [int64] -or
                  $value -is [uint16] -or $value -is [uint32]) {
            $rc = [LfoWinSqlite]::sqlite3_bind_int64($Statement, $index, [int64]$value)
        } elseif ($value -is [single] -or $value -is [double] -or $value -is [decimal]) {
            $rc = [LfoWinSqlite]::sqlite3_bind_double($Statement, $index, [double]$value)
        } else {
            $rc = [LfoWinSqlite]::sqlite3_bind_text(
                $Statement,
                $index,
                [string]$value,
                -1,
                [LfoWinSqlite]::SQLITE_TRANSIENT)
        }

        if ($rc -ne [LfoWinSqlite]::SQLITE_OK) {
            throw ("sqlite3_bind failed at parameter {0} (rc={1})" -f $index, $rc)
        }
    }
}

function New-LfoSqliteStatement($Connection, [string]$Sql, [object[]]$Parameters) {
    $statement = [IntPtr]::Zero
    $rc = [LfoWinSqlite]::sqlite3_prepare_v2(
        [IntPtr]$Connection.Handle,
        $Sql,
        -1,
        [ref]$statement,
        [IntPtr]::Zero)
    Assert-LfoSqliteRc ([IntPtr]$Connection.Handle) $rc 'sqlite3_prepare_v2'

    try {
        Set-LfoSqliteBindings $statement $Parameters
        return $statement
    } catch {
        if ($statement -ne [IntPtr]::Zero) { [void][LfoWinSqlite]::sqlite3_finalize($statement) }
        throw
    }
}

function Invoke-LfoSqliteNonQuery($Connection, [string]$Sql, [object[]]$Parameters = @()) {
    $statement = New-LfoSqliteStatement $Connection $Sql $Parameters
    try {
        $rc = [LfoWinSqlite]::sqlite3_step($statement)
        if ($rc -ne [LfoWinSqlite]::SQLITE_DONE) {
            throw ("sqlite3_step expected DONE but returned {0}: {1}" -f $rc, (Get-LfoSqliteError ([IntPtr]$Connection.Handle)))
        }
    } finally {
        if ($statement -ne [IntPtr]::Zero) { [void][LfoWinSqlite]::sqlite3_finalize($statement) }
    }
}

function Invoke-LfoSqliteQuery($Connection, [string]$Sql, [object[]]$Parameters = @()) {
    $statement = New-LfoSqliteStatement $Connection $Sql $Parameters
    try {
        while ($true) {
            $rc = [LfoWinSqlite]::sqlite3_step($statement)
            if ($rc -eq [LfoWinSqlite]::SQLITE_DONE) { break }
            if ($rc -ne [LfoWinSqlite]::SQLITE_ROW) {
                throw ("sqlite3_step expected ROW/DONE but returned {0}: {1}" -f $rc, (Get-LfoSqliteError ([IntPtr]$Connection.Handle)))
            }

            $row = [ordered]@{}
            $count = [LfoWinSqlite]::sqlite3_column_count($statement)
            for ($i = 0; $i -lt $count; $i++) {
                $name = [LfoWinSqlite]::Utf8([LfoWinSqlite]::sqlite3_column_name($statement, $i))
                $type = [LfoWinSqlite]::sqlite3_column_type($statement, $i)

                switch ($type) {
                    ([LfoWinSqlite]::SQLITE_INTEGER) {
                        $value = [LfoWinSqlite]::sqlite3_column_int64($statement, $i)
                    }
                    ([LfoWinSqlite]::SQLITE_FLOAT) {
                        $value = [LfoWinSqlite]::sqlite3_column_double($statement, $i)
                    }
                    ([LfoWinSqlite]::SQLITE_TEXT) {
                        $value = [LfoWinSqlite]::Utf8([LfoWinSqlite]::sqlite3_column_text($statement, $i))
                    }
                    ([LfoWinSqlite]::SQLITE_BLOB) {
                        $length = [LfoWinSqlite]::sqlite3_column_bytes($statement, $i)
                        if ($length -le 0) {
                            $value = [byte[]]@()
                        } else {
                            $value = New-Object byte[] $length
                            [Runtime.InteropServices.Marshal]::Copy(
                                [LfoWinSqlite]::sqlite3_column_blob($statement, $i),
                                $value,
                                0,
                                $length)
                        }
                    }
                    default {
                        $value = $null
                    }
                }

                $row[$name] = $value
            }
            [pscustomobject]$row
        }
    } finally {
        if ($statement -ne [IntPtr]::Zero) { [void][LfoWinSqlite]::sqlite3_finalize($statement) }
    }
}

function Initialize-LfoMemoryStoreSchema($Connection) {
    Invoke-LfoSqliteExec $Connection @'
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA temp_store = MEMORY;

CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS entities (
    id             INTEGER PRIMARY KEY,
    canonical_name TEXT NOT NULL COLLATE NOCASE UNIQUE,
    entity_type    TEXT NULL,
    created_turn   INTEGER NULL,
    created_at     TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS facts (
    id                INTEGER PRIMARY KEY,
    subject_entity_id INTEGER NOT NULL REFERENCES entities(id),
    predicate         TEXT NOT NULL,
    object_entity_id  INTEGER NULL REFERENCES entities(id),
    literal_type      TEXT NULL,
    value_text        TEXT NULL,
    value_integer     INTEGER NULL,
    value_real        REAL NULL,
    valid_from_turn   INTEGER NULL,
    valid_to_turn     INTEGER NULL,
    source_turn       INTEGER NULL,
    created_at        TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CHECK (
        (object_entity_id IS NOT NULL AND literal_type IS NULL) OR
        (object_entity_id IS NULL AND literal_type IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS ix_facts_current_subject_predicate
ON facts(subject_entity_id, predicate)
WHERE valid_to_turn IS NULL;

CREATE INDEX IF NOT EXISTS ix_facts_current_object
ON facts(object_entity_id, predicate)
WHERE valid_to_turn IS NULL AND object_entity_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_facts_current_literal_text
ON facts(predicate, value_text)
WHERE valid_to_turn IS NULL AND value_text IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_facts_current_literal_integer
ON facts(predicate, value_integer)
WHERE valid_to_turn IS NULL AND value_integer IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_facts_current_literal_real
ON facts(predicate, value_real)
WHERE valid_to_turn IS NULL AND value_real IS NOT NULL;

CREATE VIEW IF NOT EXISTS current_facts AS
SELECT *
FROM facts
WHERE valid_to_turn IS NULL;

INSERT INTO meta(key, value)
VALUES ('schema_version', '1')
ON CONFLICT(key) DO UPDATE SET value = excluded.value;
'@
}

function Open-LfoMemoryStore([string]$Path) {
    $connection = Open-LfoSqliteDatabase $Path
    try {
        Initialize-LfoMemoryStoreSchema $connection
        return $connection
    } catch {
        Close-LfoSqliteDatabase $connection
        throw
    }
}

function Start-LfoMemoryTransaction($Connection) {
    Invoke-LfoSqliteExec $Connection 'BEGIN IMMEDIATE;'
}

function Complete-LfoMemoryTransaction($Connection) {
    Invoke-LfoSqliteExec $Connection 'COMMIT;'
}

function Undo-LfoMemoryTransaction($Connection) {
    Invoke-LfoSqliteExec $Connection 'ROLLBACK;'
}


# Logical L2 operations -------------------------------------------------------
# These functions define the stable fact-operation contract above SQLite.
# They deliberately avoid exposing SQL or row-layout details to QwenChat.

function Get-LfoMemoryEntityId(
    $Connection,
    [string]$CanonicalName,
    [string]$EntityType = $null,
    [Nullable[int64]]$SourceTurn = $null
) {
    if ([string]::IsNullOrWhiteSpace($CanonicalName)) {
        throw 'CanonicalName must not be empty.'
    }

    Invoke-LfoSqliteNonQuery $Connection @'
INSERT INTO entities(canonical_name, entity_type, created_turn)
VALUES (?1, ?2, ?3)
ON CONFLICT(canonical_name) DO UPDATE SET
    entity_type = COALESCE(entities.entity_type, excluded.entity_type);
'@ @($CanonicalName.Trim(), $EntityType, $SourceTurn)

    $row = @(Invoke-LfoSqliteQuery $Connection @'
SELECT id
FROM entities
WHERE canonical_name = ?1
LIMIT 1;
'@ @($CanonicalName.Trim()))

    if ($row.Count -ne 1) {
        throw "Entity lookup failed after upsert: $CanonicalName"
    }

    return [int64]$row[0].id
}

function ConvertTo-LfoMemoryLiteral($Value) {
    if ($null -eq $Value) {
        throw 'L2 literal values must not be null. Use a retract operation instead.'
    }

    if ($Value -is [bool]) {
        return [pscustomobject]@{
            Type = 'boolean'
            Text = $null
            Integer = $(if ($Value) { [int64]1 } else { [int64]0 })
            Real = $null
        }
    }

    if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or
        $Value -is [uint16] -or $Value -is [uint32]) {
        return [pscustomobject]@{
            Type = 'integer'
            Text = $null
            Integer = [int64]$Value
            Real = $null
        }
    }

    if ($Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        return [pscustomobject]@{
            Type = 'real'
            Text = $null
            Integer = $null
            Real = [double]$Value
        }
    }

    return [pscustomobject]@{
        Type = 'text'
        Text = [string]$Value
        Integer = $null
        Real = $null
    }
}

function Test-LfoSameLiteralFact(
    $Connection,
    [int64]$SubjectEntityId,
    [string]$Predicate,
    $Literal
) {
    $rows = @(Invoke-LfoSqliteQuery $Connection @'
SELECT id
FROM current_facts
WHERE subject_entity_id = ?1
  AND predicate = ?2
  AND literal_type = ?3
  AND (
       (?3 = 'text'    AND value_text = ?4) OR
       (?3 = 'integer' AND value_integer = ?5) OR
       (?3 = 'boolean' AND value_integer = ?5) OR
       (?3 = 'real'    AND value_real = ?6)
  )
LIMIT 1;
'@ @(
        $SubjectEntityId,
        $Predicate,
        $Literal.Type,
        $Literal.Text,
        $Literal.Integer,
        $Literal.Real
    ))

    return ($rows.Count -gt 0)
}

function Set-LfoMemoryAttribute(
    $Connection,
    [string]$Subject,
    [string]$Predicate,
    $Value,
    [Nullable[int64]]$SourceTurn = $null,
    [string]$EntityType = $null
) {
    if ([string]::IsNullOrWhiteSpace($Predicate)) {
        throw 'Predicate must not be empty.'
    }

    $subjectId = Get-LfoMemoryEntityId $Connection $Subject $EntityType $SourceTurn
    $literal = ConvertTo-LfoMemoryLiteral $Value
    $turn = if ($null -eq $SourceTurn) { $null } else { [int64]$SourceTurn }

    if (Test-LfoSameLiteralFact $Connection $subjectId $Predicate $literal) {
        return [pscustomobject]@{
            Operation = 'set_attribute'
            Status = 'duplicate'
            Subject = $Subject
            Predicate = $Predicate
            Value = $Value
            SourceTurn = $turn
        }
    }

    Invoke-LfoSqliteNonQuery $Connection @'
UPDATE facts
SET valid_to_turn = ?3
WHERE subject_entity_id = ?1
  AND predicate = ?2
  AND valid_to_turn IS NULL;
'@ @($subjectId, $Predicate, $turn)

    Invoke-LfoSqliteNonQuery $Connection @'
INSERT INTO facts(
    subject_entity_id,
    predicate,
    literal_type,
    value_text,
    value_integer,
    value_real,
    valid_from_turn,
    source_turn
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7);
'@ @(
        $subjectId,
        $Predicate,
        $literal.Type,
        $literal.Text,
        $literal.Integer,
        $literal.Real,
        $turn
    )

    return [pscustomobject]@{
        Operation = 'set_attribute'
        Status = 'written'
        Subject = $Subject
        Predicate = $Predicate
        Value = $Value
        SourceTurn = $turn
    }
}

function Add-LfoMemoryRelation(
    $Connection,
    [string]$Subject,
    [string]$Predicate,
    [string]$Object,
    [Nullable[int64]]$SourceTurn = $null,
    [string]$SubjectType = $null,
    [string]$ObjectType = $null
) {
    if ([string]::IsNullOrWhiteSpace($Predicate)) {
        throw 'Predicate must not be empty.'
    }

    $subjectId = Get-LfoMemoryEntityId $Connection $Subject $SubjectType $SourceTurn
    $objectId = Get-LfoMemoryEntityId $Connection $Object $ObjectType $SourceTurn
    $turn = if ($null -eq $SourceTurn) { $null } else { [int64]$SourceTurn }

    $existing = @(Invoke-LfoSqliteQuery $Connection @'
SELECT id
FROM current_facts
WHERE subject_entity_id = ?1
  AND predicate = ?2
  AND object_entity_id = ?3
LIMIT 1;
'@ @($subjectId, $Predicate, $objectId))

    if ($existing.Count -gt 0) {
        return [pscustomobject]@{
            Operation = 'add_relation'
            Status = 'duplicate'
            Subject = $Subject
            Predicate = $Predicate
            Object = $Object
            SourceTurn = $turn
        }
    }

    Invoke-LfoSqliteNonQuery $Connection @'
INSERT INTO facts(
    subject_entity_id,
    predicate,
    object_entity_id,
    valid_from_turn,
    source_turn
)
VALUES (?1, ?2, ?3, ?4, ?4);
'@ @($subjectId, $Predicate, $objectId, $turn)

    return [pscustomobject]@{
        Operation = 'add_relation'
        Status = 'written'
        Subject = $Subject
        Predicate = $Predicate
        Object = $Object
        SourceTurn = $turn
    }
}

function Get-LfoMemoryCurrentAttribute(
    $Connection,
    [string]$Subject,
    [string]$Predicate
) {
    $rows = @(Invoke-LfoSqliteQuery $Connection @'
SELECT
    e.canonical_name AS subject,
    f.predicate,
    f.literal_type,
    f.value_text,
    f.value_integer,
    f.value_real,
    f.valid_from_turn,
    f.source_turn
FROM current_facts f
JOIN entities e ON e.id = f.subject_entity_id
WHERE e.canonical_name = ?1
  AND f.predicate = ?2
  AND f.literal_type IS NOT NULL
ORDER BY f.id DESC;
'@ @($Subject, $Predicate))

    foreach ($row in $rows) {
        $value = switch ([string]$row.literal_type) {
            'integer' { [int64]$row.value_integer }
            'boolean' { ([int64]$row.value_integer -ne 0) }
            'real'    { [double]$row.value_real }
            default   { [string]$row.value_text }
        }

        [pscustomobject]@{
            Subject = [string]$row.subject
            Predicate = [string]$row.predicate
            ValueType = [string]$row.literal_type
            Value = $value
            ValidFromTurn = $row.valid_from_turn
            SourceTurn = $row.source_turn
        }
    }
}
