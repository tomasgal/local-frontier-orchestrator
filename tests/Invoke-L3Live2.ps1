# L3-LIVE2 five-case live acceptance. TEMP fixture only; local Ollama only.
# Mandatory offline/pre-inference gate completes before the first model call.
[CmdletBinding()]
param([string]$Model='qwen3.5:4b-q4_K_M',[ValidateRange(2,3)][int]$Repetitions=2)
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
  $classDb = Open-LfoL3ReadOnly $script:L3Path
  try {
    $classification = Get-LfoL3Classification $classDb $Question
    $predicateKeys = @($classification.Predicates | ForEach-Object { [string]$_.ValueKey })
  } finally {
    if ($null -ne $classDb) { Close-LfoSqliteDatabase $classDb }
  }
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
    predicate_keys=@($predicateKeys)
    context_assembly_seconds=[double]$stats.assembly_seconds
  }
}
$definitions = @(
  @{ id='single_current'; query='For LFO what OS does BENCH_SERVER run?'; current_marker='Synthetic OS 13' },
  @{ id='two_current'; query='For LFO, what are the RAM size and CPU count of BENCH_SERVER?'; current_marker='96' },
  @{ id='corrected_current'; query='For LFO what is the corrected current BENCH_SERVER OS?'; current_marker='Synthetic OS 13'; historical_marker='Synthetic OS 11' },
  @{ id='topic_l0'; query='What archival catalog token was noted for RETRO_ARCHIVE?' },
  @{ id='no_match'; query='According to conversation memory, what is QUASAR_NOMATCH_0928? If it is absent, answer UNKNOWN.' }
)
$cases = @()
foreach($d in $definitions) {
  $b=Invoke-Probe $d.query 'baseline'
  $l=Invoke-Probe $d.query 'l3'
  $row=[ordered]@{ id=$d.id; query=$d.query; baseline=$b; l3=$l }
  if($d.ContainsKey('current_marker')) { $row.current_marker=$d.current_marker }
  if($d.ContainsKey('historical_marker')) { $row.historical_marker=$d.historical_marker }
  $cases += [pscustomobject]$row
  Write-Host ("SHAPE {0}: baseline L2={1}; L3 {2}/{3}, predicates={4}, L2={5}, L0={6}, chars={7}/{8}" -f $d.id,$b.l2_items,$l.l3_used,$l.l3_status,(@($l.predicate_keys) -join ','),$l.l2_items,$l.l0_items,$b.model_visible_chars,$l.model_visible_chars)
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


# ---------------- LIVE STAGE: reachable only after the offline gate above ----------------
try {
  $ollama = Invoke-RestMethod -Uri ([string]$script:Config.BaseUri + '/api/version') -Method Get -TimeoutSec 3
} catch {
  throw "Ollama is not responding at $($script:Config.BaseUri)."
}

$format = @{
  type='object'
  properties=@{
    route=@{type='string';enum=@('LOCAL','FRONTIER')}
    answer=@{type='string'}
  }
  required=@('route','answer')
  additionalProperties=$false
}

function Test-Live2Answer([string]$CaseId,[string]$Route,[string]$Answer) {
  if ($Route -cne 'LOCAL') { return $false }
  switch ($CaseId) {
    'single_current' {
      return ($Answer -match 'Synthetic\s+OS\s+13' -and $Answer -notmatch 'Synthetic\s+OS\s+11')
    }
    'two_current' {
      return ($Answer -match '(?<!\d)96(?!\d)' -and $Answer -match '(?<!\d)8(?!\d)')
    }
    'corrected_current' {
      return ($Answer -match 'Synthetic\s+OS\s+13' -and $Answer -notmatch 'Synthetic\s+OS\s+11')
    }
    'topic_l0' {
      return ($Answer -match 'HALCYON-77')
    }
    'no_match' {
      return ($Answer -match '(?i)unknown|not\s+(?:in|found|available|present)|no\s+(?:information|record|memory|data)')
    }
  }
  return $false
}

function Invoke-Live2Variant($Definition,[string]$Variant,[int]$Repetition) {
  $question=[string]$Definition.query
  $script:L3ReadEnabled = ($Variant -ceq 'l3')
  $script:Messages = @(@{role='user';content=$question})
  $script:LfoTurnContext = $null
  Start-LfoTurnTelemetry
  Start-LfoTurnContext $question
  $stats = Get-LfoTurnContextStats
  $messages = @(Get-QwenConversationMessages)
  $visibleChars = [int](($messages | ForEach-Object { ([string]$_.content).Length } | Measure-Object -Sum).Sum)

  $bodyObj=@{
    model=$Model
    messages=$messages
    think=$false
    stream=$false
    keep_alive='5m'
    format=$format
    options=@{num_predict=128;temperature=0.0}
  }
  $body=$bodyObj | ConvertTo-Json -Depth 12 -Compress
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $response=Invoke-RestMethod -Uri ([string]$script:Config.BaseUri + '/api/chat') -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
  $sw.Stop()

  $parsed=$null
  try { $parsed=([string]$response.message.content) | ConvertFrom-Json -ErrorAction Stop } catch {}
  $answer=if($null -ne $parsed){[string]$parsed.answer}else{''}
  $route=if($null -ne $parsed){[string]$parsed.route}else{''}
  $correct=Test-Live2Answer ([string]$Definition.id) $route $answer

  [pscustomobject]@{
    Case=[string]$Definition.id
    Variant=$Variant
    Repetition=$Repetition
    Correct=[bool]$correct
    Route=$route
    Answer=$answer
    ModelVisibleChars=$visibleChars
    MemoryBlockChars=[int]$stats.memory_block_chars
    L0Items=[int]$stats.l0_old_data_items
    L2Items=[int]$stats.l2_read_items
    L3Used=[bool]$stats.l3_used
    L3Status=[string]$stats.l3_status
    L3Candidates=[int]$stats.l3_candidates
    L3Selected=[int]$stats.l3_selected
    ContextAssemblyS=[double]$stats.assembly_seconds
    PromptTokens=[int]$response.prompt_eval_count
    PromptEvalS=[Math]::Round(([double]$response.prompt_eval_duration/1e9),4)
    OutputTokens=[int]$response.eval_count
    EvalS=[Math]::Round(([double]$response.eval_duration/1e9),4)
    WallS=[Math]::Round($sw.Elapsed.TotalSeconds,4)
    LoadS=[Math]::Round(([double]$response.load_duration/1e9),4)
  }
}

$samples=@()
foreach($d in $definitions) {
  for($rep=1;$rep -le $Repetitions;$rep++) {
    $order=if(($rep % 2)-eq 1){@('baseline','l3')}else{@('l3','baseline')}
    foreach($variant in $order) {
      Write-Host ("LIVE2 {0} {1} rep {2}/{3}" -f $d.id,$variant,$rep,$Repetitions)
      $sample=Invoke-Live2Variant $d $variant $rep
      $samples += $sample
      Write-Host ("  prompt={0}; visible={1}; L0={2}; L2={3}; wall={4:n2}s; correct={5}" -f
        $sample.PromptTokens,$sample.ModelVisibleChars,$sample.L0Items,$sample.L2Items,$sample.WallS,$sample.Correct)
    }
  }
}

$failures=@($samples | Where-Object { -not $_.Correct })
if($failures.Count -gt 0) {
  $failures | Format-Table Case,Variant,Repetition,Route,PromptTokens,Answer -AutoSize
  throw ("LIVE2 correctness gate failed: {0} sample(s)." -f $failures.Count)
}

$caseSummaries=@()
foreach($d in $definitions) {
  $caseId=[string]$d.id
  $b=@($samples | Where-Object { $_.Case -ceq $caseId -and $_.Variant -ceq 'baseline' } | Sort-Object Repetition)
  $l=@($samples | Where-Object { $_.Case -ceq $caseId -and $_.Variant -ceq 'l3' } | Sort-Object Repetition)
  if($b.Count -ne $Repetitions -or $l.Count -ne $Repetitions){throw "Unpaired LIVE2 samples: $caseId"}

  for($i=0;$i -lt $Repetitions;$i++) {
    if($l[$i].PromptTokens -gt $b[$i].PromptTokens) {
      throw ("LIVE2 prompt tokens increased for {0} rep {1}: {2}->{3}" -f $caseId,($i+1),$b[$i].PromptTokens,$l[$i].PromptTokens)
    }
    if($l[$i].ModelVisibleChars -gt $b[$i].ModelVisibleChars) {
      throw ("LIVE2 visible chars increased for {0} rep {1}." -f $caseId,($i+1))
    }
    if($caseId -in @('single_current','two_current','corrected_current')) {
      if($l[$i].PromptTokens -ge $b[$i].PromptTokens -or $l[$i].ModelVisibleChars -ge $b[$i].ModelVisibleChars) {
        throw ("LIVE2 expected clear evidence reduction for {0} rep {1}." -f $caseId,($i+1))
      }
    }
  }

  $avgBTok=($b|Measure-Object PromptTokens -Average).Average
  $avgLTok=($l|Measure-Object PromptTokens -Average).Average
  $avgBChars=($b|Measure-Object ModelVisibleChars -Average).Average
  $avgLChars=($l|Measure-Object ModelVisibleChars -Average).Average
  $avgBWall=($b|Measure-Object WallS -Average).Average
  $avgLWall=($l|Measure-Object WallS -Average).Average
  $caseSummaries += [pscustomobject]@{
    Case=$caseId
    BaselinePromptTokens=[Math]::Round($avgBTok,2)
    L3PromptTokens=[Math]::Round($avgLTok,2)
    PromptTokenDeltaPct=if($avgBTok -gt 0){[Math]::Round((100.0*($avgLTok-$avgBTok)/$avgBTok),2)}else{0}
    BaselineVisibleChars=[Math]::Round($avgBChars,2)
    L3VisibleChars=[Math]::Round($avgLChars,2)
    VisibleCharDeltaPct=if($avgBChars -gt 0){[Math]::Round((100.0*($avgLChars-$avgBChars)/$avgBChars),2)}else{0}
    BaselineWallS=[Math]::Round($avgBWall,3)
    L3WallS=[Math]::Round($avgLWall,3)
  }
}

# Exact no-match fallback is a pre-inference property; assert it again from the
# materialized probes used by this same fixture.
$noMatch=@($cases | Where-Object id -ceq 'no_match')[0]
if([string]$noMatch.baseline.context -cne [string]$noMatch.l3.context) {
  throw 'LIVE2 no-match fallback context parity changed after preflight.'
}

$samples | Select-Object Case,Variant,Repetition,Correct,L0Items,L2Items,ModelVisibleChars,PromptTokens,ContextAssemblyS,OutputTokens,WallS | Format-Table -AutoSize
$caseSummaries | Format-Table -AutoSize

$liveReport=[ordered]@{
  schema='lfo-l3-live2-v1'
  pass=$true
  commit=$head
  ollama_version=[string]$ollama.version
  model=$Model
  repetitions_per_variant=$Repetitions
  cases=5
  model_calls=$samples.Count
  expected_model_calls=(5*2*$Repetitions)
  correctness_failures=0
  exact_no_match_fallback=$true
  production_memory_touched=$false
  frontier_calls=0
  latency_interpretation='Exploratory only; AB/BA reduces order bias but this small mechanism-validation corpus does not establish a universal speedup.'
  case_summaries=@($caseSummaries)
  samples=@($samples)
}
$livePath=Join-Path $root 'live2-report.json'
$liveReport | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $livePath -Encoding UTF8

[pscustomobject]@{
  PASS=$true
  Commit=$head
  OllamaVersion=[string]$ollama.version
  Model=$Model
  Cases=5
  RepetitionsPerVariant=$Repetitions
  ModelCalls=$samples.Count
  Correctness='5/5 cases; all paired samples PASS'
  ExactNoMatchFallback=$true
  ProductionMemoryTouched=$false
  FrontierCalls=0
  ReportPath=$livePath
  LatencyInterpretation=$liveReport.latency_interpretation
} | Format-List
