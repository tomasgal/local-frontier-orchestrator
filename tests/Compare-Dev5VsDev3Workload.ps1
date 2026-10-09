# Read-only, OFFLINE comparison of independently validated TEMP-only runs.
# This script does not invoke Ollama, mutate data, or infer missing timings.
param(
    [Parameter(Mandatory=$true)][string]$Dev3Path,
    [Parameter(Mandatory=$true)][string]$Dev5Path,
    [string]$WeightsPath
)
$ErrorActionPreference='Stop'
function Read-LfoBenchmark([string]$Path,[string]$Variant) {
    $d=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if([string]$d.schema -ne 'lfo-dev5-vs-dev3-v1' -or [string]$d.variant -ne $Variant) { throw "Wrong schema/variant: $Path" }
    if(@($d.samples).Count -eq 0){throw "No measured samples in $Path"}
    foreach($sample in @($d.samples)){
        if([string]::IsNullOrWhiteSpace([string]$sample.case_id) -or [int]$sample.repetition -le 0 -or
           $null -eq $sample.answer_wall_s -or [double]$sample.answer_wall_s -le 0 -or
           $null -eq $sample.answer_correct -or $null -eq $sample.memory_correct -or
           $null -eq $sample.input_tokens -or $null -eq $sample.output_tokens -or
           [int]$sample.input_tokens -lt 0 -or [int]$sample.output_tokens -lt 0) {
            throw "Incomplete or invalid measured sample in $Path"
        }
        if(-not [bool]$sample.answer_correct -or -not [bool]$sample.memory_correct) {
            throw "Correctness failure; timing comparison cannot establish a valid net gain: $Path / $($sample.case_id)"
        }
    }
    return $d
}
function Get-LfoMedian([double[]]$Values){
    $sorted=@($Values|Sort-Object);$n=$sorted.Count
    if($n -eq 0){throw 'Cannot calculate median of empty data.'}
    if($n % 2 -eq 1){return [double]$sorted[[int][Math]::Floor($n/2)]}
    return ([double]$sorted[$n/2-1]+[double]$sorted[$n/2])/2
}
$a=Read-LfoBenchmark $Dev3Path 'dev3'
$b=Read-LfoBenchmark $Dev5Path 'dev5'
$dev3Pin='a34658b81742596520da844618b5bb39f3329279'
if([string]$a.environment.commit_sha -cne $dev3Pin -or
   [string]$b.environment.commit_sha -notmatch '^[0-9a-f]{40}
foreach($field in @('fixture_version','host_class','model_id','model_digest','ollama_version','num_ctx','think','warm_state','logging_mode')){
    if([string]$a.environment.$field -cne [string]$b.environment.$field -or
       [string]::IsNullOrWhiteSpace([string]$a.environment.$field)) {
        throw "Unmatched or missing environment field $field: cannot attribute dev5 delta."
    }
}
$required=@('plain-local','dense-write','correction','preference-only','scoped-read')
$paired=@()
foreach($caseId in $required){
    $aCase=@($a.samples|Where-Object{[string]$_.case_id -eq $caseId})
    $bCase=@($b.samples|Where-Object{[string]$_.case_id -eq $caseId})
    if($aCase.Count -eq 0 -or $aCase.Count -ne $bCase.Count){throw "Missing/unmatched scenario: $caseId"}
    $idsA=@($aCase|ForEach-Object{[int]$_.repetition}|Sort-Object)
    $idsB=@($bCase|ForEach-Object{[int]$_.repetition}|Sort-Object)
    if(($idsA|Select-Object -Unique).Count -ne $idsA.Count -or
       ($idsB|Select-Object -Unique).Count -ne $idsB.Count -or
       ($idsA -join ',') -cne ($idsB -join ',')) {throw "Unpaired/duplicated repetitions: $caseId"}
    $old=Get-LfoMedian ([double[]]@($aCase|ForEach-Object{[double]$_.answer_wall_s}))
    $new=Get-LfoMedian ([double[]]@($bCase|ForEach-Object{[double]$_.answer_wall_s}))
    $paired+= [pscustomobject]@{
        Case=$caseId;N=$aCase.Count;Dev3MedianS=[Math]::Round($old,3)
        Dev5MedianS=[Math]::Round($new,3)
        DeltaPct=[Math]::Round(100*($new-$old)/$old,2)
        TokensInDev3=([double](($aCase|Measure-Object input_tokens -Average).Average))
        TokensInDev5=([double](($bCase|Measure-Object input_tokens -Average).Average))
        TokensOutDev3=([double](($aCase|Measure-Object output_tokens -Average).Average))
        TokensOutDev5=([double](($bCase|Measure-Object output_tokens -Average).Average))
    }
}
# The five common semantic tasks must be comparable. New dev5-only mixed
# provenance functionality is reported separately, NEVER blended into speed.
$unknownA=@($a.samples|Where-Object{$_.case_id -notin $required})
$unknownB=@($b.samples|Where-Object{$_.case_id -notin $required})
if($unknownA.Count -gt 0 -or $unknownB.Count -gt 0){throw 'Unknown/noncomparable scenarios in primary workload.'}
$weighted=$false;$weights=@{};$profile='illustrative-equal-weight'
if(-not [string]::IsNullOrWhiteSpace($WeightsPath)){
    $profileObj=Get-Content -LiteralPath $WeightsPath -Raw -Encoding UTF8|ConvertFrom-Json
    if([string]$profileObj.schema -ne 'lfo-observed-workload-weights-v1' -or
       [string]::IsNullOrWhiteSpace([string]$profileObj.provenance)){throw 'Invalid/missing observed workload profile provenance.'}
    $sum=0.0
    foreach($id in $required){
        $v=$profileObj.weights.$id
        if($null -eq $v -or [double]$v -lt 0){throw "Missing/negative case weight: $id"}
        $weights[$id]=[double]$v;$sum+=[double]$v
    }
    if([Math]::Abs($sum-1.0) -gt 0.000001){throw "Weights must sum to 1.0, got $sum"}
    $weighted=$true;$profile=[string]$profileObj.provenance
} else {foreach($id in $required){$weights[$id]=1.0/$required.Count}}
$oldWeighted=0.0;$newWeighted=0.0
foreach($p in $paired){
    $oldWeighted += $weights[$p.Case]*$p.Dev3MedianS
    $newWeighted += $weights[$p.Case]*$p.Dev5MedianS
}
$net=100*($newWeighted-$oldWeighted)/$oldWeighted
$adequate=@($paired|Where-Object{$_.N -lt 3}).Count -eq 0
$paired|Format-Table Case,N,Dev3MedianS,Dev5MedianS,DeltaPct -AutoSize
[pscustomobject]@{
    OfflineComparatorPASS=$true
    ModelAndHostMatched=$true
    AllFiveSemanticCasesMatched=$true
    CorrectnessGated=$true
    PerCaseRepetitions=($paired|Select-Object -First 1).N
    Profile=$profile
    ProfileObserved=$weighted
    Dev3WeightedMedianS=[Math]::Round($oldWeighted,3)
    Dev5WeightedMedianS=[Math]::Round($newWeighted,3)
    Dev5MinusDev3Percent=[Math]::Round($net,2)
    Interpretation=$(if(-not $weighted){'ILLUSTRATIVE_ONLY: no observed workload mix'}elseif(-not $adequate){'EXPLORATORY_ONLY: fewer than 3 matched repetitions'}elseif($net -lt 0){'CANDIDATE_NET_GAIN: requires independent variance/cross-host review'}else{'NO_NET_GAIN: dev5 is not faster'})
    DoesNotRunInference=$true
    DoesNotTestDev5OnlyMixedWrites=$true
}|Format-List
 -or
   [string]$b.environment.commit_sha -ceq $dev3Pin) {
    throw 'Unpinned or invalid dev3/dev5 commit SHA in benchmark inputs.'
}
if([string]$a.environment.scoped_read_evidence -cne 'matched-bounded-recent-turn' -or
   [string]$b.environment.scoped_read_evidence -cne 'matched-bounded-recent-turn') {
    throw 'Dev3 and dev5 scoped read must share bounded recent-turn evidence for semantic comparability.'
}
if([string]$b.environment.dev5_flags -cne 'A=on;B=on;C=off;Mixed=off;StructuredRead=on') {
    throw 'Dev5 benchmark must use comparable A+B flags with C and Mixed off.'
}
foreach($field in @('fixture_version','host_class','model_id','model_digest','ollama_version','num_ctx','think','warm_state','logging_mode')){
    if([string]$a.environment.$field -cne [string]$b.environment.$field -or
       [string]::IsNullOrWhiteSpace([string]$a.environment.$field)) {
        throw "Unmatched or missing environment field $field: cannot attribute dev5 delta."
    }
}
$required=@('plain-local','dense-write','correction','preference-only','scoped-read')
$paired=@()
foreach($caseId in $required){
    $aCase=@($a.samples|Where-Object{[string]$_.case_id -eq $caseId})
    $bCase=@($b.samples|Where-Object{[string]$_.case_id -eq $caseId})
    if($aCase.Count -eq 0 -or $aCase.Count -ne $bCase.Count){throw "Missing/unmatched scenario: $caseId"}
    $idsA=@($aCase|ForEach-Object{[int]$_.repetition}|Sort-Object)
    $idsB=@($bCase|ForEach-Object{[int]$_.repetition}|Sort-Object)
    if(($idsA|Select-Object -Unique).Count -ne $idsA.Count -or
       ($idsB|Select-Object -Unique).Count -ne $idsB.Count -or
       ($idsA -join ',') -cne ($idsB -join ',')) {throw "Unpaired/duplicated repetitions: $caseId"}
    $old=Get-LfoMedian ([double[]]@($aCase|ForEach-Object{[double]$_.answer_wall_s}))
    $new=Get-LfoMedian ([double[]]@($bCase|ForEach-Object{[double]$_.answer_wall_s}))
    $paired+= [pscustomobject]@{
        Case=$caseId;N=$aCase.Count;Dev3MedianS=[Math]::Round($old,3)
        Dev5MedianS=[Math]::Round($new,3)
        DeltaPct=[Math]::Round(100*($new-$old)/$old,2)
        TokensInDev3=([double](($aCase|Measure-Object input_tokens -Average).Average))
        TokensInDev5=([double](($bCase|Measure-Object input_tokens -Average).Average))
        TokensOutDev3=([double](($aCase|Measure-Object output_tokens -Average).Average))
        TokensOutDev5=([double](($bCase|Measure-Object output_tokens -Average).Average))
    }
}
# The five common semantic tasks must be comparable. New dev5-only mixed
# provenance functionality is reported separately, NEVER blended into speed.
$unknownA=@($a.samples|Where-Object{$_.case_id -notin $required})
$unknownB=@($b.samples|Where-Object{$_.case_id -notin $required})
if($unknownA.Count -gt 0 -or $unknownB.Count -gt 0){throw 'Unknown/noncomparable scenarios in primary workload.'}
$weighted=$false;$weights=@{};$profile='illustrative-equal-weight'
if(-not [string]::IsNullOrWhiteSpace($WeightsPath)){
    $profileObj=Get-Content -LiteralPath $WeightsPath -Raw -Encoding UTF8|ConvertFrom-Json
    if([string]$profileObj.schema -ne 'lfo-observed-workload-weights-v1' -or
       [string]::IsNullOrWhiteSpace([string]$profileObj.provenance)){throw 'Invalid/missing observed workload profile provenance.'}
    $sum=0.0
    foreach($id in $required){
        $v=$profileObj.weights.$id
        if($null -eq $v -or [double]$v -lt 0){throw "Missing/negative case weight: $id"}
        $weights[$id]=[double]$v;$sum+=[double]$v
    }
    if([Math]::Abs($sum-1.0) -gt 0.000001){throw "Weights must sum to 1.0, got $sum"}
    $weighted=$true;$profile=[string]$profileObj.provenance
} else {foreach($id in $required){$weights[$id]=1.0/$required.Count}}
$oldWeighted=0.0;$newWeighted=0.0
foreach($p in $paired){
    $oldWeighted += $weights[$p.Case]*$p.Dev3MedianS
    $newWeighted += $weights[$p.Case]*$p.Dev5MedianS
}
$net=100*($newWeighted-$oldWeighted)/$oldWeighted
$adequate=@($paired|Where-Object{$_.N -lt 3}).Count -eq 0
$paired|Format-Table Case,N,Dev3MedianS,Dev5MedianS,DeltaPct -AutoSize
[pscustomobject]@{
    OfflineComparatorPASS=$true
    ModelAndHostMatched=$true
    AllFiveSemanticCasesMatched=$true
    CorrectnessGated=$true
    PerCaseRepetitions=($paired|Select-Object -First 1).N
    Profile=$profile
    ProfileObserved=$weighted
    Dev3WeightedMedianS=[Math]::Round($oldWeighted,3)
    Dev5WeightedMedianS=[Math]::Round($newWeighted,3)
    Dev5MinusDev3Percent=[Math]::Round($net,2)
    Interpretation=$(if(-not $weighted){'ILLUSTRATIVE_ONLY: no observed workload mix'}elseif(-not $adequate){'EXPLORATORY_ONLY: fewer than 3 matched repetitions'}elseif($net -lt 0){'CANDIDATE_NET_GAIN: requires independent variance/cross-host review'}else{'NO_NET_GAIN: dev5 is not faster'})
    DoesNotRunInference=$true
    DoesNotTestDev5OnlyMixedWrites=$true
}|Format-List
