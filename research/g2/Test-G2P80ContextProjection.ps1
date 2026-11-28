[CmdletBinding()]
param([ValidateRange(1,1000)][int]$Repeat=100)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../src/LfoG2ContextProjection.ps1')
function New-P80Item([string]$Layer,[string]$Ref,[string]$Text,[string]$Status='UNKNOWN',[string]$Scope='conversation:1'){
    [pscustomobject]@{layer=$Layer;source_ref=$Ref;text=$Text;scope_id=$Scope;external_evidence_status=$Status}
}
function Assert-P80([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message}}
$task='Current request: compare the evidence without changing the question.'
$l0=New-P80Item L0 'turn:1' 'A prior claim was recorded.' NONE
$l1=New-P80Item L1 'working:1' 'A prior claim was recorded.' OBSERVED
$l2=New-P80Item L2 'fact:4' 'A.value = 61' OBSERVED
$l4=New-P80Item L4 'obs:5' 'Possible unsupported inference.' OBSERVED
$other=New-P80Item L0 'turn:2' 'A prior claim was recorded.' OBSERVED
$conflict=New-P80Item L0 'turn:1' 'Different text for same reference.' NONE
$wrongScope=New-P80Item L2 'fact:9' 'B.value = 84' UNKNOWN 'conversation:2'
$badLayer=New-P80Item L3 'index:1' 'Index metadata.'
$bank=@($l0,$l1,$l2,$l4,$other,$l0)
$before=$bank|ConvertTo-Json -Depth 10 -Compress
$p=New-LfoG2ContextProjection $task 'conversation:1' $bank -TrustedEnvelope
$n=0
Assert-P80 ($p.state -ceq 'PROJECTED' -and $p.items.Count -eq 5) 'Projection failed';$n++
Assert-P80 ($p.current_text -ceq $task) 'Current task changed';$n++
Assert-P80 ($p.duplicate_count -eq 1 -and $p.input_chars-$p.projected_chars -eq $l0.text.Length) 'Exact deduplication failed';$n++
Assert-P80 ($p.items[0].external_evidence_status -ceq 'NONE' -and $p.items[4].external_evidence_status -ceq 'OBSERVED') 'Runtime provenance lost';$n++
Assert-P80 ($p.items[1].role -ceq 'LOSSY_ORIENTATION' -and $p.items[1].external_evidence_status -ceq 'UNKNOWN') 'L1 authority inflated';$n++
Assert-P80 ($p.items[2].role -ceq 'STRUCTURED_MEMORY' -and $p.items[2].external_evidence_status -ceq 'UNKNOWN') 'L2 authority inflated';$n++
Assert-P80 ($p.items[3].role -ceq 'EPISTEMIC_OBSERVATION' -and $p.items[3].external_evidence_status -ceq 'UNKNOWN') 'L4 authority inflated';$n++
Assert-P80 (($bank|ConvertTo-Json -Depth 10 -Compress) -ceq $before) 'Source mutated';$n++
$q=New-LfoG2ContextProjection $task 'conversation:1' @($l0,$conflict) -TrustedEnvelope
Assert-P80 ($q.state -ceq 'ABSTAIN' -and $null -eq $q.packet) 'Conflict silently resolved';$n++
$q=New-LfoG2ContextProjection $task 'conversation:1' @($l0,$wrongScope) -TrustedEnvelope
Assert-P80 ($q.state -ceq 'ABSTAIN') 'Cross scope accepted';$n++
$q=New-LfoG2ContextProjection $task 'conversation:1' @($badLayer) -TrustedEnvelope
Assert-P80 ($q.state -ceq 'ABSTAIN') 'Index treated as evidence';$n++
$q=New-LfoG2ContextProjection $task 'conversation:1' $bank
Assert-P80 ($q.state -ceq 'ABSTAIN') 'Untrusted input accepted';$n++
$q=New-LfoG2ContextProjection $task 'conversation:1' @() -TrustedEnvelope
Assert-P80 ($q.state -ceq 'ABSTAIN' -and $q.reason -ceq 'NO_CONTEXT') 'Empty context mishandled';$n++
Write-Host "UNIT PASS $n/$n"
$times=New-Object 'System.Collections.Generic.List[double]'
for($i=0;$i -lt $Repeat;$i++){
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $q=New-LfoG2ContextProjection $task 'conversation:1' $bank -TrustedEnvelope
    $sw.Stop()
    Assert-P80 ($q.state -ceq 'PROJECTED' -and $q.items.Count -eq 5) 'Repeat changed'
    $times.Add($sw.Elapsed.TotalMilliseconds)
}
Write-Host ("P80 PROJECTION PASS; warm_calls={0}; mean_ms={1:N3}; source_items=6; projected_items=5; model_calls=0; db_writes=0" -f $times.Count,($times|Measure-Object -Average).Average)
