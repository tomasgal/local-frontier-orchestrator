# Bounded end-to-end live comparison: frozen-style L2 read vs opt-in L3 selective context.
# TEMP-only memory fixture. Calls local Ollama, never production memory or frontier/network search.
[CmdletBinding()]
param(
    [string]$Model = 'qwen3.5:4b-q4_K_M',
    [ValidateRange(1,3)][int]$Repetitions = 2
)

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
$root = Join-Path $env:TEMP ('LFO-l3-live-' + [guid]::NewGuid().ToString('N'))
$state = Join-Path $root 'state'
$logs = Join-Path $root 'logs'
[void](New-Item -ItemType Directory -Force -Path $state)
[void](New-Item -ItemType Directory -Force -Path $logs)

$script:Config.Memory.DataDirectory = $root
$script:Config.Memory['L3ReadEnabled'] = $false
$script:Config.Memory['L3ReadMaxItems'] = 1
$script:Config.Memory['L3ReadMaxChars'] = 300
$script:Config.Memory['L3IndexEnabled'] = $false
$script:Config.Memory['L3TopicRules'] = @(
    @{ Topic='lfo'; Terms=@('LFO','Local Frontier Orchestrator'); Priority=100 }
)
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

$seedPrompt = 'For LFO, BENCH_SERVER runs Synthetic OS 13 with 96 GB RAM, a 512 GB disk and 8 CPUs.'
Add-FixtureTurn 1 $seedPrompt ('Recorded BENCH_SERVER configuration. ' + ('Background deployment context. ' * 18))
Add-FixtureTurn 2 'Unrelated recent continuity message.' 'Acknowledged.'

$l2 = Open-LfoMemoryStore $script:StructuredMemoryPath
try {
    [void](Set-LfoMemoryAttribute $l2 'BENCH_SERVER' 'os' 'Synthetic OS 13' 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $l2 'BENCH_SERVER' 'ram_gb' ([int64]96) 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $l2 'BENCH_SERVER' 'disk_gb' ([int64]512) 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $l2 'BENCH_SERVER' 'cpu_count' ([int64]8) 1 'server' 'conversation:1')
} finally {
    Close-LfoSqliteDatabase $l2
}

$index = Invoke-LfoL3PostTurnIndex $seedPrompt 'Recorded BENCH_SERVER configuration.' 1 1 $script:StructuredMemoryPath $script:L3Path $script:L3TopicRules
if ($index.Status -ne 'ok' -or -not $index.TurnIndexed -or $index.L2ItemsIndexed -ne 4) {
    throw ('Automatic L3 fixture indexing failed: ' + ($index | ConvertTo-Json -Compress))
}

try {
    $ollama = Invoke-RestMethod -Uri ([string]$script:Config.BaseUri + '/api/version') -Method Get -TimeoutSec 3
} catch {
    throw "Ollama is not responding at $($script:Config.BaseUri). Start Ollama before this live gate."
}

$query = 'For LFO, what OS does BENCH_SERVER run?'
$format = @{
    type='object'
    properties=@{
        route=@{type='string';enum=@('LOCAL','FRONTIER')}
        answer=@{type='string'}
    }
    required=@('route','answer')
    additionalProperties=$false
}

function Get-VariantContextProbe([string]$Variant) {
    $script:L3ReadEnabled = ($Variant -eq 'l3')
    $script:Messages = @(@{role='user';content=$query})
    $script:LfoTurnContext = $null
    Start-LfoTurnTelemetry
    Start-LfoTurnContext $query

    $stats = Get-LfoTurnContextStats
    $messages = @(Get-QwenConversationMessages)
    $visibleChars = [int](($messages | ForEach-Object { ([string]$_.content).Length } | Measure-Object -Sum).Sum)

    return [pscustomobject]@{
        Variant = $Variant
        L2Items = [int]$stats.l2_read_items
        L2Status = [string]$stats.l2_read_status
        L3Used = [bool]$stats.l3_used
        L3Status = [string]$stats.l3_status
        L3Candidates = [int]$stats.l3_candidates
        L3Selected = [int]$stats.l3_selected
        MemoryBlockChars = [int]$stats.memory_block_chars
        ModelVisibleChars = $visibleChars
    }
}

# Mandatory no-inference preflight. A live test is invalid unless L3 has
# actually changed the retrieval shape before the first model call.
$baselineProbe = Get-VariantContextProbe 'baseline'
$l3Probe = Get-VariantContextProbe 'l3'

Write-Host ("PREFLIGHT baseline: L2={0} status={1} visible={2}" -f
    $baselineProbe.L2Items,$baselineProbe.L2Status,$baselineProbe.ModelVisibleChars)
Write-Host ("PREFLIGHT l3: L3Used={0} L3Status={1} candidates={2} selected={3} L2={4} visible={5}" -f
    $l3Probe.L3Used,$l3Probe.L3Status,$l3Probe.L3Candidates,$l3Probe.L3Selected,
    $l3Probe.L2Items,$l3Probe.ModelVisibleChars)

if ($baselineProbe.L2Items -ne 4 -or $baselineProbe.L2Status -ne 'ok') {
    throw ('Invalid live baseline retrieval shape: ' + ($baselineProbe | ConvertTo-Json -Compress))
}
if (-not $l3Probe.L3Used -or $l3Probe.L3Status -ne 'ok' -or
    $l3Probe.L2Items -ne 1 -or $l3Probe.L3Selected -ne 1) {
    throw ('Invalid L3 live preflight: ' + ($l3Probe | ConvertTo-Json -Compress))
}
if ($l3Probe.ModelVisibleChars -ge $baselineProbe.ModelVisibleChars -or
    $l3Probe.MemoryBlockChars -ge $baselineProbe.MemoryBlockChars) {
    throw ('L3 preflight did not reduce context before inference: baseline=' +
        ($baselineProbe | ConvertTo-Json -Compress) + '; l3=' +
        ($l3Probe | ConvertTo-Json -Compress))
}

function Invoke-LiveVariant([string]$Variant,[int]$Repetition) {
    $script:L3ReadEnabled = ($Variant -eq 'l3')
    $script:Messages = @(@{role='user';content=$query})
    $script:LfoTurnContext = $null
    Start-LfoTurnTelemetry
    Start-LfoTurnContext $query

    $stats = Get-LfoTurnContextStats
    $messages = @(Get-QwenConversationMessages)
    $visibleChars = [int](($messages | ForEach-Object { ([string]$_.content).Length } | Measure-Object -Sum).Sum)
    $bodyObj = @{
        model=$Model
        messages=$messages
        think=$false
        stream=$false
        keep_alive='5m'
        format=$format
        options=@{
            num_predict=128
            temperature=0.0
        }
    }
    $body = $bodyObj | ConvertTo-Json -Depth 12 -Compress
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Uri ([string]$script:Config.BaseUri + '/api/chat') -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
    $sw.Stop()

    $parsed = $null
    try { $parsed = ([string]$response.message.content) | ConvertFrom-Json -ErrorAction Stop } catch {}
    $answer = if ($null -ne $parsed) { [string]$parsed.answer } else { '' }
    $route = if ($null -ne $parsed) { [string]$parsed.route } else { '' }
    $correct = ($route -ceq 'LOCAL' -and $answer -match 'Synthetic OS 13')

    return [pscustomobject]@{
        Variant=$Variant
        Repetition=$Repetition
        Correct=$correct
        Route=$route
        Answer=$answer
        ModelVisibleChars=$visibleChars
        MemoryBlockChars=[int]$stats.memory_block_chars
        L2Items=[int]$stats.l2_read_items
        L3Used=[bool]$stats.l3_used
        L3Status=[string]$stats.l3_status
        L3Candidates=[int]$stats.l3_candidates
        L3Selected=[int]$stats.l3_selected
        ContextAssemblyS=[double]$stats.assembly_seconds
        PromptTokens=[int]$response.prompt_eval_count
        PromptEvalS=[Math]::Round(([double]$response.prompt_eval_duration / 1e9),4)
        OutputTokens=[int]$response.eval_count
        EvalS=[Math]::Round(([double]$response.eval_duration / 1e9),4)
        WallS=[Math]::Round($sw.Elapsed.TotalSeconds,4)
        LoadS=[Math]::Round(([double]$response.load_duration / 1e9),4)
    }
}

$samples = @()
for ($rep=1; $rep -le $Repetitions; $rep++) {
    $order = if (($rep % 2) -eq 1) { @('baseline','l3') } else { @('l3','baseline') }
    foreach ($variant in $order) {
        Write-Host ("LIVE {0} repetition {1}/{2}" -f $variant,$rep,$Repetitions)
        $sample = Invoke-LiveVariant $variant $rep
        $samples += $sample
        Write-Host ("  prompt={0} tok; visible={1} chars; L2={2}; L3={3}/{4}; wall={5:n2}s; correct={6}" -f
            $sample.PromptTokens,$sample.ModelVisibleChars,$sample.L2Items,
            $sample.L3Used,$sample.L3Status,$sample.WallS,$sample.Correct)
    }
}

$baseline = @($samples | Where-Object Variant -eq 'baseline' | Sort-Object Repetition)
$l3rows = @($samples | Where-Object Variant -eq 'l3' | Sort-Object Repetition)
if ($baseline.Count -ne $Repetitions -or $l3rows.Count -ne $Repetitions) { throw 'Unpaired live samples.' }
if (@($samples | Where-Object { -not $_.Correct }).Count -gt 0) {
    $samples | Format-Table Variant,Repetition,Route,Correct,PromptTokens,WallS,Answer -AutoSize
    throw 'Live correctness gate failed.'
}

for ($i=0; $i -lt $Repetitions; $i++) {
    if ($l3rows[$i].PromptTokens -ge $baseline[$i].PromptTokens) {
        throw ("L3 prompt-token reduction failed in repetition {0}: baseline={1}, l3={2}" -f ($i+1),$baseline[$i].PromptTokens,$l3rows[$i].PromptTokens)
    }
    if ($l3rows[$i].ModelVisibleChars -ge $baseline[$i].ModelVisibleChars) {
        throw ("L3 visible-char reduction failed in repetition {0}" -f ($i+1))
    }
    if ($baseline[$i].L2Items -ne 4 -or $l3rows[$i].L2Items -ne 1 -or -not $l3rows[$i].L3Used) {
        throw ("Unexpected retrieval shape in repetition {0}" -f ($i+1))
    }
}

$avgBaseTok = ($baseline | Measure-Object PromptTokens -Average).Average
$avgL3Tok = ($l3rows | Measure-Object PromptTokens -Average).Average
$avgBaseChars = ($baseline | Measure-Object ModelVisibleChars -Average).Average
$avgL3Chars = ($l3rows | Measure-Object ModelVisibleChars -Average).Average
$avgBaseWall = ($baseline | Measure-Object WallS -Average).Average
$avgL3Wall = ($l3rows | Measure-Object WallS -Average).Average
$tokenReductionPct = 100.0 * ($avgBaseTok - $avgL3Tok) / $avgBaseTok
$charReductionPct = 100.0 * ($avgBaseChars - $avgL3Chars) / $avgBaseChars
$wallDeltaPct = 100.0 * ($avgL3Wall - $avgBaseWall) / $avgBaseWall

$samples | Select-Object Variant,Repetition,Correct,L2Items,L3Used,ModelVisibleChars,PromptTokens,PromptEvalS,OutputTokens,WallS | Format-Table -AutoSize
[pscustomobject]@{
    PASS = $true
    Commit = $head
    OllamaVersion = [string]$ollama.version
    Model = $Model
    RepetitionsPerVariant = $Repetitions
    CorrectnessMatched = $true
    BaselineAveragePromptTokens = [Math]::Round($avgBaseTok,2)
    L3AveragePromptTokens = [Math]::Round($avgL3Tok,2)
    PromptTokenReductionPercent = [Math]::Round($tokenReductionPct,2)
    BaselineAverageModelVisibleChars = [Math]::Round($avgBaseChars,2)
    L3AverageModelVisibleChars = [Math]::Round($avgL3Chars,2)
    ModelVisibleCharReductionPercent = [Math]::Round($charReductionPct,2)
    BaselineAverageWallS = [Math]::Round($avgBaseWall,3)
    L3AverageWallS = [Math]::Round($avgL3Wall,3)
    L3MinusBaselineWallPercent = [Math]::Round($wallDeltaPct,2)
    LatencyInterpretation = 'EXPLORATORY: prompt reduction is gated; wall time is reported but not accepted as universal speedup from this small paired pilot.'
    BaselineL2Items = 4
    L3L2Items = 1
    AutomaticIndexingUsed = $true
    PreInferenceRetrievalShapeValidated = $true
    BaselinePreflightVisibleChars = $baselineProbe.ModelVisibleChars
    L3PreflightVisibleChars = $l3Probe.ModelVisibleChars
    FrontierCalls = 0
    ProductionMemoryTouched = $false
    TempFixture = $root
} | Format-List
