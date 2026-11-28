[CmdletBinding()]
param([ValidateRange(1,1000)][int]$Repeat=20)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../src/LfoG2DeterministicWitness.ps1')
function New-WitnessCase([string]$Op,$Values,[string]$Relation=''){
    $sources=New-Object 'System.Collections.Generic.List[object]'
    $bindings=New-Object 'System.Collections.Generic.List[object]'
    foreach($name in $Values.Keys){
        $literal=[string]$Values[$name];$sid='S'+($sources.Count+1)
        $sources.Add([pscustomobject]@{id=$sid;role='EVIDENCE';text=($name+': '+$literal)})
        $bindings.Add([pscustomobject]@{name=$name;source_id=$sid;start=($name.Length+2);length=$literal.Length;lexeme=$literal})
    }
    [pscustomobject]@{segments=$sources.ToArray();witness=[pscustomobject]@{operation=$Op;relation=$Relation;inputs=$bindings.ToArray()}}
}
function Assert-Witness([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message}}
function Near([double]$A,[double]$B){[Math]::Abs($A-$B) -lt 1e-9}
$bank=@(
    @{c=(New-WitnessCase 'UTILITY' ([ordered]@{a_hits='10';a_false='3';b_hits='8';b_false='0';benefit='2';cost='3'}));check={param($r) $r.results.higher_utility -ceq 'B' -and $r.results.b_minus_a -eq 5}},
    @{c=(New-WitnessCase 'STRATIFIED_RATES' ([ordered]@{a_easy_hits='9';a_easy_total='10';a_hard_hits='20';a_hard_total='100';b_easy_hits='80';b_easy_total='100';b_hard_hits='1';b_hard_total='10'}));check={param($r) $r.results.easy_higher -ceq 'A' -and $r.results.hard_higher -ceq 'A' -and $r.results.aggregate_higher -ceq 'B'}},
    @{c=(New-WitnessCase 'PREDICTIVE_VALUE' ([ordered]@{prevalence_pct='1';sensitivity_pct='90';specificity_pct='95'}));check={param($r) Near $r.results.positive_predictive_value (0.009/0.0585)}},
    @{c=(New-WitnessCase 'INTERVAL_ZERO' ([ordered]@{estimate='2';lower='-1';upper='3'}));check={param($r) $r.results.zero_excluded -eq $false}},
    @{c=(New-WitnessCase 'RELATIVE_REDUCTION' ([ordered]@{before_hits='20';before_total='100';after_hits='15';after_total='100';target_pct='25'}));check={param($r) (Near $r.results.relative_reduction_pct 25) -and (Near $r.results.reduction_percentage_points 5) -and $r.results.target_met}},
    @{c=(New-WitnessCase 'MISSING_BOUNDS' ([ordered]@{a_yes='8';a_no='1';a_unknown='1';b_yes='3';b_no='5';b_unknown='2'}));check={param($r) $r.results.a_strictly_higher_guaranteed -and -not $r.results.b_strictly_higher_guaranteed}},
    @{c=(New-WitnessCase 'PAIR_SUM' ([ordered]@{a1='2';a2='3';b1='1';b2='6'}));check={param($r) $r.results.lower_total -ceq 'A' -and $r.results.a_total -eq 5}},
    @{c=(New-WitnessCase 'COST_PER_SUCCESS' ([ordered]@{a_cost='120';a_success='8';b_cost='100';b_success='5'}));check={param($r) $r.results.lower_cost_per_success -ceq 'A' -and $r.results.a_cost_per_success -eq 15}},
    @{c=(New-WitnessCase 'COMPARE' ([ordered]@{a='9007199254740993';b='9007199254740992'}) 'GT');check={param($r) $r.results.holds -and $r.results.actual_relation -ceq 'GT'}}
)
$checks=0
foreach($item in $bank){
    $r=Invoke-LfoG2DeterministicWitness $item.c -TrustedBinding
    Assert-Witness ($r.state -ceq 'COMPUTED' -and (& $item.check $r)) ('Operation failed: '+$item.c.witness.operation+' '+$r.reason)
    $checks++
}
foreach($t in @(@('GT','2','1',$true),@('LT','2','1',$false),@('EQ','1.00','1',$true),@('GE','-2','-2',$true),@('LE','-2','-3',$false),@('NE','1','1',$false))){
    $c=New-WitnessCase 'COMPARE' ([ordered]@{a=$t[1];b=$t[2]}) $t[0]
    $r=Invoke-LfoG2DeterministicWitness $c -TrustedBinding
    Assert-Witness ($r.state -ceq 'COMPUTED' -and $r.results.holds -eq $t[3]) ('Comparison failed: '+$t[0]);$checks++
}
$r=Invoke-LfoG2DeterministicWitness $bank[0].c
Assert-Witness ($r.state -ceq 'ABSTAIN' -and $null -eq $r.results) 'Unverified binding accepted';$checks++
$r=Invoke-LfoG2DeterministicWitness $null
Assert-Witness ($r.state -ceq 'ABSTAIN') 'Missing binding accepted';$checks++
$bad=@(
    @{label='wrong literal';mut={param($c) $c.witness.inputs[0].lexeme='9'}},
    @{label='partial token';mut={param($c) $c.witness.inputs[0].lexeme='1';$c.witness.inputs[0].length=1}},
    @{label='invalid source';mut={param($c) $c.segments[0].role='CLAIM'}},
    @{label='duplicate name';mut={param($c) $c.witness.inputs[1].name='a'}},
    @{label='overlap';mut={param($c) $c.witness.inputs[1].source_id=$c.witness.inputs[0].source_id;$c.witness.inputs[1].start=$c.witness.inputs[0].start;$c.witness.inputs[1].length=$c.witness.inputs[0].length;$c.witness.inputs[1].lexeme=$c.witness.inputs[0].lexeme}},
    @{label='ambiguous source';mut={param($c) $c.segments+=@($c.segments[0])}},
    @{label='invalid offset';mut={param($c) $c.witness.inputs[0].start=-1}},
    @{label='unsupported relation';mut={param($c) $c.witness.relation='APPROX'}},
    @{label='unsupported operation';mut={param($c) $c.witness.operation='EXEC'}},
    @{label='string offset';mut={param($c) $c.witness.inputs[0].start='3'}}
)
foreach($t in $bad){
    $c=New-WitnessCase 'COMPARE' ([ordered]@{a='12';b='4'}) 'GT'
    & $t.mut $c
    $r=Invoke-LfoG2DeterministicWitness $c -TrustedBinding
    Assert-Witness ($r.state -ceq 'INVALID' -and $null -eq $r.results) ('Accepted invalid binding: '+$t.label);$checks++
}
foreach($literal in @('1,5','1e3','NaN','99999999999999999999999999999')){
    $c=New-WitnessCase 'COMPARE' ([ordered]@{a=$literal;b='1'}) 'GT'
    $r=Invoke-LfoG2DeterministicWitness $c -TrustedBinding
    Assert-Witness ($r.state -ceq 'INVALID') ('Accepted invalid numeric literal: '+$literal);$checks++
}
$c=New-WitnessCase 'PREDICTIVE_VALUE' ([ordered]@{prevalence_pct='0';sensitivity_pct='90';specificity_pct='100'})
$r=Invoke-LfoG2DeterministicWitness $c -TrustedBinding
Assert-Witness ($r.state -ceq 'INVALID') 'Undefined PPV accepted';$checks++
$c=New-WitnessCase 'COST_PER_SUCCESS' ([ordered]@{a_cost='1';a_success='0';b_cost='2';b_success='1'})
$r=Invoke-LfoG2DeterministicWitness $c -TrustedBinding
Assert-Witness ($r.state -ceq 'INVALID') 'Division by zero accepted';$checks++
Write-Host "UNIT PASS $checks/$checks"
$times=New-Object 'System.Collections.Generic.List[double]'
for($i=0;$i -lt $Repeat;$i++){
    foreach($item in $bank){
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $r=Invoke-LfoG2DeterministicWitness $item.c -TrustedBinding
        $sw.Stop()
        Assert-Witness ($r.state -ceq 'COMPUTED' -and (& $item.check $r)) 'Repeated witness mismatch'
        $times.Add($sw.Elapsed.TotalMilliseconds)
    }
}
$sorted=@($times.ToArray()|Sort-Object)
$median=if($sorted.Count%2){$sorted[[int][Math]::Floor($sorted.Count/2)]}else{($sorted[$sorted.Count/2-1]+$sorted[$sorted.Count/2])/2}
Write-Host ("P77 WITNESS PASS; operations=9; warm_calls={0}; mean_ms={1:N3}; median_ms={2:N3}; max_ms={3:N3}; model_calls=0; db_writes=0" -f $times.Count,($times|Measure-Object -Average).Average,$median,$sorted[-1])
