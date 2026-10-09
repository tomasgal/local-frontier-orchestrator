# Deterministic offline SELF-TEST of the benchmark comparator.
# All numbers below are synthetic parser/contract fixtures, NOT measurements.
# No model calls, SQLite, worktree modifications, or production memory access.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$comparator=Join-Path $repo 'tests\Compare-Dev5VsDev3Workload.ps1'
$tokens=$null; $errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($comparator,[ref]$tokens,[ref]$errors)
if(@($errors).Count -gt 0){throw "Comparator parser errors: $($errors | Out-String)"}
$root=Join-Path ([IO.Path]::GetTempPath()) ('LFO-dev5-comparator-selftest-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root -Force)
$aPath=Join-Path $root 'dev3-synthetic.json'
$bPath=Join-Path $root 'dev5-synthetic.json'
$cases=@('plain-local','dense-write','correction','preference-only','scoped-read')
function New-LfoComparatorFixture([string]$Variant) {
    $environment=[ordered]@{
        commit_sha=$(if($Variant -eq 'dev3'){'a34658b81742596520da844618b5bb39f3329279'}else{'b4957f54107200f62a82e67ec87ffb12976fc691'})
        fixture_version='synthetic-contract-v1'
        host_class='synthetic-self-test'
        model_id='mock-no-model'
        model_digest='mock-no-model'
        ollama_version='mock-no-model'
        num_ctx=5120
        think=$false
        warm_state='warm'
        logging_mode='normal'
        thread_profile='synthetic'
        gpu_profile='synthetic'
        scoped_read_evidence='matched-bounded-recent-turn'
    }
    if($Variant -eq 'dev5'){$environment['dev5_flags']='A=on;B=on;C=off;Mixed=off;StructuredRead=on'}
    $samples=@()
    foreach($id in $cases) {
        foreach($rep in @(1,2,3)) {
            $samples+= [ordered]@{
                case_id=$id
                repetition=$rep
                answer_correct=$true
                memory_correct=$true
                answer_wall_s=$(if($Variant -eq 'dev3'){1.0+0.1*$rep}else{0.8+0.1*$rep})
                input_tokens=100
                output_tokens=20
            }
        }
    }
    return [pscustomobject]@{schema='lfo-dev5-vs-dev3-v1';data_kind='synthetic-self-test';variant=$Variant;environment=[pscustomobject]$environment;samples=@($samples)}
}
function Write-LfoComparatorFixtures($A,$B) {
    $A | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $aPath -Encoding UTF8
    $B | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $bPath -Encoding UTF8
}
function Assert-LfoComparator([bool]$Okay,[string]$Why) {
    if(-not $Okay){throw $Why}
}
function Expect-LfoComparatorFailure([scriptblock]$Change,[string]$Expected) {
    $a=New-LfoComparatorFixture 'dev3'
    $b=New-LfoComparatorFixture 'dev5'
    & $Change $a $b
    Write-LfoComparatorFixtures $a $b
    $failed=$false
    try {
        $null=& $comparator -Dev3Path $aPath -Dev5Path $bPath -AllowSyntheticTestData 2>&1 | Out-String
    } catch {
        $failed=($_.Exception.Message -match $Expected)
    }
    Assert-LfoComparator $failed "Comparator failed to reject contract break: $Expected"
}
$a=New-LfoComparatorFixture 'dev3'
$b=New-LfoComparatorFixture 'dev5'
Write-LfoComparatorFixtures $a $b
$good=(& $comparator -Dev3Path $aPath -Dev5Path $bPath -AllowSyntheticTestData | Out-String -Width 180)
Assert-LfoComparator ($good -match 'OfflineComparatorPASS\s*:\s*True' -and
                      $good -match 'SYNTHETIC_SELF_TEST_ONLY' -and
                      $good -match 'AllFiveSemanticCasesMatched\s*:\s*True') 'Synthetic happy path did not pass or was mislabeled as a real finding.'
$rejectedByDefault=$false
try {$null=& $comparator -Dev3Path $aPath -Dev5Path $bPath 2>&1 | Out-String}
catch {$rejectedByDefault=($_.Exception.Message -match 'must be measured')}
Assert-LfoComparator $rejectedByDefault 'Comparator accepted synthetic results without opt-in.'
Expect-LfoComparatorFailure {param($a,$b) $b.environment.commit_sha='not-a-sha'} 'commit SHA'
Expect-LfoComparatorFailure {param($a,$b) $b.environment.scoped_read_evidence='dev5-only-evidence'} 'matched bounded recent-turn evidence'
Expect-LfoComparatorFailure {param($a,$b) $b.environment.thread_profile='another-thread-profile'} 'thread_profile'
Expect-LfoComparatorFailure {param($a,$b) $b.environment.dev5_flags='A=on;B=on;C=on;Mixed=off;StructuredRead=on'} 'A\+B flags'
Expect-LfoComparatorFailure {param($a,$b) $b.samples[0].answer_correct=$false} 'Correctness failure'
Expect-LfoComparatorFailure {param($a,$b) $b.samples[0].answer_wall_s=0} 'invalid sample'
Expect-LfoComparatorFailure {param($a,$b) $b.samples[1].repetition=1} 'duplicated repetitions'
Expect-LfoComparatorFailure {param($a,$b) $b.samples[0].case_id='dev5-only-case'} 'scenario'
[pscustomobject]@{
    PASS=$true
    SyntheticInputsOnly=$true
    SyntheticRejectedWithoutExplicitOptIn=$true
    PairedCases=5
    SyntheticRepetitionsPerCase=3
    NegativeContractCases=8
    ActualDev3VsDev5Measurements=0
    ModelCalls=0
    ProductionMemoryTouched=$false
    TempRoot=$root
} | Format-List
