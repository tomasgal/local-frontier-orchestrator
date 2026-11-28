[CmdletBinding()]
param([ValidateRange(1,1000)][int]$Repeat=100)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../src/LfoG2FindingAggregation.ps1')
function New-P81Finding([string]$State='CONTRADICTED',[string]$Status='VERIFIED',[string]$Producer='cpu',[string]$Target='turn:1#claim:1',[string]$Invariant='runtime_operation',[string]$Source='receipt:1',[string]$Scope='conversation:1'){
    [pscustomobject]@{scope_id=$Scope;target_ref=$Target;invariant=$Invariant;source_ref=$Source;producer=$Producer;version='1';state=$State;status=$Status}
}
function Assert-P81([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message}}
$d=New-P81Finding
$s=New-P81Finding SUPPORTED VERIFIED 'cpu2'
$u=New-P81Finding UNKNOWN VERIFIED 'cpu2'
$na=New-P81Finding NOT_APPLICABLE VERIFIED 'cpu2'
$pd=New-P81Finding CONTRADICTED PROVISIONAL 'edge'
$provisionalSupport=New-P81Finding SUPPORTED PROVISIONAL 'edge'
$pn=New-P81Finding NOT_APPLICABLE PROVISIONAL 'edge'
$bank=@(
    @{n='verified contradiction';f=@($d);s='CONTRADICTED';e='REVIEW_FOR_INTERVENTION'},
    @{n='verified support';f=@($s);s='SUPPORTED';e='INHIBIT'},
    @{n='verified exclusion';f=@($na);s='NOT_APPLICABLE';e='INHIBIT'},
    @{n='unknown';f=@($u);s='UNKNOWN';e='INHIBIT'},
    @{n='provisional contradiction';f=@($pd);s='UNKNOWN';e='INHIBIT'},
    @{n='provisional support';f=@($provisionalSupport);s='UNKNOWN';e='INHIBIT'},
    @{n='verified conflict';f=@($d,$s);s='CONFLICT';e='INHIBIT'},
    @{n='scope conflict';f=@($d,$na);s='CONFLICT';e='INHIBIT'},
    @{n='scope support conflict';f=@($s,$na);s='CONFLICT';e='INHIBIT'},
    @{n='provisional contrary';f=@($d,$provisionalSupport);s='CONTRADICTED';e='REVIEW_FOR_INTERVENTION'},
    @{n='provisional exclusion';f=@($d,$pn);s='CONTRADICTED';e='REVIEW_FOR_INTERVENTION'},
    @{n='verified exclusion vs provisional';f=@($na,$pd);s='NOT_APPLICABLE';e='INHIBIT'},
    @{n='unknown plus contradiction';f=@($u,$d);s='CONTRADICTED';e='REVIEW_FOR_INTERVENTION'},
    @{n='duplicate';f=@($d,$d);s='CONTRADICTED';e='REVIEW_FOR_INTERVENTION'}
)
$checks=0
foreach($t in $bank){
    $r=Merge-LfoG2Findings 'conversation:1' $t.f -TrustedEnvelope
    Assert-P81 ($r.state -ceq 'AGGREGATED' -and $r.groups.Count -eq 1 -and $r.groups[0].state -ceq $t.s -and $r.groups[0].eligibility -ceq $t.e) ($t.n+': '+$r.reason)
    $checks++
}
$r=Merge-LfoG2Findings 'conversation:1' @($d,$d,$provisionalSupport) -TrustedEnvelope
Assert-P81 ($r.duplicate_count -eq 1 -and $r.groups[0].findings.Count -eq 2) 'Exact deduplication failed';$checks++
$other=New-P81Finding SUPPORTED VERIFIED cpu2 'turn:1#claim:2'
$r=Merge-LfoG2Findings 'conversation:1' @($d,$other) -TrustedEnvelope
Assert-P81 ($r.groups.Count -eq 2 -and $r.groups[0].state -ceq 'CONTRADICTED' -and $r.groups[1].state -ceq 'SUPPORTED') 'Target contamination';$checks++
$other=New-P81Finding SUPPORTED VERIFIED cpu2 'turn:1#claim:1' 'numeric_comparison'
$r=Merge-LfoG2Findings 'conversation:1' @($d,$other) -TrustedEnvelope
Assert-P81 ($r.groups.Count -eq 2) 'Invariant propagation';$checks++
$r=Merge-LfoG2Findings 'conversation:1' @($d)
Assert-P81 ($r.state -ceq 'ABSTAIN') 'Untrusted envelope accepted';$checks++
$other=New-P81Finding -Scope 'conversation:2'
$r=Merge-LfoG2Findings 'conversation:1' @($d,$other) -TrustedEnvelope
Assert-P81 ($r.state -ceq 'ABSTAIN' -and $r.groups.Count -eq 0) 'Foreign scope accepted';$checks++
$other=New-P81Finding -Status 'CERTAIN'
$r=Merge-LfoG2Findings 'conversation:1' @($d,$other) -TrustedEnvelope
Assert-P81 ($r.state -ceq 'ABSTAIN') 'Unknown status accepted';$checks++
$r=Merge-LfoG2Findings 'conversation:1' @() -TrustedEnvelope
Assert-P81 ($r.state -ceq 'AGGREGATED' -and $r.groups.Count -eq 0) 'Empty input failed';$checks++
$before=@($d,$s,$pd)|ConvertTo-Json -Depth 10 -Compress
$r=Merge-LfoG2Findings 'conversation:1' @($d,$s,$pd) -TrustedEnvelope
Assert-P81 ((@($d,$s,$pd)|ConvertTo-Json -Depth 10 -Compress) -ceq $before) 'Input mutation';$checks++
$r=Merge-LfoG2Findings 'conversation:1' @($pd,$pd,$pd) -TrustedEnvelope
Assert-P81 ($r.groups[0].state -ceq 'UNKNOWN' -and $r.duplicate_count -eq 2) 'Repeated provisional evidence promoted';$checks++
Write-Host "UNIT PASS $checks/$checks"
$times=New-Object 'System.Collections.Generic.List[double]'
for($i=0;$i -lt $Repeat;$i++){
    foreach($t in $bank){
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $r=Merge-LfoG2Findings 'conversation:1' $t.f -TrustedEnvelope
        $sw.Stop()
        Assert-P81 ($r.groups[0].state -ceq $t.s) 'Repeat changed'
        $times.Add($sw.Elapsed.TotalMilliseconds)
    }
}
Write-Host ("P81 AGGREGATION PASS; warm_calls={0}; mean_ms={1:N3}; model_calls=0; db_writes=0" -f $times.Count,($times|Measure-Object -Average).Average)
