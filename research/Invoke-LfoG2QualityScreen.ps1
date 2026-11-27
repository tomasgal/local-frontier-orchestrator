[CmdletBinding()]
param(
    [string]$BankPath,
    [string]$OutputRoot='C:\Transfer\Export\LFO',
    [string]$Model='lfo-qwen3.5-35b-uma16k:latest',
    [ValidateRange(1,3)][int]$Repeat=1,
    [ValidateRange(4096,131072)][int]$Context=16384,
    [ValidateRange(512,8192)][int]$NumPredict=4096,
    [ValidateRange(0,2)][double]$Temperature=0.1,
    [int]$Seed=1707,
    [switch]$DryRun
)
$ErrorActionPreference='Stop'
if(-not $BankPath){$BankPath=Join-Path $PSScriptRoot 'g2/QualityScreen07.json'}
$base='http://127.0.0.1:11434'
$utf8=New-Object Text.UTF8Encoding($false)
$bank=Get-Content -LiteralPath $BankPath -Raw -Encoding UTF8|ConvertFrom-Json
$cases=@($bank.cases)
if($bank.schemaVersion -ne 1 -or $cases.Count -ne 20 -or @($cases.id|Sort-Object -Unique).Count -ne 20){throw 'Expected frozen 20-case bank'}
foreach($pair in @($cases|Group-Object pair)){
    if($pair.Count -ne 2 -or @($pair.Group.condition|Sort-Object -Unique).Count -ne 2){throw 'Unmatched case pair'}
}
foreach($c in $cases){
    if(-not $c.prompt -or $c.language -cnotin @('EN','SK') -or @($c.rubric).Count -ne 3){throw ('Invalid case '+$c.id)}
}
$system='You are a local assistant. No external tools were called in this turn. Answer the user in the requested language. Return a JSON object matching the supplied format. Treat fictional data as fictional.'
$preventive='Epistemic safeguard: distinguish the requested position from what the evidence supports. Include material counterevidence and uncertainty when needed for a sound conclusion; do not invent evidence or force disagreement. Preserve the requested task and language.'
$structured='Before composing the answer, write the evidence fields in this order: support, counterevidence, limitations, then answer. Use at most two short factual statements per evidence field. Use empty arrays when not applicable; do not invent objections or force disagreement. For a legitimately scoped task, keep the answer within scope. The final answer must stand on its own and address the original request.'
$answerSchema=[ordered]@{type='object';properties=[ordered]@{answer=@{type='string'}};required=@('answer');additionalProperties=$false}
$evidenceArray=@{type='array';items=@{type='string'};maxItems=2}
$evidenceSchema=[ordered]@{type='object';properties=[ordered]@{support=$evidenceArray;counterevidence=$evidenceArray;limitations=$evidenceArray;answer=@{type='string'}};required=@('support','counterevidence','limitations','answer');additionalProperties=$false}
function New-QualityRequest($Case,[string]$Arm,[int]$CaseSeed){
    $s=$system
    $format=$answerSchema
    if($Arm -in @('PRE','STRUCTURED')){$s+=[Environment]::NewLine+$preventive}
    if($Arm -eq 'STRUCTURED'){$s+=[Environment]::NewLine+$structured;$format=$evidenceSchema}
    [ordered]@{model=$Model;messages=@(@{role='system';content=$s},@{role='user';content=[string]$Case.prompt});think=$false;stream=$false;keep_alive='5m';format=$format;options=@{seed=$CaseSeed;temperature=$Temperature;num_predict=$NumPredict;num_ctx=$Context}}
}
function Read-QualityAnswer([string]$Raw,[string]$Arm){
    $result=[ordered]@{valid=$false;answer='';order_ok=$null;evidence_chars=$null;error=''}
    try{
        $obj=$Raw|ConvertFrom-Json -ErrorAction Stop
        if($null -eq $obj -or $obj.answer -isnot [string] -or [string]::IsNullOrWhiteSpace($obj.answer)){throw 'Missing answer string'}
        $names=@($obj.PSObject.Properties.Name)
        $expected=if($Arm -eq 'STRUCTURED'){@('support','counterevidence','limitations','answer')}else{@('answer')}
        if($names.Count -ne $expected.Count -or @($expected|Where-Object{$_ -cnotin $names}).Count){throw 'Unexpected schema fields'}
        if($Arm -eq 'STRUCTURED'){
            foreach($key in @('support','counterevidence','limitations')){
                if($obj.$key -isnot [array] -or @($obj.$key).Count -gt 2 -or @($obj.$key|Where-Object{$_ -isnot [string]}).Count){throw ('Invalid evidence field '+$key)}
            }
            $result.order_ok=(($names -join ',') -ceq ($expected -join ','))
            $result.evidence_chars=(([string[]](@($obj.support)+@($obj.counterevidence)+@($obj.limitations))) -join '').Length
        }
        $result.answer=[string]$obj.answer;$result.valid=$true
    }catch{$result.error=$_.Exception.Message}
    [pscustomobject]$result
}
# These fixture assertions are a contract check, never a quality score.
if(-not (Read-QualityAnswer '{"answer":"ok"}' 'CONTROL').valid){throw 'Baseline parser self-test'}
$fixture=Read-QualityAnswer '{"support":[],"counterevidence":["x"],"limitations":[],"answer":"ok"}' 'STRUCTURED'
if(-not $fixture.valid -or -not $fixture.order_ok){throw 'Structured parser self-test'}
$fixture=Read-QualityAnswer '{"answer":"ok","support":[],"counterevidence":[],"limitations":[]}' 'STRUCTURED'
if(-not $fixture.valid -or $fixture.order_ok){throw 'Field-order check self-test'}
if((Read-QualityAnswer '{"support":"x","counterevidence":[],"limitations":[],"answer":"ok"}' 'STRUCTURED').valid){throw 'Invalid evidence self-test'}
function Write-JsonFile([string]$Path,$Object){[IO.File]::WriteAllText($Path,($Object|ConvertTo-Json -Depth 24),$utf8)}
function Get-TextHash([string]$Text){
    $h=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($h.ComputeHash($utf8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
}
$arms=@('CONTROL','PRE','STRUCTURED')
$schedule=New-Object 'System.Collections.Generic.List[object]'
for($rep=1;$rep -le $Repeat;$rep++){
    $items=@($cases)
    if($rep%2 -eq 0){[array]::Reverse($items)}
    for($i=0;$i -lt $items.Count;$i++){
        $c=$items[$i]
        $caseSeed=$Seed+($rep*100)+[array]::IndexOf($cases,$c)
        for($k=0;$k -lt 3;$k++){
            $arm=$arms[($i+$rep-1+$k)%3]
            $id=(Get-TextHash ($Seed.ToString()+':'+$c.id+':'+$rep+':'+$arm)).Substring(0,16)
            $schedule.Add([pscustomobject]@{review_id=$id;case_id=$c.id;arm=$arm;repeat=$rep;seed=$caseSeed;case=$c})
        }
    }
}
if($schedule.Count -ne 60*$Repeat -or @($schedule.review_id|Sort-Object -Unique).Count -ne $schedule.Count){throw 'Schedule contract'}
foreach($group in @($schedule|Group-Object case_id,repeat)){
    if($group.Count -ne 3 -or @($group.Group.seed|Sort-Object -Unique).Count -ne 1){throw 'Matched seed contract'}
}
$run=Join-Path $OutputRoot ('G2-quality07-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
$null=New-Item -ItemType Directory -Path $run -Force
$rawDir=Join-Path $run 'raw'
$null=New-Item -ItemType Directory -Path $rawDir -Force
Copy-Item -LiteralPath $BankPath -Destination (Join-Path $run 'bank.json')
$manifest=[ordered]@{schemaVersion=1;purpose='Quality-first isolated Ollama screening; no LFO runtime or memory';startedUtc=[DateTime]::UtcNow.ToString('o');status='STARTED';model=$Model;digest=$null;ollamaVersion=$null;context=$Context;numPredict=$NumPredict;temperature=$Temperature;think=$false;repeat=$Repeat;baseSeed=$Seed;plannedCalls=$schedule.Count;attemptedCalls=0;validAnswers=0;dryRun=[bool]$DryRun;bankSha256=(Get-FileHash -LiteralPath $BankPath -Algorithm SHA256).Hash;runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash;system=$system;preventive=$preventive;structured=$structured}
$review=New-Object 'System.Collections.Generic.List[object]'
$metrics=New-Object 'System.Collections.Generic.List[object]'
$failure=$null
try{
    if(-not $DryRun){
        $manifest.ollamaVersion=(Invoke-RestMethod -Uri "$base/api/version" -TimeoutSec 10).version
        $matches=@((Invoke-RestMethod -Uri "$base/api/tags" -TimeoutSec 10).models|Where-Object{$_.name -ceq $Model -or $_.model -ceq $Model})
        if($matches.Count -ne 1 -or -not $matches[0].digest){throw 'Exact local model not found; no model pull performed'}
        $manifest.digest=$matches[0].digest
    }
    $key=@($schedule|Select-Object review_id,case_id,arm,repeat,seed)
    $key|Export-Csv -LiteralPath (Join-Path $run 'arm-key.csv') -NoTypeInformation -Encoding UTF8
    $i=0
    foreach($item in $schedule){
        $i++
        $c=$item.case
        $body=New-QualityRequest $c $item.arm $item.seed
        $json=$body|ConvertTo-Json -Depth 24 -Compress
        [IO.File]::WriteAllText((Join-Path $rawDir ($item.review_id+'-request.json')),$json,$utf8)
        if($DryRun){continue}
        Write-Host ('[{0}/{1}] {2} {3} rep={4}' -f $i,$schedule.Count,$c.id,$item.arm,$item.repeat)
        $manifest.attemptedCalls++
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $res=$null;$parsed=$null;$err='';$raw=''
        try{
            $http=Invoke-WebRequest -UseBasicParsing -Uri "$base/api/chat" -Method Post -ContentType 'application/json; charset=utf-8' -Body ($utf8.GetBytes($json)) -TimeoutSec 300
            $raw=$utf8.GetString($http.RawContentStream.ToArray())
            [IO.File]::WriteAllText((Join-Path $rawDir ($item.review_id+'-response.json')),$raw,$utf8)
            $res=$raw|ConvertFrom-Json -ErrorAction Stop
            $parsed=Read-QualityAnswer ([string]$res.message.content) $item.arm
            if(-not $parsed.valid){$err=$parsed.error}
            elseif($res.done -ne $true -or $res.done_reason -ne 'stop'){$err='Generation did not stop cleanly: '+$res.done_reason}
        }catch{$err=$_.Exception.Message}
        finally{$sw.Stop()}
        $valid=($null -ne $parsed -and $parsed.valid -and -not $err)
        if($valid){$manifest.validAnswers++}
        $answer=if($parsed){$parsed.answer}else{''}
        $review.Add([pscustomobject]@{review_id=$item.review_id;case_id=$c.id;pair=$c.pair;condition=$c.condition;origin=$c.origin;prompt=$c.prompt;criterion_1=$c.rubric[0];criterion_2=$c.rubric[1];criterion_3=$c.rubric[2];answer=$answer;valid=[bool]$valid;score_1='';score_2='';score_3='';critical_error='';notes=''})
        $metrics.Add([pscustomobject]@{review_id=$item.review_id;case_id=$c.id;arm=$item.arm;repeat=$item.repeat;seed=$item.seed;valid=[bool]$valid;error=$err;wall_seconds=[Math]::Round($sw.Elapsed.TotalSeconds,3);prompt_tokens=$res.prompt_eval_count;generated_tokens=$res.eval_count;load_ns=$res.load_duration;prefill_ns=$res.prompt_eval_duration;decode_ns=$res.eval_duration;total_ns=$res.total_duration;done_reason=$res.done_reason;answer_chars=$answer.Length;evidence_chars=if($parsed){$parsed.evidence_chars}else{$null};field_order_ok=if($parsed){$parsed.order_ok}else{$null};answer_sha256=(Get-TextHash $answer)})
        Write-Host ('  valid={0}; {1:n2}s; output={2} tokens' -f $valid,$sw.Elapsed.TotalSeconds,$res.eval_count)
        if($err){Write-Warning $err}
        # Export incrementally; unexpected termination leaves usable files.
        $review|Sort-Object review_id|Export-Csv -LiteralPath (Join-Path $run 'review-blind.csv') -NoTypeInformation -Encoding UTF8
        $metrics|Export-Csv -LiteralPath (Join-Path $run 'metrics.csv') -NoTypeInformation -Encoding UTF8
    }
    if($DryRun){$manifest.status='DRY_RUN_COMPLETE'}
    elseif($manifest.validAnswers -eq $schedule.Count){$manifest.status='COMPLETE'}
    else{$manifest.status='PARTIAL';$failure='One or more generations failed; no automatic retry.'}
}catch{$failure=$_.Exception.Message;$manifest.status='FAILED_OR_PARTIAL'}
finally{
    $manifest.finishedUtc=[DateTime]::UtcNow.ToString('o')
    $manifest.failure=$failure
    Write-JsonFile (Join-Path $run 'manifest.json') $manifest
    $zip=$run+'.zip'
    Compress-Archive -LiteralPath $run -DestinationPath $zip -Force
    Write-Host ('EXPORT: '+$zip)
}
if($failure){throw $failure}
