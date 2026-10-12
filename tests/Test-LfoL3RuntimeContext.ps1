# L3 runtime-context gate: opt-in context assembly, prompt reduction and baseline fallback.
# TEMP-only. No Ollama, network or production memory.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$files = @(
    'src\LfoStructuredMemory.ps1',
    'src\LfoMemoryStore.ps1',
    'src\LfoStructuredRetrieval.ps1',
    'src\LfoTurnTelemetry.ps1',
    'src\QwenMemory.ps1',
    'src\LfoL3Store.ps1',
    'src\LfoL3Planner.ps1',
    'src\LfoL3Runtime.ps1'
)
foreach ($relative in $files) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $relative),[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        throw ("Syntax FAIL {0}: {1}" -f $relative,(($errors | ForEach-Object Message) -join '; '))
    }
}

. (Join-Path $repoRoot 'src\LfoStructuredMemory.ps1')
. (Join-Path $repoRoot 'src\LfoMemoryStore.ps1')
. (Join-Path $repoRoot 'src\LfoStructuredRetrieval.ps1')
. (Join-Path $repoRoot 'src\LfoTurnTelemetry.ps1')
. (Join-Path $repoRoot 'src\QwenMemory.ps1')
. (Join-Path $repoRoot 'src\LfoL3Store.ps1')
. (Join-Path $repoRoot 'src\LfoL3Planner.ps1')
. (Join-Path $repoRoot 'src\LfoL3Runtime.ps1')

$root = Join-Path $env:TEMP ('LFO-l3-runtime-' + [guid]::NewGuid().ToString('N'))
$state = Join-Path $root 'state'
$logs = Join-Path $root 'logs'
[void](New-Item -ItemType Directory -Force -Path $state)
[void](New-Item -ItemType Directory -Force -Path $logs)

$script:Config = @{
    Memory = @{
        Enabled = $true
        DataDirectory = $root
        RecentTurns = 1
        ContextMaxChars = 600
        RecentContextMaxChars = 6000
        RetrievalMaxChars = 2200
        RetrievalMaxItems = 3
        RetrievalScanMaxTurns = 500
        CompactionMaxPendingNotes = 4
        CompactionMaxPendingChars = 108
        NoteMaxChars = 40
        StateMaxChars = 160
        StructuredEnabled = $true
        StructuredReadEnabled = $true
        StructuredReadMaxItems = 6
        StructuredReadMaxChars = 800
        L3ReadEnabled = $false
        L3ReadMaxItems = 1
        L3ReadMaxChars = 220
    }
    LocalGeneration = @{
        CompactReadSchemaEnabled = $true
        LeanReadPolicyEnabled = $true
        LowerTrustL2EvidenceEnabled = $false
        MixedUserEvidenceWriteEnabled = $false
    }
}
Initialize-QwenMemoryConfiguration $null $null $null $null $null $null

$script:RuntimeState = @{ epoch=1; next_turn_id=7; completed_since_compaction=0 }
$script:Messages = @()
$script:L2StructuredMemoryTemplate = 'L2 RULES: {{L2_EVIDENCE_SCOPE}}'
function Get-OrchestratorSystemPrompt { return 'TEST ORCHESTRATOR' }

[IO.File]::WriteAllText($script:WorkingMemoryPath,'')
[IO.File]::WriteAllText($script:PendingNotesPath,'')

$conversationPath = Join-Path $logs 'conversation-2026-10.jsonl'
$rows = @(
    [ordered]@{event='turn';timestamp='2026-10-01T10:00:00Z';turn_id=1;epoch=1;route='LOCAL';user='ORION operating system and deployment details';assistant=('ORION currently runs Debian 13. ' + ('Deployment background and historical context. ' * 12))},
    [ordered]@{event='turn';timestamp='2026-10-01T10:01:00Z';turn_id=2;epoch=1;route='LOCAL';user='ORION RAM configuration';assistant=('ORION has 64 GB RAM. ' + ('Memory configuration background. ' * 12))},
    [ordered]@{event='turn';timestamp='2026-10-01T10:02:00Z';turn_id=3;epoch=1;route='LOCAL';user='LFO database architecture';assistant=('LFO uses separate memory layers. ' + ('Architecture discussion. ' * 12))},
    [ordered]@{event='turn';timestamp='2026-10-01T10:03:00Z';turn_id=4;epoch=1;route='LOCAL';user='Amiga operating system notes';assistant=('Amiga uses Kickstart and Workbench. ' + ('Retrocomputing context. ' * 12))},
    [ordered]@{event='turn';timestamp='2026-10-01T10:04:00Z';turn_id=5;epoch=1;route='LOCAL';user='ORION nightly backup run';assistant=('ORION nightly backups are enabled. ' + ('Backup operational context. ' * 12))},
    [ordered]@{event='turn';timestamp='2026-10-01T10:05:00Z';turn_id=6;epoch=1;route='LOCAL';user='Unrelated recent message';assistant='Recent continuity only.'}
)
foreach ($row in $rows) {
    [IO.File]::AppendAllText($conversationPath,($row | ConvertTo-Json -Compress) + [Environment]::NewLine)
}

$l2 = Open-LfoMemoryStore $script:StructuredMemoryPath
try {
    [void](Set-LfoMemoryAttribute $l2 'ORION' 'os' 'Debian 13' 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $l2 'ORION' 'ram_gb' ([int64]64) 2 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $l2 'ORION' 'db_version' 'PostgreSQL 16' 3 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $l2 'ORION' 'nightly_backups_enabled' $true 5 'server' 'conversation:1')
    $facts = @(Invoke-LfoSqliteQuery $l2 @'
SELECT id,predicate FROM current_facts
WHERE scope_id='conversation:1'
ORDER BY id;
'@)
} finally {
    Close-LfoSqliteDatabase $l2
}
$factByPredicate = @{}
foreach ($fact in $facts) { $factByPredicate[[string]$fact.predicate] = [int64]$fact.id }

$l3 = Open-LfoL3Store $script:L3Path
try {
    Set-LfoL3TermRule $l3 'topic' 'lfo' 'LFO' 100 'runtime-topic' $true
    Set-LfoL3TermRule $l3 'entity' 'orion' 'ORION' 100 'runtime-entity' $true
    Set-LfoL3TermRule $l3 'kind' 'configuration' 'OS' 100 'runtime-kind' $true
    Set-LfoL3TermRule $l3 'kind' 'configuration' 'run' 80 'runtime-kind' $true

    $l0os = Set-LfoL3Item $l3 'conversation:1' 'L0' 'turn:1' 1 'eq:orion-os'
    [void](Set-LfoL3Facet $l3 $l0os.id 'topic' 'lfo' 1 'runtime-seed')
    [void](Set-LfoL3Facet $l3 $l0os.id 'entity' 'orion' 1 'runtime-seed')
    [void](Set-LfoL3Facet $l3 $l0os.id 'kind' 'configuration' 1 'runtime-seed')

    foreach ($predicate in @('os','ram_gb','db_version','nightly_backups_enabled')) {
        $fp = if ($predicate -eq 'os') { 'eq:orion-os' } else { 'eq:orion-' + $predicate }
        $item = Set-LfoL3Item $l3 'conversation:1' 'L2' ('fact:' + $factByPredicate[$predicate]) 5 $fp
        [void](Set-LfoL3Facet $l3 $item.id 'topic' 'lfo' 1 'runtime-seed')
        [void](Set-LfoL3Facet $l3 $item.id 'entity' 'orion' 1 'runtime-seed')
        [void](Set-LfoL3Facet $l3 $item.id 'kind' 'configuration' 1 'runtime-seed')
        if ($predicate -eq 'os') { [void](Set-LfoL3Facet $l3 $item.id 'retrieval' 'priority' 1 'runtime-seed') }
    }
} finally {
    Close-LfoSqliteDatabase $l3
}

$query = 'For LFO, what OS does ORION run?'
$script:Messages = @(@{role='system';content='TEST'},@{role='user';content=$query})

$script:L3ReadEnabled = $false
Start-LfoTurnTelemetry
$script:LfoTurnContext = $null
Start-LfoTurnContext $query
$baselineBlock = Get-LfoTurnMemoryBlock $query
$baselineStats = Get-LfoTurnContextStats
$baselineMessages = @(Get-QwenConversationMessages)
$baselineVisibleChars = (($baselineMessages | ForEach-Object { ([string]$_.content).Length }) | Measure-Object -Sum).Sum

if ($baselineStats.l2_read_items -ne 4 -or $baselineBlock -notmatch 'ORION\.ram_gb = 64' -or
    $baselineBlock -notmatch 'ORION\.db_version = PostgreSQL 16') {
    throw 'Baseline fixture did not expose the expected broad ORION context.'
}

$script:L3ReadEnabled = $true
Start-LfoTurnTelemetry
$script:LfoTurnContext = $null
Start-LfoTurnContext $query
$l3Block = Get-LfoTurnMemoryBlock $query
$l3Stats = Get-LfoTurnContextStats
$l3Messages = @(Get-QwenConversationMessages)
$l3VisibleChars = (($l3Messages | ForEach-Object { ([string]$_.content).Length }) | Measure-Object -Sum).Sum

if (-not $l3Stats.l3_used -or $l3Stats.l3_status -ne 'ok') { throw 'L3 runtime path was not used.' }
if ($l3Stats.l2_read_items -ne 1 -or $l3Block -notmatch 'ORION\.os = Debian 13') {
    throw 'L3 runtime path did not retain the required current OS fact.'
}
if ($l3Block -match 'ORION\.ram_gb|ORION\.db_version|nightly_backups_enabled|Deployment background') {
    throw 'L3 runtime path retained irrelevant/duplicate ORION context.'
}
if ($l3Block -match 'topic|entity|kind|source_ref|retrieval') {
    throw 'L3 internal metadata leaked into model-visible memory.'
}
if ($l3Stats.memory_block_chars -ge $baselineStats.memory_block_chars -or $l3VisibleChars -ge $baselineVisibleChars) {
    throw 'L3 runtime path did not reduce model-visible context.'
}

# Unknown query: enabled L3 must fail open to exactly the baseline memory block.
$unknown = 'What happened yesterday?'
$script:Messages = @(@{role='system';content='TEST'},@{role='user';content=$unknown})
$script:L3ReadEnabled = $false
Start-LfoTurnTelemetry
$script:LfoTurnContext = $null
Start-LfoTurnContext $unknown
$unknownBaseline = Get-LfoTurnMemoryBlock $unknown

$script:L3ReadEnabled = $true
Start-LfoTurnTelemetry
$script:LfoTurnContext = $null
Start-LfoTurnContext $unknown
$unknownL3 = Get-LfoTurnMemoryBlock $unknown
$unknownStats = Get-LfoTurnContextStats
if ($unknownL3 -cne $unknownBaseline -or $unknownStats.l3_used -or $unknownStats.l3_status -ne 'no_query_facets') {
    throw 'L3 fallback parity failed for an unclassified query.'
}

[pscustomobject]@{
    PASS = $true
    BaselineMemoryChars = $baselineStats.memory_block_chars
    L3MemoryChars = $l3Stats.memory_block_chars
    MemoryCharsSaved = $baselineStats.memory_block_chars - $l3Stats.memory_block_chars
    BaselineModelVisibleChars = $baselineVisibleChars
    L3ModelVisibleChars = $l3VisibleChars
    ModelVisibleCharsSaved = $baselineVisibleChars - $l3VisibleChars
    BaselineL2Items = $baselineStats.l2_read_items
    L3L2Items = $l3Stats.l2_read_items
    L3Candidates = $l3Stats.l3_candidates
    L3Selected = $l3Stats.l3_selected
    L3Seconds = $l3Stats.l3_seconds
    FallbackParity = $true
    InternalMetadataVisible = $false
    ModelCalls = 0
    ProductionMemoryTouched = $false
    TempFixture = $root
} | Format-List
