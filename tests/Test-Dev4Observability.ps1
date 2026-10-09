# Dev4 offline regression: no Ollama call; all synthetic state lives in TEMP.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

foreach ($path in @('src\LfoTurnTelemetry.ps1','src\QwenMemory.ps1','src\QwenChat.ps1','src\LfoMemoryStore.ps1')) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $path),[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        throw ("PowerShell parser regression in {0}: {1}" -f $path,(($errors | ForEach-Object Message) -join '; '))
    }
}

. (Join-Path $repoRoot 'src\LfoTurnTelemetry.ps1')
. (Join-Path $repoRoot 'src\QwenMemory.ps1')
Start-LfoTurnTelemetry
$fake = [pscustomobject]@{
    prompt_eval_count = 120
    prompt_eval_duration = 1500000000
    eval_count = 20
    eval_duration = 2500000000
}
Add-LfoTurnPhase -Phase 'local_generation' -WallSeconds 5 -Response $fake -InputChars 320
$phases = @(Get-LfoTurnPhases)
if ($phases.Count -ne 1 -or $phases[0].prompt_eval_count -ne 120 -or
    $phases[0].eval_count -ne 20 -or $phases[0].prompt_eval_seconds -ne 1.5 -or
    $phases[0].decode_seconds -ne 2.5 -or $phases[0].other_seconds -ne 1) {
    throw 'Dev4 telemetry counter conversion FAILED'
}

$temp = Join-Path $env:TEMP ('LFO-dev4-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $temp 'state') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $temp 'logs') | Out-Null
$script:MemoryEnabled = $true
$script:MemoryRecentTurns = 1
$script:MemoryContextMaxChars = 600
$script:MemoryRecentContextMaxChars = 6000
$script:MemoryRetrievalMaxChars = 2500
$script:MemoryRetrievalMaxItems = 3
$script:MemoryRetrievalScanMaxTurns = 100
$script:StateDir = Join-Path $temp 'state'
$script:LogDir = Join-Path $temp 'logs'
$script:WorkingMemoryPath = Join-Path $script:StateDir 'working_memory.txt'
$script:PendingNotesPath = Join-Path $script:StateDir 'pending_notes.jsonl'
$script:RuntimeState = @{ epoch = 1 }
$script:Messages = @(
    @{ role = 'system'; content = 'TEST' },
    @{ role = 'user'; content = 'What hardware does LYRA have?' }
)
[IO.File]::WriteAllText($script:WorkingMemoryPath,'STATE-INITIAL')
[IO.File]::WriteAllText($script:PendingNotesPath,'')
$rows = @(
    @{ event='turn'; turn_id=1; epoch=1; user='LYRA has 48 GB RAM.'; assistant='Acknowledged.' },
    @{ event='turn'; turn_id=2; epoch=1; user='Unrelated discussion'; assistant='OK.' }
)
$logs = ($rows | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 4 }) -join "`n"
[IO.File]::WriteAllText((Join-Path $script:LogDir 'conversation-2026-10.jsonl'),$logs + "`n")
$script:LfoTurnContext = $null
Start-LfoTurnContext 'LYRA hardware'
$before = Get-LfoTurnMemoryBlock 'LYRA hardware'
$stats = Get-LfoTurnContextStats
if ($stats.l0_old_data_items -ne 1 -or $before -notmatch '48 GB RAM' -or
    @((Get-LfoTurnRecentMessages)).Count -ne 1) {
    throw 'Dev4 context assembly or L0 retrieval FAILED'
}
[IO.File]::WriteAllText($script:WorkingMemoryPath,'STATE-CHANGED')
$afterCached = Get-LfoTurnMemoryBlock 'LYRA hardware'
$afterDirect = Get-MemoryContextBlock 'LYRA hardware'
if ($afterCached -cne $before -or $afterDirect -ceq $before) {
    throw 'Dev4 turn cache failed to preserve immutable pre-turn snapshot'
}
$phaseNames = @((Get-LfoTurnPhases) | ForEach-Object { $_.phase })
if ($phaseNames.Count -ne 2 -or $phaseNames[1] -ne 'context_assembly') {
    throw 'Dev4 context phase trace missing'
}
[pscustomobject]@{
    PASS = $true
    TelemetryPhases = $phaseNames.Count
    PromptEvalSeconds = $phases[0].prompt_eval_seconds
    DecodeSeconds = $phases[0].decode_seconds
    L0Hits = $stats.l0_old_data_items
    CachedContextStable = ($afterCached -ceq $before)
    ProductionMemoryTouched = $false
    TempFixture = $temp
} | Format-List
