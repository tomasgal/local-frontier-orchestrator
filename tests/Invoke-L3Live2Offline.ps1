# L3-LIVE2 real retrieval probes. Always offline; no Ollama API calls.
# A failed retrieval shape is a legitimate FAIL, never automatically adjusted to a PASS.
[CmdletBinding()]
param([string]$Model='qwen3.5:4b-q4_K_M')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$branch = (& git -C $repo branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -cne 'v9.5-l3-selective-index') {
    throw "Wrong branch: expected v9.5-l3-selective-index, got '$branch'"
}
$dirty = @(& git -C $repo status --porcelain)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Dirty or unreadable Git worktree.' }
$head = (& git -C $repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -cnotmatch '^[0-9a-f]{40}$') { throw 'Invalid checkout HEAD.' }

foreach ($relative in @(
    'src\LfoStructuredMemory.ps1',
    'src\LfoMemoryStore.ps1',
    'src\LfoStructuredRetrieval.ps1',
    'src\LfoTurnTelemetry.ps1',
    'src\QwenMemory.ps1',
    'src\LfoL3Store.ps1',
    'src\LfoL3Planner.ps1',
    'src\LfoL3Runtime.ps1',
    'src\LfoL3Indexer.ps1'
)) {
    $file = Join-Path $repo $relative
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        throw ("Syntax FAIL {0}: {1}" -f $relative,(($errors | ForEach-Object Message) -join '; '))
    }
}

$baseConfigPath = Join-Path $repo 'config\QwenChat-L2Frozen.config.psd1'
$script:Config = Import-PowerShellDataFile -LiteralPath $baseConfigPath
$root = Join-Path $env:TEMP ('LFO-l3-live2-' + [guid]::NewGuid().ToString('N'))
$state = Join-Path $root 'state'
$logs = Join-Path $root 'logs'
[void](New-Item -ItemType Directory -Force -Path $state)
[void](New-Item -ItemType Directory -Force -Path $logs)

$script:Config.Memory.DataDirectory = $root
$script:Config.Memory['L3ReadEnabled'] = $false
$script:Config.Memory['L3ReadMaxItems'] = 3
$script:Config.Memory['L3ReadMaxChars'] = 1200
$script:Config.Memory['L3IndexEnabled'] = $false
$script:Config.Memory['L3TopicRules'] = @(@{ Topic='lfo'; Terms=@('LFO'); Priority=100 }, @{ Topic='archive'; Terms=@('RETRO_ARCHIVE'); Priority=100 })
$script:Config.Memory.RecentTurns = 1
$script:Config.Memory.RetrievalMaxItems = 3
$script:Config.Memory.RetrievalMaxChars = 2200

. (Join-Path $repo 'src\LfoStructuredMemory.ps1')
. (Join-Path $repo 'src\LfoMemoryStore.ps1')
. (Join-Path $repo 'src\LfoStructuredRetrieval.ps1')
. (Join-Path $repo 'src\LfoTurnTelemetry.ps1')
. (Join-Path $repo 'src\QwenMemory.ps1')
. (Join-Path $repo 'src\LfoL3Store.ps1')
. (Join-Path $repo 'src\LfoL3Planner.ps1')
. (Join-Path $repo 'src\LfoL3Runtime.ps1')
. (Join-Path $repo 'src\LfoL3Indexer.ps1')

$script:OrchestratorSystemTemplate = (Get-Content -LiteralPath (Join-Path $repo 'policy\orchestrator-system.txt') -Raw -Encoding UTF8).TrimEnd()
$script:L2StructuredMemoryTemplate = (Get-Content -LiteralPath (Join-Path $repo 'policy\l2-structured-memory.txt') -Raw -Encoding UTF8).TrimEnd()
function Get-OrchestratorSystemPrompt {
    return $script:OrchestratorSystemTemplate.Replace('{{CURRENT_DATE}}',(Get-Date).ToString('yyyy-MM-dd'))
}

Initialize-QwenMemoryConfiguration $null $null $null $null $null $null
$script:RuntimeState = [pscustomobject]@{
    version=2
    memory_schema=2
    epoch=1
    next_turn_id=3
    completed_since_compaction=0
}
$script:Messages = @()
[IO.File]::WriteAllText($script:WorkingMemoryPath,'',(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($script:PendingNotesPath,'',(New-Object Text.UTF8Encoding($false)))

function Add-FixtureTurn([int]$TurnId,[string]$User,[string]$Assistant) {
    $row = [ordered]@{
        event='turn'; timestamp=(Get-Date).ToString('o'); turn_id=$TurnId
        epoch=1; route='LOCAL'; user=$User; assistant=$Assistant
    }
    [IO.File]::AppendAllText(
        (Join-Path $logs 'conversation-2026-10.jsonl'),
        ($row | ConvertTo-Json -Compress) + [Environment]::NewLine,
        (New-Object Text.UTF8Encoding($false))
    )
}


# Unique synthetic data; no access to production memory.
Add-FixtureTurn 1 'For LFO BENCH_SERVER runs Synthetic OS 11 with 96 GB RAM, 512 GB disk and 8 CPUs.' 'Recorded configuration.'
Add-FixtureTurn 2 'For LFO correction: BENCH_SERVER now runs Synthetic OS 13.' 'Confirmed correction.'
Add-FixtureTurn 3 'RETRO_ARCHIVE contains the fictional HALCYON-77 catalog token for archival testing.' 'Archival HALCYON-77 record was indexed.'
Add-FixtureTurn 4 'Unrelated continuity.' 'Acknowledged.'
$l2 = Open-LfoMemoryStore $script:StructuredMemoryPath
try {
  [void](Set-LfoMemoryAttribute $l2 'BENCH_SERVER' 'os' 'Synthetic OS 11' 1 'server' 'conversation:1')
  [void](Set-LfoMemoryAttribute $l2 'BENCH_SERVER' 'ram_gb' ([int64]96) 1 'server' 'conversation:1')
  [void](Set-LfoMemoryAttribute $l2 'BENCH_SERVER' 'disk_gb' ([int64]512) 1 'server' 'conversation:1')
  [void](Set-LfoMemoryAttribute $l2 'BENCH_SERVER' 'cpu_count' ([int64]8) 1 'server' 'conversation:1')
  [void](Set-LfoMemoryAttribute $l2 'BENCH_SERVER' 'os' 'Synthetic OS 13' 2 'server' 'conversation:1')
} finally { Close-LfoSqliteDatabase $l2 }
$index1 = Invoke-LfoL3PostTurnIndex 'For LFO BENCH_SERVER runs Synthetic OS 11 with 96 GB RAM, 512 GB disk and 8 CPUs.' 'Recorded configuration.' 1 1 $script:StructuredMemoryPath $script:L3Path $script:L3TopicRules
$index2 = Invoke-LfoL3PostTurnIndex 'For LFO correction: BENCH_SERVER now runs Synthetic OS 13.' 'Confirmed correction.' 2 1 $script:StructuredMemoryPath $script:L3Path $script:L3TopicRules
$index3 = Invoke-LfoL3PostTurnIndex 'RETRO_ARCHIVE contains the fictional HALCYON-77 catalog token for archival testing.' 'Archival HALCYON-77 record was indexed.' 3 1 $script:StructuredMemoryPath $script:L3Path $script:L3TopicRules
foreach($x in @($index1,$index2,$index3)) { if($x.Status -ne 'ok') { throw ('Index failed: ' + ($x | ConvertTo-Json -Compress)) } }

function Invoke-Probe([string]$Question,[string]$Variant) {
  $script:L3ReadEnabled = ($Variant -ceq 'l3')
  $script:Messages = @(@{role='user';content=$Question})
  $script:LfoTurnContext = $null
  Start-LfoTurnTelemetry
  Start-LfoTurnContext $Question
  $stats = Get-LfoTurnContextStats
  $messages = @(Get-QwenConversationMessages)
  $context = ($messages | ForEach-Object { [string]$_.content }) -join "`n"
  return [pscustomobject]@{
    query=$Question; model=$Model; context=$context
    model_visible_chars=$context.Length; model_calls=0
    l2_status=[string]$stats.l2_read_status
    l2_items=[int]$stats.l2_read_items
    l0_items=[int]$stats.l0_old_data_items
    l3_used=[bool]$stats.l3_used
    l3_status=[string]$stats.l3_status
    l3_candidates=[int]$stats.l3_candidates
    l3_selected=[int]$stats.l3_selected
    context_assembly_seconds=[double]$stats.assembly_seconds
  }
}
$definitions = @(
  @{ id='single_current'; query='For LFO what OS does BENCH_SERVER run?'; current_marker='Synthetic OS 13' },
  @{ id='two_current'; query='For LFO, what are the RAM size and CPU count of BENCH_SERVER?'; current_marker='96' },
  @{ id='corrected_current'; query='For LFO what is the corrected current BENCH_SERVER OS?'; current_marker='Synthetic OS 13'; historical_marker='Synthetic OS 11' },
  @{ id='topic_l0'; query='What archival catalog token was noted for RETRO_ARCHIVE?' },
  @{ id='no_match'; query='Tell me about QUASAR_NOMATCH_0928.' }
)
$cases = @()
foreach($d in $definitions) {
  $b=Invoke-Probe $d.query 'baseline'
  $l=Invoke-Probe $d.query 'l3'
  $row=[ordered]@{ id=$d.id; query=$d.query; baseline=$b; l3=$l }
  if($d.ContainsKey('current_marker')) { $row.current_marker=$d.current_marker }
  if($d.ContainsKey('historical_marker')) { $row.historical_marker=$d.historical_marker }
  $cases += [pscustomobject]$row
  Write-Host ("SHAPE {0}: baseline L2={1}; L3 {2}/{3}, L2={4}, L0={5}, chars={6}/{7}" -f $d.id,$b.l2_items,$l.l3_used,$l.l3_status,$l.l2_items,$l.l0_items,$b.model_visible_chars,$l.model_visible_chars)
}
$report=[pscustomobject]@{
  fixture_root=$root; production_memory_touched=$false; model_calls=0; model=$Model
  commit=$head; cases=@($cases)
}
$path=Join-Path $root 'live2-preflight.json'
$report | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $path -Encoding UTF8
Write-Host "PROBE REPORT: $path"
& (Join-Path $PSScriptRoot 'Assert-L3Live2Preflight.ps1') -ProbeJson $path -PassThru
if($LASTEXITCODE -ne 0) { throw 'L3-LIVE2 gate failed.' }
