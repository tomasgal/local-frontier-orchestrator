# CES-C08 experimental plan-only composer, frozen P22 shapes.
# No model calls, writes, prompt mutation, learned coupling or automatic revision.
# Eligibility attestations are supplied by the trusted caller, not by model text.
. (Join-Path $PSScriptRoot 'LfoG2FindingAggregation.ps1')
function New-LfoG2CesPlan {
    [CmdletBinding()]
    param([ValidateSet('S0','S1','S2','S3')][string]$RequestedShape='S0',
          [string]$ScopeId,[object[]]$Findings=@(),$Eligibility,[switch]$TrustedEnvelope)
    $out=[ordered]@{contract='g2-ces-plan-v1';state='ABSTAIN';reason='UNTRUSTED_ENVELOPE';requested_shape=$RequestedShape;selected_shape='S0';operators=@();inhibited=@();review_targets=@();aggregation=$null;extra_model_calls=0;execution='PLAN_ONLY';production_enabled=$false}
    if(-not $TrustedEnvelope){return [pscustomobject]$out}
    $agg=Merge-LfoG2Findings $ScopeId $Findings -TrustedEnvelope
    $out.aggregation=$agg
    if($agg.state -cne 'AGGREGATED'){$out.reason='INVALID_FINDINGS';return [pscustomobject]$out}
    $out.review_targets=@(foreach($g in $agg.groups){
        if($g.eligibility -ceq 'REVIEW_FOR_INTERVENTION'){
            [pscustomobject]@{target_ref=$g.target_ref;invariant=$g.invariant;state=$g.state}
        }
    })
    $allowed=@{
        S0=@()
        S1=@('MASK_CONTEXT','PRESERVE_SUPPORT')
        S2=@('PRESERVE_SUPPORT','SCOPE_BIND')
        S3=@('MASK_CONTEXT','PRESERVE_SUPPORT','SCOPE_BIND')
    }
    # Only subsets of the requested frozen shape may be selected.
    # No automatic activation from a finding or an axis.
    $preference=switch -CaseSensitive ($RequestedShape){
        'S0'{@('S0')}
        'S1'{@('S1','S0')}
        'S2'{@('S2','S0')}
        'S3'{@('S3','S2','S1','S0')}
    }
    if($RequestedShape -ceq 'S0'){
        $out.state='PLANNED';$out.reason='REFERENCE';return [pscustomobject]$out
    }
    foreach($op in $allowed[$RequestedShape]){
        if($null -eq $Eligibility -or $Eligibility.$op -isnot [bool] -or -not $Eligibility.$op){
            $out.inhibited+= $op
        }
    }
    foreach($shape in $preference){
        $blocked=@($allowed[$shape]|Where-Object {$_ -cin $out.inhibited})
        if($blocked.Count -eq 0){
            $out.selected_shape=$shape
            $out.operators=@($allowed[$shape])
            break
        }
    }
    $out.state='PLANNED'
    $out.reason=if($out.selected_shape -ceq $RequestedShape){'REQUESTED_SHAPE_ELIGIBLE'}else{'FALLBACK_TO_FROZEN_SUBSET'}
    return [pscustomobject]$out
}
