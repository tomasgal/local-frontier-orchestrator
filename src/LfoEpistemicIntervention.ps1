# L4-P2 bounded intervention adapter over frozen P1 Policy Capsules.
# Default OFF. Pure mapping only: no model call, store access, answer rewrite, or persistence.

function Get-LfoP2Sha256File {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-LfoEpistemicIntervention {
    param(
        [Parameter(Mandatory)]$PolicyCapsule,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedPolicyRulesSha256,
        [switch]$Enabled,
        [string]$MapPath=(Join-Path $PSScriptRoot '../config/L4P2Intervention.map.json'),
        [string]$LockPath=(Join-Path $PSScriptRoot '../config/L4P2Intervention.lock.json')
    )
    if([string]$PolicyCapsule.Schema -cne 'lfo-l4-p1-policy-capsule-v1'){throw 'P2 accepts only P1 policy capsules.'}
    if([string]$PolicyCapsule.PolicyVersion -cne '1.0.0'){throw 'P2 requires P1 policy version 1.0.0.'}
    if([string]$PolicyCapsule.PolicyRulesSha256 -cne $ExpectedPolicyRulesSha256){throw 'P2 capsule rules identity differs from the compatibility-verified frozen P1 rules bytes.'}

    $map=Get-Content -Raw -LiteralPath $MapPath -Encoding UTF8|ConvertFrom-Json
    $lock=Get-Content -Raw -LiteralPath $LockPath -Encoding UTF8|ConvertFrom-Json
    if([string]$map.schema -cne 'lfo-l4-p2-intervention-map-v1' -or [string]$map.status -cne 'frozen_for_acceptance'){throw 'Invalid or unfrozen P2 intervention map.'}
    if([string]$lock.schema -cne 'lfo-l4-p2-intervention-lock-v1' -or -not [bool]$lock.locked_before_acceptance){throw 'Invalid P2 intervention lock.'}
    $hash=Get-LfoP2Sha256File $MapPath
    if($hash -cne [string]$lock.map_sha256){throw 'P2 intervention map differs from its pre-acceptance lock.'}

    $decision=[string]$PolicyCapsule.Decision
    $allowed=@('NO_ACTION','REVIEW_FRAMING','REQUEST_COUNTEREVIDENCE','INCREASE_UNCERTAINTY_EXPLICITNESS','CHECK_REINFORCEMENT_PATTERN')
    if($decision -notin $allowed){throw 'Unsupported P1 decision for P2.'}

    if(-not $Enabled -or $decision -ceq 'NO_ACTION'){
        return [pscustomobject][ordered]@{
            Schema='lfo-l4-p2-intervention-v1';Enabled=$false;PolicyDecision=$decision
            PolicyRulesSha256=$ExpectedPolicyRulesSha256
            InterventionVersion=[string]$map.intervention_version;InterventionMapSha256=$hash
            Instruction='';MutatesAnswer=$false;PersistentState=$false
        }
    }

    $instruction=[string]$map.decisions.$decision
    if([string]::IsNullOrWhiteSpace($instruction)){throw 'Active P2 decision has no frozen intervention instruction.'}
    return [pscustomobject][ordered]@{
        Schema='lfo-l4-p2-intervention-v1';Enabled=$true;PolicyDecision=$decision
        PolicyRulesSha256=$ExpectedPolicyRulesSha256
        InterventionVersion=[string]$map.intervention_version;InterventionMapSha256=$hash
        Instruction=$instruction;MutatesAnswer=$false;PersistentState=$false
    }
}
