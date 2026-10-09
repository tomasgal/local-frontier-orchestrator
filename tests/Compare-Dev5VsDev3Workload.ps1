# Read-only, OFFLINE comparison of independently validated paired workload measurements.
# No model, SQLite writes, synthetic measurements, or production file access.
param(
    [Parameter(Mandatory=$true)][string]$Dev3Path,
    [Parameter(Mandatory=$true)][string]$Dev5Path,
    [string]$WeightsPath,
    # Explicitly limited to the offline comparator SELF-TEST. Such output is not evidence of speedup.
    [switch]$AllowSyntheticTestData
)
$ErrorActionPreference='Stop'
$required=@('plain-local','dense-write','correction','preference-only','scoped-read')

function Read-LfoBenchmark([string]$Path,[string]$Variant) {
    $d=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if([string]$d.schema -cne 'lfo-dev5-vs-dev3-v1' -or [string]$d.variant -cne $Variant) {
        throw "Wrong schema/variant: $Path"
    }
    if([string]$d.data_kind -cne 'measured' -and
       -not ($AllowSyntheticTestData -and [string]$d.data_kind -ceq 'synthetic-self-test')) {
        throw "Benchmark inputs must be measured; synthetic data is only allowed for explicit self-tests: $Path"
    }
    if($null -eq $d.environment -or $null -eq $d.samples -or @($d.samples).Count -eq 0) {
        throw "Missing environment or samples: $Path"
    }
    foreach($sample in @($d.samples)) {
        if([string]::IsNullOrWhiteSpace([string]$sample.case_id) -or
           $null -eq $sample.repetition -or [int]$sample.repetition -le 0 -or
           $null -eq $sample.answer_wall_s -or [double]$sample.answer_wall_s -le 0 -or
           [double]::IsNaN([double]$sample.answer_wall_s) -or
           [double]::IsInfinity([double]$sample.answer_wall_s) -or
           $sample.answer_correct -isnot [bool] -or $sample.memory_correct -isnot [bool] -or
           $null -eq $sample.input_tokens -or $null -eq $sample.output_tokens -or
           [int]$sample.input_tokens -lt 0 -or [int]$sample.output_tokens -lt 0) {
            throw "Incomplete or invalid sample in $Path"
        }
        if(-not $sample.answer_correct -or -not $sample.memory_correct) {
            throw "Correctness failure; cannot establish net gain: $Path / $($sample.case_id)"
        }
    }
    return $d
}
function Get-LfoMedian([double[]]$Values) {
    $sorted=@($Values | Sort-Object)
    $n=$sorted.Count
    if($n -eq 0){throw 'Cannot calculate median of empty data.'}
    $mid=[int][Math]::Floor($n / 2)
    if($n % 2 -eq 1){return [double]$sorted[$mid]}
    return ([double]$sorted[$mid-1]+[double]$sorted[$mid])/2.0
}
$a=Read-LfoBenchmark $Dev3Path 'dev3'
$b=Read-LfoBenchmark $Dev5Path 'dev5'
if([string]$a.data_kind -cne [string]$b.data_kind) {throw 'Cannot compare measured and synthetic data.'}

$dev3Pin='a34658b81742596520da844618b5bb39f3329279'
if([string]$a.environment.commit_sha -cne $dev3Pin -or
   [string]$b.environment.commit_sha -cnotmatch '^[0-9a-f]{40}$' -or
   [string]$b.environment.commit_sha -ceq $dev3Pin) {
    throw 'Unpinned or invalid dev3/dev5 commit SHA in benchmark inputs.'
}
if([string]$a.environment.scoped_read_evidence -cne 'matched-bounded-recent-turn' -or
   [string]$b.environment.scoped_read_evidence -cne 'matched-bounded-recent-turn') {
    throw 'Dev3 and dev5 scoped read require matched bounded recent-turn evidence.'
}
if([string]$b.environment.dev5_flags -cne 'A=on;B=on;C=off;Mixed=off;StructuredRead=on') {
    throw 'Dev5 benchmark requires comparable A+B flags; C and Mixed OFF.'
}
foreach($field in @('fixture_version','host_class','model_id','model_digest','ollama_version','num_ctx','think','warm_state','logging_mode','thread_profile','gpu_profile')) {
    $av=$a.environment.$field
    $bv=$b.environment.$field
    if($null -eq $av -or $null -eq $bv -or
       [string]::IsNullOrWhiteSpace([string]$av) -or
       [string]$av -cne [string]$bv) {
        throw "Unmatched or missing environment field ${field}: cannot attribute dev5 delta."
    }
}
if([string]$a.environment.think -cne 'False' -or [string]$b.environment.think -cne 'False') {
    throw 'Comparable experiment requires think=false.'
}

$paired=@()
foreach($caseId in $required) {
    $aCase=@($a.samples | Where-Object {[string]$_.case_id -ceq $caseId})
    $bCase=@($b.samples | Where-Object {[string]$_.case_id -ceq $caseId})
    if($aCase.Count -eq 0 -or $aCase.Count -ne $bCase.Count) {
        throw "Missing/unmatched scenario: $caseId"
    }
    $idsA=@($aCase | ForEach-Object {[int]$_.repetition} | Sort-Object)
    $idsB=@($bCase | ForEach-Object {[int]$_.repetition} | Sort-Object)
    if(@($idsA | Select-Object -Unique).Count -ne $idsA.Count -or
       @($idsB | Select-Object -Unique).Count -ne $idsB.Count -or
       ($idsA -join ',') -cne ($idsB -join ',')) {
        throw "Unpaired/duplicated repetitions: $caseId"
    }
    $old=Get-LfoMedian ([double[]]@($aCase | ForEach-Object {[double]$_.answer_wall_s}))
    $new=Get-LfoMedian ([double[]]@($bCase | ForEach-Object {[double]$_.answer_wall_s}))
    $paired+= [pscustomobject]@{
        Case=$caseId
        N=$aCase.Count
        Dev3MedianS=$old
        Dev5MedianS=$new
        DeltaPct=[Math]::Round(100.0*($new-$old)/$old,2)
        TokensInDev3=($aCase | Measure-Object -Property input_tokens -Average).Average
        TokensInDev5=($bCase | Measure-Object -Property input_tokens -Average).Average
        TokensOutDev3=($aCase | Measure-Object -Property output_tokens -Average).Average
        TokensOutDev5=($bCase | Measure-Object -Property output_tokens -Average).Average
    }
}
if(@($a.samples | Where-Object {$_.case_id -cnotin $required}).Count -gt 0 -or
   @($b.samples | Where-Object {$_.case_id -cnotin $required}).Count -gt 0) {
    throw 'Unknown or noncomparable scenarios in primary workload.'
}
$weighted=$false; $weights=@{}; $profile='illustrative-equal-weight'
if(-not [string]::IsNullOrWhiteSpace($WeightsPath)) {
    $profileObj=Get-Content -LiteralPath $WeightsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if([string]$profileObj.schema -cne 'lfo-observed-workload-weights-v1' -or
       [string]::IsNullOrWhiteSpace([string]$profileObj.provenance)) {
        throw 'Invalid or missing observed workload weight provenance.'
    }
    $sum=0.0
    foreach($id in $required) {
        $v=$profileObj.weights.$id
        if($null -eq $v -or [double]::IsNaN([double]$v) -or
           [double]::IsInfinity([double]$v) -or [double]$v -lt 0) {
            throw "Missing/invalid case weight: $id"
        }
        $weights[$id]=[double]$v; $sum+=[double]$v
    }
    if([Math]::Abs($sum-1.0) -gt 0.000001){throw "Weights must sum to 1.0, got $sum"}
    $weighted=$true; $profile=[string]$profileObj.provenance
} else {
    foreach($id in $required){$weights[$id]=1.0/$required.Count}
}
$oldWeighted=0.0; $newWeighted=0.0
foreach($p in $paired) {
    $oldWeighted += $weights[$p.Case]*[double]$p.Dev3MedianS
    $newWeighted += $weights[$p.Case]*[double]$p.Dev5MedianS
}
$net=100.0*($newWeighted-$oldWeighted)/$oldWeighted
$adequate=@($paired | Where-Object {$_.N -lt 3}).Count -eq 0
$paired | Select-Object Case,N,@{N='Dev3MedianS';E={[Math]::Round($_.Dev3MedianS,3)}},@{N='Dev5MedianS';E={[Math]::Round($_.Dev5MedianS,3)}},DeltaPct | Format-Table -AutoSize
[pscustomobject]@{
    OfflineComparatorPASS=$true
    DataKind=[string]$a.data_kind
    ModelAndHostMatched=$true
    AllFiveSemanticCasesMatched=$true
    CorrectnessGated=$true
    PerCaseRepetitions=($paired | Select-Object -First 1).N
    Profile=$profile
    ProfileObserved=$weighted
    Dev3WeightedMedianS=[Math]::Round($oldWeighted,3)
    Dev5WeightedMedianS=[Math]::Round($newWeighted,3)
    Dev5MinusDev3Percent=[Math]::Round($net,2)
    Interpretation=$(if([string]$a.data_kind -eq 'synthetic-self-test'){'SYNTHETIC_SELF_TEST_ONLY: not a performance finding'}elseif(-not $weighted){'ILLUSTRATIVE_ONLY: no observed workload mix'}elseif(-not $adequate){'EXPLORATORY_ONLY: fewer than 3 matched repetitions'}elseif($net -lt 0){'CANDIDATE_NET_GAIN: requires independent variance/cross-host review'}else{'NO_NET_GAIN: dev5 is not faster'})
    DoesNotRunInference=$true
    DoesNotTestDev5OnlyMixedWrites=$true
} | Format-List
