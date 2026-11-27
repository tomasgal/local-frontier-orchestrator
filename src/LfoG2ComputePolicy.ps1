# Experimental, shadow-only compute recommendation and bounded pre-generation E4 intervention.
# No change to model, context, think, memory policy or generation cap.
function Get-LfoG2ComputeRecommendation {
    param([string]$Prompt,[int]$PriorTurns,[bool]$Thinking,[string]$PreviousClass)
    $t=ConvertTo-LfoG2NormalizedText $Prompt
    $continuation=($t -match '^(?:continue|go on|next|proceed|pokračuj|pokracuj|dalej|dalsi|dalsie|ano|yes|ok|then what|co dalej)\b' -or ($PriorTurns -gt 0 -and $t.Length -le 40))
    $complex=($t.Length -ge 600 -or $t -match '\b(?:analy[sz]e|analysis|compare|design|architecture|evaluate|assess|methodolog\w*|implement\w*|analyz\w*|porovnaj|navrhni|architektur\w*|posud|vyhodnot)\b')
    if($Thinking){$class='DEEP';$reason='USER_THINKING'}
    elseif($complex){$class='DEEP';$reason='COMPLEX_REQUEST'}
    elseif($PriorTurns -gt 0 -and $PreviousClass -eq 'DEEP'){$class='DEEP';$reason='SESSION_CONTINUITY'}
    elseif($continuation -and $PriorTurns -gt 0){$class='STANDARD';$reason='FOLLOWUP_CONTINUITY'}
    elseif($PriorTurns -eq 0 -and $t.Length -le 80 -and $t -match '^(?:what is|define|translate|co je|definuj|preloz)\b'){$class='FAST';$reason='SHORT_STANDALONE_CANDIDATE'}
    else{$class='STANDARD';$reason='DEFAULT'}
    [pscustomobject]@{recommendation=$class;reason=$reason;continuation=[bool]$continuation}
}
function Get-LfoG2InterventionPlan {
    param($Controller,[string]$Prompt,[string]$Route,[bool]$Requested)
    $out=[ordered]@{requested=$Requested;eligible=$false;signal=$null;rule=$null;decision='DISABLED';instruction=''}
    if(-not $Requested){return [pscustomobject]$out}
    $out.decision='INELIGIBLE'
    if($null -eq $Controller -or $Controller.Mode -notin @('OBSERVE','INTERVENE') -or ($Route -ne 'LOCAL' -and -not ($Controller.Mode -eq 'INTERVENE' -and $Route -eq 'AUTO')) -or $Controller.Axes.E4 -eq 'OFF'){return [pscustomobject]$out}
    $m=$Controller.Modules['confirmation-seeking']
    if($null -eq $m -or -not $m.Enabled){return [pscustomobject]$out}
    $ctx=[pscustomobject]@{Text=$Prompt;ExternalEvidence='UNKNOWN';Route=$Route;Stage='USER'}
    $r=@(& $m.Run $ctx $Controller.Axes.E4)
    if($r.Count -ne 1 -or $r[0] -is [string] -or $r[0].Assessment -cne 'OBSERVED_SIGNAL' -or $r[0].Phenomenon -cne 'CONFIRMATION_SEEKING'){
        $out.decision='NO_DEFINITE_SIGNAL';return [pscustomobject]$out
    }
    $out.eligible=$true;$out.signal=$r[0].Phenomenon;$out.rule=$r[0].RuleId;$out.decision='PLANNED'
    $out.instruction='Epistemic safeguard: distinguish the requested position from what the evidence supports. Include material counterevidence and uncertainty when needed for a sound conclusion; do not invent evidence or force disagreement. Preserve the requested task and language.'
    [pscustomobject]$out
}
function Add-LfoG2RequestSafeguard {
    param([object[]]$Messages,$Plan)
    if($null -eq $Plan -or -not $Plan.eligible -or -not $Plan.instruction){return $Messages}
    if($Messages.Count -lt 1 -or [string]$Messages[0].role -ne 'system'){throw 'Expected system message for G2 safeguard.'}
    # Copy only the first message; never mutate the stored history or user message.
    $copy=@($Messages)
    $copy[0]=@{role='system';content=([string]$Messages[0].content+[Environment]::NewLine+[Environment]::NewLine+$Plan.instruction)}
    return $copy
}
