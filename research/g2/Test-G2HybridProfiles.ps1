[CmdletBinding()]
param([string]$ConfigPath=(Join-Path $PSScriptRoot '../../config/G2Hybrid.config.psd1'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../src/LfoG2HybridPolicy.ps1')
$script:Checks=0
function Check([bool]$Condition,[string]$Message){
    if(-not $Condition){throw $Message}
    $script:Checks++
}
$default=Get-LfoG2HybridProfile -ConfigPath $ConfigPath
$compact=Get-LfoG2HybridProfile -ConfigPath $ConfigPath -Profile COMPACT_CPU
$scoped=Get-LfoG2HybridProfile -ConfigPath $ConfigPath -Profile SCOPED_CPU
Check ($default.Name -ceq (Import-PowerShellDataFile -LiteralPath $ConfigPath).DefaultProfile) 'Default profile mismatch.'
Check ($compact.PredicateContract -ceq 'COMPACT' -and $compact.CpuGate) 'COMPACT profile mismatch.'
Check ($scoped.PredicateContract -ceq 'SCOPED' -and $scoped.CpuGate) 'SCOPED profile mismatch.'
$rejected=$false
try{$null=Get-LfoG2HybridProfile -ConfigPath $ConfigPath -Profile INVALID}catch{$rejected=$true}
Check $rejected 'Unknown profile accepted.'
$literal=@{origin='WRAPPER';coverage='ENTIRE_TARGET';kind='LITERAL_ONLY';target_available=$true}
$missing=@{origin='WRAPPER';coverage='ENTIRE_TARGET';kind='ASSERTION_TARGET_MISSING';target_available=$false}
$partial=@{origin='WRAPPER';coverage='PARTIAL';kind='LITERAL_ONLY';target_available=$true}
$untrusted=@{origin='USER';coverage='ENTIRE_TARGET';kind='LITERAL_ONLY';target_available=$true}
$fakeBool=@{origin='WRAPPER';coverage='ENTIRE_TARGET';kind='LITERAL_ONLY';target_available='false'}
foreach($profile in @($compact,$scoped)){
    foreach($phase in @('PRE','POST')){
        $p=New-LfoG2HybridPlan -Profile $profile -Phase $phase -Text 'example'
        Check ($p.RequiresNpu -and $p.Body.questions.Count -eq 1 -and $p.Body.state -ceq 'example') 'Expected one NPU predicate.'
        $p=New-LfoG2HybridPlan -Profile $profile -Phase $phase -Text 'literal' -Metadata $literal -TrustedEnvelope
        Check (-not $p.RequiresNpu -and $p.Decision -ceq 'C' -and $null -eq $p.Body) 'Trusted literal gate failed.'
        $p=New-LfoG2HybridPlan -Profile $profile -Phase $phase -Text '' -Metadata $missing -TrustedEnvelope
        Check (-not $p.RequiresNpu -and $p.Decision -ceq 'U' -and $null -eq $p.Body) 'Missing target gate failed.'
        foreach($m in @($partial,$untrusted,$fakeBool)){
            $p=New-LfoG2HybridPlan -Profile $profile -Phase $phase -Text 'example' -Metadata $m -TrustedEnvelope
            Check ($p.RequiresNpu) 'Invalid scope, origin or type bypassed NPU.'
        }
        $p=New-LfoG2HybridPlan -Profile $profile -Phase $phase -Text 'example' -Metadata $literal
        Check ($p.RequiresNpu) 'Untrusted envelope bypassed NPU.'
    }
}
$matrix=@{present=@{NONE='D';UNKNOWN='U';MATCHED='C'};absent=@{NONE='C';UNKNOWN='C';MATCHED='C'};unknown=@{NONE='U';UNKNOWN='U';MATCHED='U'}}
foreach($s in @('present','absent','unknown')){foreach($rt in @('NONE','UNKNOWN','MATCHED')){Check ((Resolve-LfoG2Provenance -Semantic $s -Runtime $rt) -ceq $matrix[$s][$rt]) 'Decision mismatch.'}}
Check ((Resolve-LfoG2Provenance -Semantic 'invalid' -Runtime NONE) -ceq 'INVALID') 'Invalid semantic accepted.'
Check ((Resolve-LfoG2Provenance -Semantic present -Runtime invalid) -ceq 'INVALID') 'Invalid runtime accepted.'
$execution=Get-LfoG2ExecutionPolicy -ConfigPath $ConfigPath
$raw=Import-PowerShellDataFile -LiteralPath $ConfigPath
Check ($execution.Parallelism -eq $raw.Execution.Parallelism -and $execution.Topology -ceq $raw.Execution.Topology) 'Execution default mismatch.'
foreach($topology in @('CPU_GPU','NPU_GPU','GPU_GPU','CPU_CPU','NPU_CPU','GPU_CPU')){
    $on=Get-LfoG2ExecutionPolicy -ConfigPath $ConfigPath -Topology $topology -Parallelism $true
    $off=Get-LfoG2ExecutionPolicy -ConfigPath $ConfigPath -Topology $topology -Parallelism $false
    Check (($on.EdgeTarget+'_'+$on.MainTarget) -ceq $topology) 'Topology mismatch.'
    Check ((Get-LfoG2DispatchMode -ExecutionPolicy $on -Dependency INDEPENDENT -InputsReady $true -RuntimeSupportsParallel $true) -ceq 'PARALLEL') 'Parallel dispatch failed.'
    Check ((Get-LfoG2DispatchMode -ExecutionPolicy $off -Dependency INDEPENDENT -InputsReady $true -RuntimeSupportsParallel $true) -ceq 'SERIAL') 'Serial override failed.'
    Check ((Get-LfoG2DispatchMode -ExecutionPolicy $on -Dependency INDEPENDENT -InputsReady $true -RuntimeSupportsParallel $false) -ceq 'SERIAL') 'Capability gate failed.'
    Check ((Get-LfoG2DispatchMode -ExecutionPolicy $on -Dependency BLOCKING -InputsReady $true -RuntimeSupportsParallel $true) -ceq 'BEFORE_MAIN') 'Blocking dependency bypassed.'
    Check ((Get-LfoG2DispatchMode -ExecutionPolicy $on -Dependency POST_REQUIRED -InputsReady $true -RuntimeSupportsParallel $true) -ceq 'AFTER_OUTPUT') 'POST dependency bypassed.'
    Check ((Get-LfoG2DispatchMode -ExecutionPolicy $on -Dependency INDEPENDENT -InputsReady $false -RuntimeSupportsParallel $true) -ceq 'WAIT_DEPENDENCY') 'Unready dependency bypassed.'
}
$dual=Get-LfoG2ExecutionPolicy -ConfigPath $ConfigPath -Topology GPU_GPU -EdgeDeviceId 'gpu-a' -MainDeviceId 'gpu-b'
Check ($dual.EdgeDeviceId -ceq 'gpu-a' -and $dual.MainDeviceId -ceq 'gpu-b') 'Explicit device IDs lost.'
$rejected=$false
try{$null=Get-LfoG2ExecutionPolicy -ConfigPath $ConfigPath -Topology INVALID}catch{$rejected=$true}
Check $rejected 'Unknown topology accepted.'
Write-Host "G2 PROFILE UNIT PASS $script:Checks/$script:Checks; default=$($default.Name); topology=$($execution.Topology); parallelism=$($execution.Parallelism)"
