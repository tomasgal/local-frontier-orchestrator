# L4-P2 bounded intervention adapter over frozen P1 Policy Capsules.
# Default OFF. Pure mapping only: no model call, store access, answer rewrite, or persistence.

function Get-LfoP2Digest {
    param([byte[]]$Bytes,[ValidateSet('SHA256','SHA1')][string]$Algorithm='SHA256')
    $hasher=[Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    try{return ([BitConverter]::ToString($hasher.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}
    finally{$hasher.Dispose()}
}

function Get-LfoP2MapIntegrity {
    param([Parameter(Mandatory)][string]$MapPath,[Parameter(Mandatory)][string]$LockPath,
        [string]$CompatibilityPath=(Join-Path $PSScriptRoot '../config/L4P2Integrity.compatibility-v1.json'))
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $bytes=[IO.File]::ReadAllBytes($MapPath)
    $text=$utf8.GetString($bytes)
    if($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF){$text=$text.Substring(1)}
    # Normalize representation only. Do not trim/reformat JSON or its instructions.
    $canonical=$text.Replace("`r`n","`n")
    $canonicalBytes=$utf8.GetBytes($canonical)
    $lock=[IO.File]::ReadAllText($LockPath,$utf8)|ConvertFrom-Json
    $contract=[IO.File]::ReadAllText($CompatibilityPath,$utf8)|ConvertFrom-Json
    if($contract.schema -cne 'lfo-l4-p2-integrity-compatibility-v1' -or $contract.version -cne '1.0.0' -or
       $contract.canonicalization -cne 'utf8-optional-bom-crlf-to-lf-v1' -or
       $contract.historical_serialization -cne 'crlf-internal-final-lf-v1'){
        throw 'Unsupported P2 integrity compatibility contract.'
    }
    if($contract.frozen_tag -cne 'v9.6-l4-p2-frozen' -or
       $contract.frozen_commit -cne 'e648bba1201db639244b120b5f5db74e0c6f4059'){
        throw 'P2 integrity contract must bind the accepted frozen checkpoint.'
    }
    if($lock.schema -cne 'lfo-l4-p2-intervention-lock-v1' -or $lock.locked_before_acceptance -isnot [bool] -or -not $lock.locked_before_acceptance){throw 'Invalid P2 intervention lock.'}
    $canonicalHash=Get-LfoP2Digest $canonicalBytes
    if($canonicalHash -cne $contract.canonical_map_sha256){throw 'P2 canonical map differs from its compatibility contract.'}
    $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$canonicalBytes.Length+[char]0))
    $blobHash=Get-LfoP2Digest ([byte[]]($header+$canonicalBytes)) SHA1
    if($blobHash -cne $contract.frozen_map_git_blob){throw 'P2 map differs from its frozen Git blob.'}
    if(-not $canonical.EndsWith("`n")){throw 'P2 canonical map must retain its final LF.'}
    # Recover the exact accepted artifact bytes: PS5 ConvertTo-Json CRLF lines
    # followed by the writer's appended single LF. This is not a new lock.
    $historical=$canonical.Substring(0,$canonical.Length-1).Replace("`n","`r`n")+"`n"
    $historicalHash=Get-LfoP2Digest ($utf8.GetBytes($historical))
    if($historicalHash -cne $contract.historical_map_sha256 -or $historicalHash -cne $lock.map_sha256){throw 'P2 reconstructed artifact differs from its pre-acceptance lock.'}
    $map=$canonical|ConvertFrom-Json
    if($map.schema -cne 'lfo-l4-p2-intervention-map-v1' -or $map.status -cne 'frozen_for_acceptance'){throw 'Invalid or unfrozen P2 intervention map.'}
    if($map.intervention_version -cne $lock.intervention_version -or $map.intervention_version -cne $contract.intervention_version){throw 'P2 map/lock/compatibility version mismatch.'}
    return [pscustomobject]@{
        Map=$map;HistoricalSha256=$historicalHash;CanonicalSha256=$canonicalHash
        FileSha256=(Get-LfoP2Digest $bytes);GitBlob=$blobHash;Contract=$contract.schema
    }
}

function Get-LfoEpistemicIntervention {
    param(
        [Parameter(Mandatory)]$PolicyCapsule,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{64}$')][string]$ExpectedPolicyRulesSha256,
        [switch]$Enabled,
        [string]$MapPath=(Join-Path $PSScriptRoot '../config/L4P2Intervention.map.json'),
        [string]$LockPath=(Join-Path $PSScriptRoot '../config/L4P2Intervention.lock.json'),
        [string]$CompatibilityPath=(Join-Path $PSScriptRoot '../config/L4P2Integrity.compatibility-v1.json')
    )
    if([string]$PolicyCapsule.Schema -cne 'lfo-l4-p1-policy-capsule-v1'){throw 'P2 accepts only P1 policy capsules.'}
    if([string]$PolicyCapsule.PolicyVersion -cne '1.0.0'){throw 'P2 requires P1 policy version 1.0.0.'}
    if([string]$PolicyCapsule.PolicyRulesSha256 -cne $ExpectedPolicyRulesSha256){throw 'P2 capsule rules identity differs from the compatibility-verified frozen P1 rules bytes.'}
    $identity=Get-LfoP2MapIntegrity -MapPath $MapPath -LockPath $LockPath -CompatibilityPath $CompatibilityPath
    $map=$identity.Map
    $decision=[string]$PolicyCapsule.Decision
    $allowed=@('NO_ACTION','REVIEW_FRAMING','REQUEST_COUNTEREVIDENCE','INCREASE_UNCERTAINTY_EXPLICITNESS','CHECK_REINFORCEMENT_PATTERN')
    if($decision -notin $allowed){throw 'Unsupported P1 decision for P2.'}
    $active=[bool]$Enabled -and $decision -cne 'NO_ACTION'
    $instruction=''
    if($active){
        $instruction=[string]$map.decisions.$decision
        if([string]::IsNullOrWhiteSpace($instruction)){throw 'Active P2 decision has no frozen intervention instruction.'}
    }
    return [pscustomobject][ordered]@{
        Schema='lfo-l4-p2-intervention-v1';Enabled=$active;PolicyDecision=$decision
        PolicyRulesSha256=$ExpectedPolicyRulesSha256
        InterventionVersion=[string]$map.intervention_version
        # Existing field identifies the recovered historical accepted artifact.
        InterventionMapSha256=$identity.HistoricalSha256
        InterventionMapFileSha256=$identity.FileSha256
        InterventionMapCanonicalSha256=$identity.CanonicalSha256
        InterventionMapGitBlob=$identity.GitBlob
        InterventionIntegrityContract=$identity.Contract
        Instruction=$instruction;MutatesAnswer=$false;PersistentState=$false
    }
}
