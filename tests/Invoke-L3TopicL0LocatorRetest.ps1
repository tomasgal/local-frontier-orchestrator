# Focused LIVE smoke for schema-v4 L0 byte locator.
# Full five-case offline preflight first; then only topic_l0 baseline/L3 ABBA.
[CmdletBinding()]
param([string]$Model='qwen3.5:4b-q4_K_M',[ValidateRange(2,3)][int]$Repetitions=2)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Invoke-L3Live2Offline.ps1') -Model $Model

$query='What archival catalog token was noted for RETRO_ARCHIVE?'
$db=Open-LfoL3ReadOnly $script:L3Path
try{
  $turn3=@(Invoke-LfoSqliteQuery $db "SELECT id FROM l3_items WHERE scope_id='conversation:1' AND source_layer='L0' AND source_ref='turn:3';")
  if($turn3.Count -ne 1){throw 'topic_l0 turn:3 item missing.'}
  $locator=@(Get-LfoL3L0Locators $db @([int64]$turn3[0].id))
  if($locator.Count -ne 1){throw 'topic_l0 L0 locator missing before live smoke.'}
} finally {
  Close-LfoSqliteDatabase $db
}

try{
  $ollama=Invoke-RestMethod -Uri ([string]$script:Config.BaseUri + '/api/version') -Method Get -TimeoutSec 3
}catch{
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

function Invoke-TopicL0Variant([string]$Variant,[int]$Repetition){
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
  [pscustomobject]@{
    Variant=$Variant;Repetition=$Repetition
    Correct=($route -ceq 'LOCAL' -and $answer -match 'HALCYON-77')
    Route=$route;Answer=$answer
    PromptTokens=[int]$response.prompt_eval_count;VisibleChars=$visible
    L0Items=[int]$stats.l0_old_data_items;L2Items=[int]$stats.l2_read_items
    L3Used=[bool]$stats.l3_used;L3Status=[string]$stats.l3_status
    AssemblyS=[double]$stats.assembly_seconds;WallS=[Math]::Round($sw.Elapsed.TotalSeconds,4)
  }
}

$samples=@()
for($rep=1;$rep -le $Repetitions;$rep++){
  $order=if(($rep%2)-eq 1){@('baseline','l3')}else{@('l3','baseline')}
  foreach($variant in $order){
    $x=Invoke-TopicL0Variant $variant $rep
    $samples+=$x
    Write-Host ("TOPIC_L0 {0} rep {1}: prompt={2}; visible={3}; L0={4}; l3={5}/{6}; correct={7}" -f $variant,$rep,$x.PromptTokens,$x.VisibleChars,$x.L0Items,$x.L3Used,$x.L3Status,$x.Correct)
  }
}
if(@($samples|Where-Object{-not $_.Correct}).Count -gt 0){throw 'Focused topic_l0 correctness failed.'}
$b=@($samples|Where-Object Variant -ceq 'baseline'|Sort-Object Repetition)
$l=@($samples|Where-Object Variant -ceq 'l3'|Sort-Object Repetition)
for($i=0;$i -lt $Repetitions;$i++){
  if($b[$i].PromptTokens -ne $l[$i].PromptTokens -or $b[$i].VisibleChars -ne $l[$i].VisibleChars){
    throw ("topic_l0 prompt parity failed in repetition {0}." -f ($i+1))
  }
  if(-not $l[$i].L3Used -or $l[$i].L3Status -cne 'ok' -or $l[$i].L0Items -ne 1 -or $l[$i].L2Items -ne 0){
    throw ("topic_l0 L3 retrieval shape failed in repetition {0}." -f ($i+1))
  }
}
$samples|Format-Table Variant,Repetition,Correct,PromptTokens,VisibleChars,L0Items,L3Used,L3Status,AssemblyS,WallS,Answer -AutoSize
[pscustomobject]@{
  PASS=$true;Commit=$head;OllamaVersion=[string]$ollama.version;Model=$Model
  ModelCalls=$samples.Count;ExactPromptParity=$true;L0LocatorPresent=$true
  ProductionMemoryTouched=$false;TempFixture=$root
}|Format-List
