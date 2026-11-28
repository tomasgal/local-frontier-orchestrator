[CmdletBinding()]
param([ValidateRange(1,1000)][int]$Repeat=100)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../src/LfoG2CesPlan.ps1')
function Assert-P82([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message}}
function New-P82Eligibility([bool]$Mask,[bool]$Support,[bool]$Scope){
    @{MASK_CONTEXT=$Mask;PRESERVE_SUPPORT=$Support;SCOPE_BIND=$Scope}
}
function New-P82Finding([string]$Status='VERIFIED',[string]$State='CONTRADICTED',[string]$Producer='cpu',[string]$Scope='conversation:1'){
    @{scope_id=$Scope;target_ref='turn:1#claim:1';invariant='runtime_operation';source_ref='receipt:1';producer=$Producer;version='1';state=$State;status=$Status}
}
$bank=@(
    @{n='reference';shape='S0';e=(New-P82Eligibility $true $true $true);expected='S0'},
    @{n='S1 eligible';shape='S1';e=(New-P82Eligibility $true $true $true);expected='S1'},
    @{n='S2 eligible';shape='S2';e=(New-P82Eligibility $true $true $true);expected='S2'},
    @{n='S3 eligible';shape='S3';e=(New-P82Eligibility $true $true $true);expected='S3'},
    @{n='mask inhibited';shape='S3';e=(New-P82Eligibility $false $true $true);expected='S2'},
    @{n='scope inhibited';shape='S3';e=(New-P82Eligibility $true $true $false);expected='S1'},
    @{n='support inhibited';shape='S3';e=(New-P82Eligibility $true $false $true);expected='S0'},
    @{n='no untested support only';shape='S3';e=(New-P82Eligibility $false $true $false);expected='S0'},
    @{n='no substitution outside request';shape='S1';e=(New-P82Eligibility $false $true $true);expected='S0'},
    @{n='no substitution outside S2';shape='S2';e=(New-P82Eligibility $true $true $false);expected='S0'},
    @{n='unknown eligibility';shape='S3';e=@{MASK_CONTEXT='true';PRESERVE_SUPPORT=$true;SCOPE_BIND=$true};expected='S2'},
    @{n='missing eligibility';shape='S3';e=$null;expected='S0'}
)
$n=0
foreach($t in $bank){
    $p=New-LfoG2CesPlan -RequestedShape $t.shape -ScopeId 'conversation:1' -Eligibility $t.e -TrustedEnvelope
    Assert-P82 ($p.state -ceq 'PLANNED' -and $p.selected_shape -ceq $t.expected) ($t.n+': '+$p.selected_shape+' '+$p.reason)
    $n++
}
$e=New-P82Eligibility $true $true $true
$d=New-P82Finding
$p=New-LfoG2CesPlan -RequestedShape S3 -ScopeId 'conversation:1' -Eligibility $e -Findings @($d) -TrustedEnvelope
Assert-P82 (($p.operators -join ',') -ceq 'MASK_CONTEXT,PRESERVE_SUPPORT,SCOPE_BIND') 'Order mismatch';$n++
Assert-P82 ($p.review_targets.Count -eq 1 -and $p.review_targets[0].target_ref -ceq $d.target_ref) 'Review linkage lost';$n++
Assert-P82 ($p.extra_model_calls -eq 0 -and $p.execution -ceq 'PLAN_ONLY' -and -not $p.production_enabled) 'Execution boundary changed';$n++
$provisional=New-P82Finding -Status PROVISIONAL -Producer edge
$p=New-LfoG2CesPlan -RequestedShape S0 -ScopeId 'conversation:1' -Eligibility $e -Findings @($provisional) -TrustedEnvelope
Assert-P82 ($p.review_targets.Count -eq 0 -and $p.operators.Count -eq 0) 'Provisional auto-activation';$n++
$s=New-P82Finding -State SUPPORTED -Producer cpu2
$p=New-LfoG2CesPlan -RequestedShape S0 -ScopeId 'conversation:1' -Findings @($d,$s) -TrustedEnvelope
Assert-P82 ($p.review_targets.Count -eq 0 -and $p.aggregation.groups[0].state -ceq 'CONFLICT') 'Conflict activated';$n++
$p=New-LfoG2CesPlan -RequestedShape S0 -ScopeId 'conversation:1' -Findings @($d) -TrustedEnvelope
Assert-P82 ($p.review_targets.Count -eq 1 -and $p.operators.Count -eq 0) 'Contradiction auto-activated shaping';$n++
$p=New-LfoG2CesPlan -RequestedShape S3 -ScopeId 'conversation:1' -Eligibility $e
Assert-P82 ($p.state -ceq 'ABSTAIN' -and $p.operators.Count -eq 0) 'Untrusted plan accepted';$n++
$foreign=New-P82Finding -Scope 'conversation:2'
$p=New-LfoG2CesPlan -RequestedShape S3 -ScopeId 'conversation:1' -Eligibility $e -Findings @($foreign) -TrustedEnvelope
Assert-P82 ($p.state -ceq 'ABSTAIN' -and $p.operators.Count -eq 0) 'Foreign finding accepted';$n++
$before=$e|ConvertTo-Json -Compress
$p=New-LfoG2CesPlan -RequestedShape S3 -ScopeId 'conversation:1' -Eligibility $e -TrustedEnvelope
Assert-P82 (($e|ConvertTo-Json -Compress) -ceq $before) 'Eligibility mutation';$n++
Write-Host "UNIT PASS $n/$n"
$times=New-Object 'System.Collections.Generic.List[double]'
for($i=0;$i -lt $Repeat;$i++){
    foreach($t in $bank){
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $p=New-LfoG2CesPlan -RequestedShape $t.shape -ScopeId 'conversation:1' -Eligibility $t.e -Findings @($d) -TrustedEnvelope
        $sw.Stop()
        Assert-P82 ($p.selected_shape -ceq $t.expected) 'Repeated plan changed'
        $times.Add($sw.Elapsed.TotalMilliseconds)
    }
}
Write-Host ("P82 CES PLAN PASS; shapes=4; warm_calls={0}; mean_ms={1:N3}; model_calls=0; db_writes=0; execution=PLAN_ONLY" -f $times.Count,($times|Measure-Object -Average).Average)
