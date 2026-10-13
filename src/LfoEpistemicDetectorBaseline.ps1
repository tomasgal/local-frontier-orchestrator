# L4-D1 deterministic text-local detector baseline.
# This is an offline experiment baseline, not a production detector.
# It emits rule evidence, not calibrated confidence/probability.

function New-LfoDetectorHit {
    param([string]$ObservationType,[string]$RuleId)
    [pscustomobject]@{
        observation_type=$ObservationType
        rule_id=$RuleId
        evidence_strength='rule-match'
    }
}

function Invoke-LfoEpistemicDetectorBaseline {
    param(
        [Parameter(Mandatory)][ValidateSet('USER','LOCAL','FRONTIER','FINAL')][string]$Actor,
        [Parameter(Mandatory)][ValidateLength(1,4096)][string]$Text
    )
    $t=($Text -replace '\s+',' ').Trim().ToLowerInvariant()
    $hits=New-Object System.Collections.ArrayList

    if($t -match '\b(obviously|clearly|inherently|self-evidently)\b.{0,40}\b(harmful|irresponsible|reckless|disastrous|wrong|good|bad)\b'){
        [void]$hits.Add((New-LfoDetectorHit 'FRAMING' 'framing-evaluative-adverb-v1'))
    }

    if($t -match '\bwhy\b.{0,80}\bbecause\b' -or $t -match '\bwhen did\b.{0,60}\b(harm|fail|cause|start)\w*'){
        [void]$hits.Add((New-LfoDetectorHit 'PRESUPPOSITION' 'presupposed-cause-or-state-v1'))
    }

    if($t -match '\b(only|just)\b.{0,50}\b(evidence|arguments?|reasons?)\b.{0,30}\b(support|supporting|favor|positive)' -or
       $t -match '\b(leave out|omit|exclude|ignore)\b.{0,50}\b(counter\w*|oppos\w*|against|negative|objections?)\b'){
        [void]$hits.Add((New-LfoDetectorHit 'ASYMMETRIC_EVIDENCE_REQUEST' 'asymmetric-evidence-selection-v1'))
    }

    if($t -match '\b(definitely|certainly|undoubtedly|guaranteed)\b|\b(no doubt|without doubt)\b'){
        [void]$hits.Add((New-LfoDetectorHit 'OVERCONFIDENCE' 'epistemic-certainty-lexeme-v1'))
    }

    $negated=($t -match '\b(not conclusive|no proof|does not prove|doesn''t prove)\b')
    if(-not $negated -and ($t -match '\b(proves?|proof|conclusive|settled)\b|\bno uncertainty\b')){
        [void]$hits.Add((New-LfoDetectorHit 'UNCERTAINTY_SUPPRESSION' 'certainty-suppression-lexeme-v1'))
    }

    return @($hits|Sort-Object observation_type,rule_id)
}

function Get-LfoDetectorRatio {
    param([int]$Numerator,[int]$Denominator)
    if($Denominator -eq 0){return 0.0}
    return [double]$Numerator/[double]$Denominator
}

function Invoke-LfoEpistemicDetectorBenchmark {
    param([Parameter(Mandatory)][string]$BenchmarkPath)
    $bench=Get-Content -LiteralPath $BenchmarkPath -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
    if($bench.schema -cne 'lfo-l4-d1-detector-benchmark-v1'){throw 'Unsupported D1 benchmark schema.'}
    $labels=@($bench.text_local_labels)
    $per=@{}
    foreach($l in $labels){$per[$l]=[ordered]@{TP=0;FP=0;FN=0;TN=0}}

    $tp=0;$fp=0;$fn=0;$tn=0;$exact=0;$scored=0;$predictedCases=0
    $relational=0;$relationalAbstained=0
    $rows=@()

    foreach($case in @($bench.cases)){
        $pred=@(Invoke-LfoEpistemicDetectorBaseline -Actor ([string]$case.actor) -Text ([string]$case.text)|ForEach-Object observation_type)
        $expected=@($case.expected_labels)
        if([string]$case.scope -ceq 'relational'){
            $relational++
            if($pred.Count -eq 0){$relationalAbstained++}
            $rows += [pscustomobject]@{id=$case.id;scope='relational';expected=$expected;predicted=$pred;exact=$null}
            continue
        }

        $scored++
        if($pred.Count){$predictedCases++}
        $pKey=(@($pred|Sort-Object -Unique) -join '|')
        $eKey=(@($expected|Sort-Object -Unique) -join '|')
        $isExact=($pKey -ceq $eKey)
        if($isExact){$exact++}

        foreach($l in $labels){
            $e=($expected -contains $l);$p=($pred -contains $l)
            if($e -and $p){$tp++;$per[$l].TP++}
            elseif(-not $e -and $p){$fp++;$per[$l].FP++}
            elseif($e -and -not $p){$fn++;$per[$l].FN++}
            else{$tn++;$per[$l].TN++}
        }
        $rows += [pscustomobject]@{id=$case.id;scope='text_local';expected=$expected;predicted=$pred;exact=$isExact}
    }

    $precision=Get-LfoDetectorRatio $tp ($tp+$fp)
    $recall=Get-LfoDetectorRatio $tp ($tp+$fn)
    $f1=if(($precision+$recall)-eq 0){0.0}else{2.0*$precision*$recall/($precision+$recall)}
    $classRows=@();$macroSum=0.0
    foreach($l in $labels){
        $m=$per[$l]
        $p=Get-LfoDetectorRatio $m.TP ($m.TP+$m.FP)
        $r=Get-LfoDetectorRatio $m.TP ($m.TP+$m.FN)
        $cf1=if(($p+$r)-eq 0){0.0}else{2.0*$p*$r/($p+$r)}
        $macroSum+=$cf1
        $classRows += [pscustomobject]@{label=$l;TP=$m.TP;FP=$m.FP;FN=$m.FN;TN=$m.TN;precision=$p;recall=$r;f1=$cf1}
    }

    [pscustomobject]@{
        Schema='lfo-l4-d1-detector-benchmark-result-v1'
        ScoredCases=$scored
        RelationalCases=$relational
        RelationalAbstained=$relationalAbstained
        TP=$tp;FP=$fp;FN=$fn;TN=$tn
        MicroPrecision=$precision
        MicroRecall=$recall
        MicroF1=$f1
        MacroF1=($macroSum/$labels.Count)
        ExactSetAccuracy=(Get-LfoDetectorRatio $exact $scored)
        Coverage=(Get-LfoDetectorRatio $predictedCases $scored)
        Abstention=(1.0-(Get-LfoDetectorRatio $predictedCases $scored))
        PerClass=$classRows
        Cases=$rows
        Interpretation='Synthetic held-out baseline only. Metrics describe agreement with fixture labels, not truth or ecological validity.'
    }
}
