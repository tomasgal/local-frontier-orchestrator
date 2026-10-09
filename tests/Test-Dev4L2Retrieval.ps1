# Dev4 stage 2: offline, synthetic, isolated L2 read-side contract test.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
foreach ($relative in @('src\LfoMemoryStore.ps1','src\LfoStructuredRetrieval.ps1','src\QwenMemory.ps1','src\QwenChat.ps1','src\LfoTurnTelemetry.ps1')) {
    $errors = $null
    $tokens = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $relative),[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw ("Syntax FAIL {0}: {1}" -f $relative,(($errors | ForEach-Object Message) -join '; ')) }
}

. (Join-Path $repoRoot 'src\LfoMemoryStore.ps1')
. (Join-Path $repoRoot 'src\LfoStructuredRetrieval.ps1')
. (Join-Path $repoRoot 'src\LfoTurnTelemetry.ps1')
. (Join-Path $repoRoot 'src\QwenMemory.ps1')

$root = Join-Path $env:TEMP ('LFO-dev4-l2-read-' + [guid]::NewGuid().ToString('N'))
$state = Join-Path $root 'state'
$logs = Join-Path $root 'logs'
[void](New-Item -Path $state -ItemType Directory -Force)
[void](New-Item -Path $logs -ItemType Directory -Force)
$dbPath = Join-Path $state 'l2-memory.db'
$writer = Open-LfoMemoryStore $dbPath
try {
    [void](Set-LfoMemoryAttribute $writer 'ORION' 'os' 'Ubuntu 24.04' 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $writer 'ORION' 'ram_gb' ([int64]64) 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $writer 'ORION' 'db_version' 'PostgreSQL 16' 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $writer 'ORION' 'nightly_backups_enabled' $true 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $writer 'ORION' 'os' 'Debian 13' 2 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $writer 'ORION' 'os' 'FreeBSD 14' 1 'server' 'conversation:2')
    [void](Add-LfoMemoryRelation $writer 'Core' 'has_gpu' 'GTX1050' 3 'computer' 'gpu' 'conversation:1')
    [void](Set-LfoMemoryAttribute $writer 'GTX1050' 'vendor' 'NVIDIA' 3 'gpu' 'conversation:1')
} finally {
    Close-LfoSqliteDatabase $writer
}

$reader = Open-LfoMemoryReadOnly $dbPath
if ($null -eq $reader) { throw 'L2 read-only open returned null on existing DB' }
try {
    $keys = @(Get-LfoL2MentionKeys 'What operating system does ORION run?')
    if ($keys -notcontains 'orion') { throw 'L2 candidate generator lost ORION alias' }
    $a = Get-LfoMemoryRelevantCurrentFacts $reader $keys 'conversation:1' 6 800
    if ($a.Count -ne 4 -or $a.Text -notmatch 'ORION.os = Debian 13' -or
        $a.Text -notmatch 'ORION.ram_gb = 64' -or
        $a.Text -notmatch 'nightly_backups_enabled = true' -or
        $a.Text -notmatch 'source_turn=2' -or
        $a.Text -match 'Ubuntu 24.04|FreeBSD 14') {
        throw ('L2 current/scope/supersession FAIL: ' + $a.Text)
    }
    $scope2 = Get-LfoMemoryRelevantCurrentFacts $reader @('orion') 'conversation:2' 6 800
    if ($scope2.Count -ne 1 -or $scope2.Text -notmatch 'FreeBSD 14' -or $scope2.Text -match 'Debian 13') {
        throw 'L2 scope isolation FAILED'
    }
    $small = Get-LfoMemoryRelevantCurrentFacts $reader @('orion') 'conversation:1' 1 90
    if ($small.Count -gt 1 -or $small.Text.Length -gt 90) { throw 'L2 item/character budget FAILED' }
    $core = Get-LfoMemoryRelevantCurrentFacts $reader @('core') 'conversation:1' 6 800
    if ($core.Count -ne 1 -or $core.Text -notmatch 'Core.has_gpu = -> GTX1050') {
        throw 'L2 entity relation retrieval FAILED'
    }
    $none = Get-LfoMemoryRelevantCurrentFacts $reader @('unknownentity') 'conversation:1' 6 800
    if ($none.Count -ne 0) { throw 'L2 unmentioned entity retrieval FAILED' }
} finally {
    Close-LfoSqliteDatabase $reader
}

$script:MemoryEnabled = $true
$script:StructuredMemoryEnabled = $true
$script:L2ReadEnabled = $true
$script:L2ReadMaxItems = 6
$script:L2ReadMaxChars = 800
$script:StructuredMemoryPath = $dbPath
$script:MemoryRecentTurns = 4
$script:MemoryContextMaxChars = 600
$script:MemoryStateMaxChars = 160
$script:MemoryNoteMaxChars = 40
$script:MemoryRecentContextMaxChars = 6000
$script:MemoryRetrievalMaxChars = 2500
$script:MemoryRetrievalMaxItems = 3
$script:MemoryRetrievalScanMaxTurns = 500
$script:LogDir = $logs
$script:StateDir = $state
$script:WorkingMemoryPath = Join-Path $state 'working_memory.txt'
$script:PendingNotesPath = Join-Path $state 'pending_notes.jsonl'
$script:RuntimeState = @{ epoch = 1 }
$script:Messages = @(@{role='system';content='TEST'},@{role='user';content='What is the OS and RAM for ORION?'})
[IO.File]::WriteAllText($script:WorkingMemoryPath,'')
[IO.File]::WriteAllText($script:PendingNotesPath,'')
Start-LfoTurnTelemetry
$script:LfoTurnContext = $null
Start-LfoTurnContext 'What is the OS and RAM for ORION?'
$block = Get-LfoTurnMemoryBlock 'What is the OS and RAM for ORION?'
$stats = Get-LfoTurnContextStats
if ($block -notmatch 'CURRENT STRUCTURED FACTS' -or $block -notmatch 'Debian 13' -or
    $block -match 'Ubuntu 24.04|FreeBSD 14' -or $stats.l2_read_items -ne 4 -or
    $stats.l2_read_chars -gt 800 -or $stats.l2_read_status -ne 'ok') {
    throw 'L2 turn-context injection FAILED'
}
if (@(Get-LfoTurnPhases | Where-Object { $_.phase -eq 'l2_retrieval' }).Count -ne 1) {
    throw 'L2 phase telemetry FAILED'
}
# Verify L2 enters the actual LOCAL system prompt without changing evidence rules.
function Get-OrchestratorSystemPrompt { return 'TEST ORCHESTRATOR' }
$script:L2StructuredMemoryTemplate = 'L2 RULES: {{L2_EVIDENCE_SCOPE}}'
$assembled = @(Get-QwenConversationMessages)
if ($assembled.Count -ne 2 -or [string]$assembled[0].content -notmatch 'ORION.os = Debian 13' -or
    [string]$assembled[0].content -notmatch 'Do not derive L2 operations from old STATE' -or
    [string]$assembled[0].content -match 'Ubuntu 24.04|FreeBSD 14') {
    throw 'L2 LOCAL prompt integration/evidence guard FAILED'
}
# The small model may echo retrieved L2 data as memory_ops and micro-note.
# The persistence boundary must deterministically suppress both on LOCAL read turns,
# retaining counters describing what the model attempted to write.
$echoOps = [pscustomobject]@{
    Valid = @(
        [pscustomobject]@{ Op='SET_TEXT'; Subject='ORION'; Predicate='os'; TypedValue='Debian 13' },
        [pscustomobject]@{ Op='SET_INTEGER'; Subject='ORION'; Predicate='ram_gb'; TypedValue=[int64]64 },
        [pscustomobject]@{ Op='SET_TEXT'; Subject='ORION'; Predicate='db_version'; TypedValue='PostgreSQL 16' },
        [pscustomobject]@{ Op='SET_BOOLEAN'; Subject='ORION'; Predicate='nightly_backups_enabled'; TypedValue=$true }
    )
    Rejected = @()
}
$echoNote = [pscustomobject]@{ Text='ORION Debian 13'; Raw='ORION Debian 13' }
$guard = Protect-LfoPersistenceFromReadSide 'LOCAL' $echoOps $echoNote
if (-not $guard.GuardActive -or $guard.ModelValidCount -ne 4 -or
    $guard.SuppressedValidCount -ne 4 -or $guard.SuppressedRejectedCount -ne 0 -or
    @($guard.Ops.Valid).Count -ne 0 -or @($guard.Ops.Rejected).Count -ne 0 -or
    $null -ne $guard.Note -or -not $guard.NoteSuppressed -or
    $guard.Reason -ne 'local-l2-retrieval-is-not-new-evidence') {
    throw 'L2 local read-memory echo guard FAILED'
}
# Distinguish rejected model ops from persistence rejection.
$rejectedEcho = [pscustomobject]@{ Valid=@(); Rejected=@([pscustomobject]@{ Reason='malformed' }) }
$rejectedGuard = Protect-LfoPersistenceFromReadSide 'LOCAL' $rejectedEcho $null
if ($rejectedGuard.SuppressedRejectedCount -ne 1 -or @($rejectedGuard.Ops.Rejected).Count -ne 0) {
    throw 'L2 rejected-op read guard FAILED'
}
$writer = Open-LfoMemoryStore $dbPath
try {
    $rowsBefore = [int64]@(Invoke-LfoSqliteQuery $writer 'SELECT COUNT(*) AS n FROM facts;')[0].n
    $result = Apply-LfoStructuredMemoryOps $writer $guard.Ops 3 'conversation:1'
    $rowsAfter = [int64]@(Invoke-LfoSqliteQuery $writer 'SELECT COUNT(*) AS n FROM facts;')[0].n
    if ($result.Status -ne 'empty' -or $result.AppliedCount -ne 0 -or
        $result.RejectedCount -ne 0 -or $rowsAfter -ne $rowsBefore) {
        throw 'L2 read guard did not prevent SQLite write'
    }
} finally { Close-LfoSqliteDatabase $writer }
# A FRONTIER synthesis has independent evidence and must preserve its ops,
# while an L2-disabled LOCAL turn retains normal dev3 write semantics.
$frontierGuard = Protect-LfoPersistenceFromReadSide 'FRONTIER' $echoOps $echoNote
if ($frontierGuard.GuardActive -or @($frontierGuard.Ops.Valid).Count -ne 4 -or
    $null -eq $frontierGuard.Note) { throw 'FRONTIER evidence flow was blocked' }
$script:LfoTurnContext = $null
$nonReadGuard = Protect-LfoPersistenceFromReadSide 'LOCAL' $echoOps $echoNote
if ($nonReadGuard.GuardActive -or @($nonReadGuard.Ops.Valid).Count -ne 4 -or
    $null -eq $nonReadGuard.Note) { throw 'Ordinary LOCAL write contract regressed' }
# Restore the previous read snapshot to finish the opt-out parity check below.
Start-LfoTurnTelemetry
Start-LfoTurnContext 'What is the OS and RAM for ORION?'

# Disable read-side in the same fixture: baseline context must remain identical to L0/L1.
$script:L2ReadEnabled = $false
Start-LfoTurnTelemetry
$script:LfoTurnContext = $null
Start-LfoTurnContext 'What is the OS and RAM for ORION?'
$disabledBlock = Get-LfoTurnMemoryBlock 'What is the OS and RAM for ORION?'
if ($disabledBlock -match 'CURRENT STRUCTURED FACTS' -or (Get-LfoTurnContextStats).l2_read_items -ne 0) {
    throw 'Opt-out L2 regression FAILED'
}
$script:L2ReadEnabled = $true

# Updating a fact must not preload the older L2 value into model context.
$correction = Get-LfoRelevantCurrentL2 'Correction: ORION now runs AlmaLinux 10 instead of Debian 13.'
if ($correction.Count -ne 0 -or $correction.Status -ne 'write_only_turn') {
    throw 'L2 current-turn correction contamination guard FAILED'
}

# Probe ambiguous alias resolution: manual ambiguous entity name (no production state).
$writer = Open-LfoMemoryStore $dbPath
try {
    Invoke-LfoSqliteNonQuery $writer 'INSERT INTO entities(entity_type, created_turn) VALUES (?1, ?2);' @('server',4)
    $insertedIds = @(Invoke-LfoSqliteQuery $writer 'SELECT last_insert_rowid() AS id;')
    $otherId = [int64]$insertedIds[0].id
    Invoke-LfoSqliteNonQuery $writer 'INSERT INTO entity_names(entity_id,name,normalized_name,source_turn) VALUES (?1,?2,?3,?4);' @($otherId,'ORION','orion',4)
} finally { Close-LfoSqliteDatabase $writer }
$reader = Open-LfoMemoryReadOnly $dbPath
try {
    $ambiguous = Get-LfoMemoryRelevantCurrentFacts $reader @('orion') 'conversation:1' 6 800
    if ($ambiguous.Count -ne 0 -or $ambiguous.Status -ne 'no_unique_entity') {
        throw 'L2 ambiguous entity did not fail closed'
    }
} finally { Close-LfoSqliteDatabase $reader }

$missingDb = Join-Path $state 'does-not-exist.db'
if ($null -ne (Open-LfoMemoryReadOnly $missingDb) -or (Test-Path -LiteralPath $missingDb)) {
    throw 'Read-only retrieval created an absent SQLite file'
}
[pscustomobject]@{
    PASS = $true
    CurrentFacts = $a.Count
    CorrectedOs = ($a.Text -match 'ORION.os = Debian 13')
    ScopeIsolation = ($scope2.Count -eq 1)
    RelationRead = ($core.Count -eq 1)
    CharacterBudget = $small.Text.Length
    L2ContextCharacters = $stats.l2_read_chars
    L2ContextItems = $stats.l2_read_items
    CorrectionTurnReadSkipped = ($correction.Status -eq 'write_only_turn')
    EchoedModelFactsSuppressed = $guard.SuppressedValidCount
    ModelNoteSuppressed = $guard.NoteSuppressed
    SuppressedWriteRows = ($rowsAfter - $rowsBefore)
    FrontierOpsPreserved = (-not $frontierGuard.GuardActive)
    AmbiguousAliasFailClosed = $true
    MissingDatabaseNotCreated = $true
    ProductionMemoryTouched = $false
    TempFixture = $root
} | Format-List
