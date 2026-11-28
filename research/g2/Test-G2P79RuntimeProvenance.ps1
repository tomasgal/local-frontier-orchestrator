[CmdletBinding()]
param([ValidateRange(1,1000)][int]$Repeat=100)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../src/LfoG2RuntimeProvenance.ps1')
function New-P79Event([string]$Id='e1',[string]$Operation='read',[string]$Target='doc:1',[string]$Status='SUCCEEDED',[string]$Actor='assistant',[string]$Turn='t1'){
    @{event_id=$Id;turn_id=$Turn;actor=$Actor;operation=$Operation;target=$Target;status=$Status;receipt_ref='receipt:1'}
}
function New-P79Runtime([bool]$Complete=$true,[object[]]$Events=@()){
    @{turn_id='t1';complete=$Complete;events=$Events}
}
function New-P79Claim([string]$Kind='SUCCESS_ASSERTION',[string]$Operation='read',[string]$Target='doc:1',[string]$Actor='assistant',[string]$Turn='t1'){
    @{kind=$Kind;turn_id=$Turn;actor=$Actor;operation=$Operation;target=$Target}
}
function Assert-P79([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message}}
$claim=New-P79Claim
$ok=New-P79Event
$failed=New-P79Event -Status FAILED
$pending=New-P79Event -Status PENDING
$badReceipt=New-P79Event;$badReceipt.receipt_ref=''
$badStatus=New-P79Event -Status 'UNKNOWN'
$badType=New-P79Runtime;$badType.complete='true'
$bank=@(
    @{n='empty complete';r=(New-P79Runtime);c=$claim;s='CONTRADICTED'},
    @{n='empty incomplete';r=(New-P79Runtime $false);c=$claim;s='UNKNOWN'},
    @{n='matching success';r=(New-P79Runtime $true @($ok));c=$claim;s='SUPPORTED_OPERATION'},
    @{n='matching success incomplete';r=(New-P79Runtime $false @($ok));c=$claim;s='SUPPORTED_OPERATION'},
    @{n='failed';r=(New-P79Runtime $true @($failed));c=$claim;s='CONTRADICTED'},
    @{n='failed incomplete';r=(New-P79Runtime $false @($failed));c=$claim;s='UNKNOWN'},
    @{n='pending';r=(New-P79Runtime $true @($pending));c=$claim;s='UNKNOWN'},
    @{n='wrong target';r=(New-P79Runtime $true @($ok));c=(New-P79Claim -Target 'doc:2');s='CONTRADICTED'},
    @{n='wrong operation';r=(New-P79Runtime $true @($ok));c=(New-P79Claim -Operation 'write');s='CONTRADICTED'},
    @{n='wrong actor';r=(New-P79Runtime $true @($ok));c=(New-P79Claim -Actor 'auditor');s='CONTRADICTED'},
    @{n='wrong turn';r=(New-P79Runtime $true @($ok));c=(New-P79Claim -Turn 't2');s='UNKNOWN'},
    @{n='protected or absent';r=(New-P79Runtime);c=(New-P79Claim -Kind NOT_APPLICABLE);s='NOT_APPLICABLE'},
    @{n='unclear assertion';r=(New-P79Runtime);c=(New-P79Claim -Kind UNKNOWN);s='UNKNOWN'},
    @{n='missing receipt';r=(New-P79Runtime $true @($badReceipt));c=$claim;s='INVALID'},
    @{n='wrong status';r=(New-P79Runtime $true @($badStatus));c=$claim;s='INVALID'},
    @{n='duplicate event id';r=(New-P79Runtime $true @($ok,$failed));c=$claim;s='INVALID'},
    @{n='foreign event turn';r=(New-P79Runtime $true @((New-P79Event -Turn 't2')));c=$claim;s='INVALID'},
    @{n='bad completeness type';r=$badType;c=$claim;s='INVALID'},
    @{n='success after failure';r=(New-P79Runtime $true @($failed,(New-P79Event -Id 'e2')));c=$claim;s='SUPPORTED_OPERATION'},
    @{n='case-sensitive target';r=(New-P79Runtime $true @($ok));c=(New-P79Claim -Target 'DOC:1');s='CONTRADICTED'},
    @{n='unbound target';r=(New-P79Runtime $true @($ok));c=(New-P79Claim -Target '');s='INVALID'},
    @{n='generic operation';r=(New-P79Runtime $true @((New-P79Event -Operation 'calculate' -Target 'calc:7')));c=(New-P79Claim -Operation 'calculate' -Target 'calc:7');s='SUPPORTED_OPERATION'}
)
$checks=0
foreach($t in $bank){
    $r=Resolve-LfoG2RuntimeProvenance $t.r $t.c -TrustedRuntime -TrustedBinding
    Assert-P79 ($r.state -ceq $t.s) ($t.n+': '+$r.state+' '+$r.reason);$checks++
}
$r=Resolve-LfoG2RuntimeProvenance (New-P79Runtime $true @($ok)) $claim -TrustedBinding
Assert-P79 ($r.state -ceq 'UNKNOWN' -and $r.reason -ceq 'UNVERIFIED_RUNTIME') 'Untrusted runtime accepted';$checks++
$r=Resolve-LfoG2RuntimeProvenance (New-P79Runtime $true @($ok)) $claim -TrustedRuntime
Assert-P79 ($r.state -ceq 'UNKNOWN' -and $r.reason -ceq 'UNVERIFIED_CLAIM_BINDING') 'Untrusted claim accepted';$checks++
$r=Resolve-LfoG2RuntimeProvenance (New-P79Runtime $true @($ok)) $claim -TrustedRuntime -TrustedBinding
Assert-P79 ($r.matched_events.Count -eq 1 -and $r.matched_events[0].receipt_ref -ceq 'receipt:1') 'Receipt linkage lost';$checks++
Write-Host "UNIT PASS $checks/$checks"
$times=New-Object 'System.Collections.Generic.List[double]'
for($i=0;$i -lt $Repeat;$i++){
    foreach($t in $bank){
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $r=Resolve-LfoG2RuntimeProvenance $t.r $t.c -TrustedRuntime -TrustedBinding
        $sw.Stop()
        Assert-P79 ($r.state -ceq $t.s) 'Repeated result changed'
        $times.Add($sw.Elapsed.TotalMilliseconds)
    }
}
$sorted=@($times.ToArray()|Sort-Object)
$median=if($sorted.Count%2){$sorted[[int][Math]::Floor($sorted.Count/2)]}else{($sorted[$sorted.Count/2-1]+$sorted[$sorted.Count/2])/2}
Write-Host ("P79 PROVENANCE PASS; warm_calls={0}; mean_ms={1:N3}; median_ms={2:N3}; max_ms={3:N3}; model_calls=0; db_writes=0" -f $times.Count,($times|Measure-Object -Average).Average,$median,$sorted[-1])
