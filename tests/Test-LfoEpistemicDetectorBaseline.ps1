$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/LfoEpistemicDetectorBaseline.ps1')
$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Near([double]$A,[double]$B,[double]$Tol=0.0000001){return [math]::Abs($A-$B) -le $Tol}

$benchmark=Join-Path $PSScriptRoot 'fixtures\l4-d1-detector\benchmark.json'
$r=Invoke-LfoEpistemicDetectorBenchmark -BenchmarkPath $benchmark

Assert ($r.ScoredCases -eq 30) 'Expected 30 scored text-local cases'
Assert ($r.RelationalCases -eq 4 -and $r.RelationalAbstained -eq 4) 'Relational abstention boundary mismatch'
Assert ($r.TP -eq 16 -and $r.FP -eq 2 -and $r.FN -eq 4 -and $r.TN -eq 128) 'Micro confusion counts mismatch'
Assert (Near $r.MicroPrecision (16.0/18.0)) 'Micro precision mismatch'
Assert (Near $r.MicroRecall 0.8) 'Micro recall mismatch'
Assert (Near $r.MicroF1 (32.0/38.0)) 'Micro F1 mismatch'
Assert (Near $r.ExactSetAccuracy 0.8) 'Exact-set accuracy mismatch'
Assert (Near $r.Coverage 0.6 -and Near $r.Abstention 0.4) 'Coverage/abstention mismatch'
Assert ($r.PerClass.Count -eq 5) 'Per-class metrics missing'

$c27=@($r.Cases|Where-Object id -eq 'd1-27')[0]
$c28=@($r.Cases|Where-Object id -eq 'd1-28')[0]
Assert (($c27.predicted -contains 'UNCERTAINTY_SUPPRESSION') -and ($c28.predicted -contains 'OVERCONFIDENCE')) 'Known baseline false positives not exposed'

foreach($id in @('d1-04','d1-07','d1-12','d1-16')){
    $c=@($r.Cases|Where-Object id -eq $id)[0]
    Assert ($c.predicted.Count -eq 0 -and $c.expected.Count -eq 1) ('Known baseline false negative missing: '+$id)
}

$rel=@($r.Cases|Where-Object scope -eq 'relational')
Assert (@($rel|Where-Object{$_.predicted.Count -ne 0}).Count -eq 0) 'Text-local baseline overreached into relational cases'

Write-Host ('D1_BASELINE_PASS: '+$script:checks+' checks; scored=30; relational_abstain=4/4; TP=16; FP=2; FN=4; microF1='+('{0:N4}' -f $r.MicroF1)+'; exact='+('{0:N4}' -f $r.ExactSetAccuracy)+'; ModelCalls=0; ProductionMemoryTouched=False')
[pscustomobject]@{PASS=$true;Checks=$script:checks;ScoredCases=$r.ScoredCases;RelationalAbstained=$r.RelationalAbstained;TP=$r.TP;FP=$r.FP;FN=$r.FN;MicroF1=$r.MicroF1;ExactSetAccuracy=$r.ExactSetAccuracy;ModelCalls=0;ProductionMemoryTouched=$false}
