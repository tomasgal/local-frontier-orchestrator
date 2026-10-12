# Focused LIVE2 no-match adjudication/retest.
# Reuses the full five-case offline preflight, then performs only four local Ollama calls.
[CmdletBinding()]
param([string]$Model='qwen3.5:4b-q4_K_M',[ValidateRange(2,3)][int]$Repetitions=2)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Invoke-L3Live2Offline.ps1') -Model $Model

$query='What is known about QUASAR_NOMATCH_0928; if no information is present, answer UNKNOWN?'
try {
  $ollama=Invoke-RestMethod -Uri ([string]$script:Config.BaseUri + '/api/version') -Method Get -TimeoutSec 3
} catch {
  throw "Ollama is not responding at $($script:Config.BaseUri)."
}

$format=@{
  type='object'
  properties=@{
    route=@{type='string';enum=@('LOCAL','FRONTIER')}
    answer=@{type='string'}
  }
  required=@('route','answer')
  additionalProperties=$false
}

function Invoke-NoMatchVariant([string]$Variant,[int]$Repetition) {
  $script:L3ReadEnabled=($Variant -ceq 'l3')
  $script:Messages=@(@{role='user';content=$query})
  $script:LfoTurnContext=$null
  Start-LfoTurnTelemetry
  Start-LfoTurnContext $query
  $stats=Get-LfoTurnContextStats
  $messages=@(Get-QwenConversationMessages)
  $visible=[int](($messages|ForEach-Object{([string]$_.content).Length}|Measure-Object -Sum).Sum)
  $body=@{
    model=$Model;messages=$messages;think=$false;stream=$false;keep_alive='5m';format=$format
    options=@{num_predict=128;temperature=0.0}
  }|ConvertTo-Json -Depth 12 -Compress
  $sw=[Diagnostics.Stopwatch]::StartNew()
  $response=Invoke-RestMethod -Uri ([string]$script:Config.BaseUri + '/api/chat') -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
  $sw.Stop()
  $parsed=$null
  try{$parsed=([string]$response.message.content)|ConvertFrom-Json -ErrorAction Stop}catch{}
  $answer=if($null -ne $parsed){[string]$parsed.answer}else{''}
  $route=if($null -ne $parsed){[string]$parsed.route}else{''}
  $absence=($answer -match '(?i)\bunknown\b') -or
           ($answer -match '(?i)no\s+(?:specific\s+)?(?:information|record|memory|data)') -or
           ($answer -match '(?i)(?:information|record|memory|data)\s+is\s+not\s+available')
  [pscustomobject]@{
    Variant=$Variant;Repetition=$Repetition;Correct=($route -ceq 'LOCAL' -and $absence)
    Route=$route;Answer=$answer;PromptTokens=[int]$response.prompt_eval_count
    VisibleChars=$visible;L3Used=[bool]$stats.l3_used;L3Status=[string]$stats.l3_status
    AssemblyS=[double]$stats.assembly_seconds;WallS=[Math]::Round($sw.Elapsed.TotalSeconds,4)
  }
}

$samples=@()
for($rep=1;$rep -le $Repetitions;$rep++){
  $order=if(($rep%2)-eq 1){@('baseline','l3')}else{@('l3','baseline')}
  foreach($variant in $order){
    $x=Invoke-NoMatchVariant $variant $rep
    $samples+=$x
    Write-Host ("NO_MATCH {0} rep {1}: prompt={2}; visible={3}; l3={4}/{5}; correct={6}" -f $variant,$rep,$x.PromptTokens,$x.VisibleChars,$x.L3Used,$x.L3Status,$x.Correct)
  }
}
if(@($samples|Where-Object{-not $_.Correct}).Count -gt 0){throw 'Focused no-match correctness failed.'}
$b=@($samples|Where-Object Variant -ceq 'baseline'|Sort-Object Repetition)
$l=@($samples|Where-Object Variant -ceq 'l3'|Sort-Object Repetition)
for($i=0;$i -lt $Repetitions;$i++){
  if($b[$i].PromptTokens -ne $l[$i].PromptTokens -or $b[$i].VisibleChars -ne $l[$i].VisibleChars){
    throw ("Focused no-match prompt parity failed in repetition {0}." -f ($i+1))
  }
  if($l[$i].L3Used -or $l[$i].L3Status -cne 'no_query_facets'){
    throw ("Focused no-match fallback status failed in repetition {0}." -f ($i+1))
  }
}
$samples|Format-Table Variant,Repetition,Correct,PromptTokens,VisibleChars,L3Used,L3Status,AssemblyS,WallS,Answer -AutoSize
[pscustomobject]@{
  PASS=$true;Commit=$head;OllamaVersion=[string]$ollama.version;Model=$Model
  ModelCalls=$samples.Count;ExactPromptParity=$true;NoQueryFacetsFallback=$true
  ProductionMemoryTouched=$false;TempFixture=$root
}|Format-List
