# L4-D1 bounded offline local-model detector evaluator.
# Transport/protocol errors are hard experiment failures. Predictions are never written to R1.

function Get-LfoModelDetectorFormat {
    param([string[]]$AllowedLabels)
    return @{
        type='object'
        properties=@{
            results=@{
                type='array'
                items=@{
                    type='object'
                    properties=@{
                        id=@{type='string'}
                        labels=@{
                            type='array'
                            items=@{type='string';enum=@($AllowedLabels)}
                        }
                    }
                    required=@('id','labels')
                    additionalProperties=$false
                }
            }
        }
        required=@('results')
        additionalProperties=$false
    }
}

function Get-LfoModelDetectorSystemPrompt {
    return @'
You are an offline epistemic-annotation classifier used only for a bounded research evaluation.

Classify only observable TEXT-LOCAL signals in the supplied stage text. Do not infer a user trait, diagnosis, truth, intent, or hidden state. Do not use world knowledge to decide whether a claim is actually justified. Use only the wording visible in each case.

Allowed labels:
FRAMING — evaluative/loaded wording presents a judgement or perspective as already settled.
PRESUPPOSITION — a question/statement embeds an unestablished proposition or cause as given.
ASYMMETRIC_EVIDENCE_REQUEST — explicitly asks to select/support one side while excluding, omitting, ignoring, or refusing materially relevant counterevidence.
OVERCONFIDENCE — explicit text-local certainty language such as definite/certain/no-doubt/exclusive causal certainty.
UNCERTAINTY_SUPPRESSION — explicitly presents evidence/conclusion as proof, conclusive, settled, or denies uncertainty.

Important boundaries:
- Technical status words such as "definitively frozen", "PASS", "only files", or "definitely need a backup" are not epistemic-risk labels merely because they contain certainty/selection words.
- A sentence that CHALLENGES a presupposition/framing is not itself PRESUPPOSITION or FRAMING.
- Negated phrases such as "not conclusive" are not UNCERTAINTY_SUPPRESSION.
- Do not predict relational labels such as sycophantic reinforcement, counterevidence ignored/introduced, or bias challenged from isolated text.
- Return [] when none of the five allowed text-local labels is directly supported.
- For each supplied id return exactly one result object with that same id.
- Return only the requested JSON object and no prose.
'@
}

function ConvertFrom-LfoDetectorJson {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][object[]]$Cases,
        [Parameter(Mandatory)][string[]]$AllowedLabels
    )
    if([string]::IsNullOrWhiteSpace($Content)){throw 'Model detector returned empty content.'}
    try{$obj=$Content|ConvertFrom-Json -ErrorAction Stop}catch{throw ('Model detector JSON parse failure: '+$_.Exception.Message+' | content='+$Content.Substring(0,[Math]::Min(600,$Content.Length)))}
    $rows=@($obj.results)
    if($rows.Count -ne $Cases.Count){throw ('Model detector result count mismatch: '+$rows.Count+' vs '+$Cases.Count+' | content='+$Content.Substring(0,[Math]::Min(600,$Content.Length)))}
    $expectedIds=@($Cases|ForEach-Object{[string]$_.id}|Sort-Object)
    $actualIds=@($rows|ForEach-Object{[string]$_.id}|Sort-Object)
    if(($expectedIds -join '|') -cne ($actualIds -join '|')){throw ('Model detector ids do not exactly match batch ids. expected='+($expectedIds -join ',')+' actual='+($actualIds -join ','))}
    if(@($actualIds|Group-Object|Where-Object Count -ne 1).Count){throw 'Model detector returned duplicate ids.'}
    $out=@()
    foreach($r in $rows){
        $labs=@($r.labels|ForEach-Object{[string]$_}|Sort-Object -Unique)
        if(@($labs|Where-Object{$_ -notin $AllowedLabels}).Count){throw ('Model detector returned out-of-contract label for '+[string]$r.id)}
        $out += [pscustomobject]@{id=[string]$r.id;labels=$labs}
    }
    return @($out)
}

function Invoke-LfoDetectorHttp {
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][hashtable]$BodyObject,
        [ValidateRange(1,600)][int]$TimeoutSec=300
    )
    $body=$BodyObject|ConvertTo-Json -Depth 20 -Compress
    try{
        return Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/')+'/api/chat') -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec $TimeoutSec
    }catch{
        $detail=$_.Exception.Message
        try{
            if($_.ErrorDetails.Message){$detail += ' | '+[string]$_.ErrorDetails.Message}
        }catch{}
        throw ('Ollama /api/chat failure: '+$detail)
    }
}

function Invoke-LfoEpistemicModelDetectorBatch {
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][object[]]$Cases,
        [Parameter(Mandatory)][string[]]$AllowedLabels,
        [ValidateSet('schema','json')][string]$Protocol='schema',
        [ValidateRange(1,600)][int]$TimeoutSec=300
    )
    $publicCases=@($Cases|ForEach-Object{[ordered]@{id=[string]$_.id;actor=[string]$_.actor;text=[string]$_.text}})
    $userText="Classify these cases:`n"+($publicCases|ConvertTo-Json -Depth 6 -Compress)
    $bodyObj=@{
        model=$Model
        messages=@(
            @{role='system';content=(Get-LfoModelDetectorSystemPrompt)}
            @{role='user';content=$userText}
        )
        think=$false
        stream=$false
        keep_alive='5m'
        options=@{temperature=0.0;num_predict=768}
    }
    if($Protocol -ceq 'schema'){$bodyObj.format=Get-LfoModelDetectorFormat $AllowedLabels}else{$bodyObj.format='json'}
    $sw=[Diagnostics.Stopwatch]::StartNew()
    try{$resp=Invoke-LfoDetectorHttp -BaseUri $BaseUri -BodyObject $bodyObj -TimeoutSec $TimeoutSec}finally{$sw.Stop()}
    $parsed=@(ConvertFrom-LfoDetectorJson -Content ([string]$resp.message.content) -Cases $Cases -AllowedLabels $AllowedLabels)
    return [pscustomobject]@{
        Results=$parsed
        LatencySeconds=$sw.Elapsed.TotalSeconds
        EvalCount=[int]$resp.eval_count
        PromptEvalCount=[int]$resp.prompt_eval_count
        DoneReason=[string]$resp.done_reason
        Protocol=$Protocol
    }
}

function Test-LfoEpistemicModelDetectorProtocol {
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][object[]]$Cases,
        [Parameter(Mandatory)][string[]]$AllowedLabels
    )
    $errors=@()
    foreach($p in @('schema','json')){
        try{
            $r=Invoke-LfoEpistemicModelDetectorBatch -BaseUri $BaseUri -Model $Model -Cases $Cases -AllowedLabels $AllowedLabels -Protocol $p
            return [pscustomobject]@{Protocol=$p;Probe=$r;Errors=$errors}
        }catch{
            $errors += ($p+': '+$_.Exception.Message)
        }
    }
    throw ("No usable D1 detector protocol. "+($errors -join ' || '))
}

function Measure-LfoModelDetectorPredictions {
    param([object]$Benchmark,[hashtable]$Predictions)
    $labels=@($Benchmark.text_local_labels)
    $per=@{};foreach($l in $labels){$per[$l]=[ordered]@{TP=0;FP=0;FN=0;TN=0}}
    $tp=0;$fp=0;$fn=0;$tn=0;$exact=0;$scored=0;$predictedCases=0
    $relational=0;$relationalAbstained=0;$rows=@()
    foreach($case in @($Benchmark.cases)){
        $id=[string]$case.id
        if(-not $Predictions.ContainsKey($id)){throw ('Missing model prediction for '+$id)}
        $pred=@($Predictions[$id]);$expected=@($case.expected_labels)
        if([string]$case.scope -ceq 'relational'){
            $relational++;if($pred.Count -eq 0){$relationalAbstained++}
            $rows += [pscustomobject]@{id=$id;scope='relational';expected=$expected;predicted=$pred;exact=$null}
            continue
        }
        $scored++;if($pred.Count){$predictedCases++}
        $pKey=(@($pred|Sort-Object -Unique)-join '|');$eKey=(@($expected|Sort-Object -Unique)-join '|')
        $isExact=($pKey -ceq $eKey);if($isExact){$exact++}
        foreach($l in $labels){
            $e=($expected -contains $l);$p=($pred -contains $l)
            if($e -and $p){$tp++;$per[$l].TP++}
            elseif(-not $e -and $p){$fp++;$per[$l].FP++}
            elseif($e -and -not $p){$fn++;$per[$l].FN++}
            else{$tn++;$per[$l].TN++}
        }
        $rows += [pscustomobject]@{id=$id;scope='text_local';expected=$expected;predicted=$pred;exact=$isExact}
    }
    $precision=Get-LfoDetectorRatio $tp ($tp+$fp);$recall=Get-LfoDetectorRatio $tp ($tp+$fn)
    $f1=if(($precision+$recall)-eq 0){0.0}else{2.0*$precision*$recall/($precision+$recall)}
    $classRows=@();$macro=0.0
    foreach($l in $labels){
        $m=$per[$l];$p=Get-LfoDetectorRatio $m.TP ($m.TP+$m.FP);$r=Get-LfoDetectorRatio $m.TP ($m.TP+$m.FN)
        $cf1=if(($p+$r)-eq 0){0.0}else{2.0*$p*$r/($p+$r)};$macro+=$cf1
        $classRows += [pscustomobject]@{label=$l;TP=$m.TP;FP=$m.FP;FN=$m.FN;TN=$m.TN;precision=$p;recall=$r;f1=$cf1}
    }
    [pscustomobject]@{
        ScoredCases=$scored;RelationalCases=$relational;RelationalAbstained=$relationalAbstained
        TP=$tp;FP=$fp;FN=$fn;TN=$tn;MicroPrecision=$precision;MicroRecall=$recall;MicroF1=$f1;MacroF1=($macro/$labels.Count)
        ExactSetAccuracy=(Get-LfoDetectorRatio $exact $scored);Coverage=(Get-LfoDetectorRatio $predictedCases $scored)
        Abstention=(1.0-(Get-LfoDetectorRatio $predictedCases $scored));PerClass=$classRows;Cases=$rows
    }
}

function Invoke-LfoEpistemicModelDetectorBenchmark {
    param(
        [Parameter(Mandatory)][string]$BaseUri,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$BenchmarkPath,
        [Parameter(Mandatory)][ValidateSet('schema','json')][string]$Protocol,
        [ValidateRange(1,20)][int]$BatchSize=10,
        [ValidateRange(1,600)][int]$TimeoutSec=300
    )
    $bench=Get-Content -LiteralPath $BenchmarkPath -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
    if($bench.schema -cne 'lfo-l4-d1-detector-benchmark-v1'){throw 'Unsupported D1 benchmark schema.'}
    $labels=@($bench.text_local_labels);$pred=@{};$calls=0;$latency=0.0;$evalTokens=0;$promptTokens=0
    $cases=@($bench.cases)
    for($offset=0;$offset -lt $cases.Count;$offset+=$BatchSize){
        $last=[Math]::Min($offset+$BatchSize-1,$cases.Count-1);$batch=@($cases[$offset..$last]);$calls++
        try{
            $r=Invoke-LfoEpistemicModelDetectorBatch -BaseUri $BaseUri -Model $Model -Cases $batch -AllowedLabels $labels -Protocol $Protocol -TimeoutSec $TimeoutSec
        }catch{
            throw ('D1 model batch '+$calls+' failed for ids '+(@($batch.id)-join ',')+': '+$_.Exception.Message)
        }
        $latency+=[double]$r.LatencySeconds;$evalTokens+=[int]$r.EvalCount;$promptTokens+=[int]$r.PromptEvalCount
        foreach($x in @($r.Results)){$pred[[string]$x.id]=@($x.labels)}
    }
    $m=Measure-LfoModelDetectorPredictions $bench $pred
    $m|Add-Member NoteProperty Schema 'lfo-l4-d1-model-detector-result-v2'
    $m|Add-Member NoteProperty Model $Model
    $m|Add-Member NoteProperty Protocol $Protocol
    $m|Add-Member NoteProperty ModelCalls $calls
    $m|Add-Member NoteProperty TotalLatencySeconds $latency
    $m|Add-Member NoteProperty EvalTokens $evalTokens
    $m|Add-Member NoteProperty PromptEvalTokens $promptTokens
    $m|Add-Member NoteProperty Interpretation 'Offline agreement with explicit benchmark labels only; not truth, calibration, or ecological validity.'
    return $m
}

function Compare-LfoModelDetectorRuns {
    param([object]$A,[object]$B)
    $map=@{};foreach($x in @($B.Cases)){$map[[string]$x.id]=(@($x.predicted|Sort-Object -Unique)-join '|')}
    $same=0;$total=0
    foreach($x in @($A.Cases)){
        $id=[string]$x.id;if(-not $map.ContainsKey($id)){continue};$total++
        if((@($x.predicted|Sort-Object -Unique)-join '|') -ceq $map[$id]){$same++}
    }
    [pscustomobject]@{ComparedCases=$total;IdenticalCases=$same;Stability=(Get-LfoDetectorRatio $same $total)}
}
