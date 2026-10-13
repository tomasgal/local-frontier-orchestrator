# L4-P1 rare-trigger Policy Capsule.
# Pure deterministic policy over bounded A2 summaries. Default OFF.
# No model calls, store writes, raw-history reads, prompt injection, or answer mutation.

function Get-LfoP1Sha256File {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Assert-LfoP1ExactProperties {
    param([Parameter(Mandatory)]$Object,[Parameter(Mandatory)][string[]]$Allowed,[Parameter(Mandatory)][string]$Name)
    $actual=@($Object.PSObject.Properties.Name|Sort-Object -Unique)
    $expected=@($Allowed|Sort-Object -Unique)
    if(($actual -join '|') -cne ($expected -join '|')){throw ($Name+' property set is not canonical.')}
}

function Assert-LfoP1SupportIds {
    param([object[]]$Ids,[string]$Name,[int]$Max=50)
    $a=@($Ids)
    if($a.Count -gt $Max){throw ($Name+' support exceeds bound.')}
    foreach($id in $a){if(([string]$id) -cnotmatch '^[a-f0-9]{32}$'){throw ($Name+' contains invalid observation ID.')}}
}

function ConvertTo-LfoP1Evidence {
    param([Parameter(Mandatory)]$A2Summary)
    if([string]$A2Summary.Schema -cne 'lfo-l4-a2-interaction-analytics-v1'){throw 'P1 adapter accepts only the frozen A2 interaction summary schema.'}
    $rec=@()
    foreach($r in @($A2Summary.RecurrenceDensity)){
        $rec += [pscustomobject][ordered]@{
            signature_kind=[string]$r.signature_kind
            signature=[string]$r.signature
            occurrence_count=[int]$r.occurrence_count
            distinct_turn_count=[int]$r.distinct_turn_count
            window_turn_count=[int]$r.window_turn_count
            annotated_turn_count=[int]$r.annotated_turn_count
            distinct_turn_fraction=[double]$r.distinct_turn_fraction
            supporting_observation_ids=@($r.supporting_observation_ids)
        }
    }
    $bal=@()
    foreach($r in @($A2Summary.ResponseBalance)){
        $bal += [pscustomobject][ordered]@{
            actor=[string]$r.actor
            linked_response_count=[int]$r.linked_response_count
            reinforced_count=[int]$r.reinforced_count
            challenged_count=[int]$r.challenged_count
            corrected_count=[int]$r.corrected_count
            ignored_count=[int]$r.ignored_count
            reinforced_fraction=[double]$r.reinforced_fraction
            challenged_fraction=[double]$r.challenged_fraction
            corrected_fraction=[double]$r.corrected_fraction
            ignored_fraction=[double]$r.ignored_fraction
            supporting_observation_ids=@($r.supporting_observation_ids)
        }
    }
    return [pscustomobject][ordered]@{
        Schema='lfo-l4-p1-policy-evidence-v1'
        SourceSchema=[string]$A2Summary.Schema
        StoreId=[string]$A2Summary.StoreId
        Epoch=[int]$A2Summary.Epoch
        FirstTurn=[int]$A2Summary.FirstTurn
        LastTurn=[int]$A2Summary.LastTurn
        WindowTurnCount=[int]$A2Summary.WindowTurnCount
        RecurrenceDensity=$rec
        ResponseBalance=$bal
    }
}

function Assert-LfoP1Evidence {
    param([Parameter(Mandatory)]$Evidence)
    Assert-LfoP1ExactProperties $Evidence @('Schema','SourceSchema','StoreId','Epoch','FirstTurn','LastTurn','WindowTurnCount','RecurrenceDensity','ResponseBalance') 'Evidence'
    if([string]$Evidence.Schema -cne 'lfo-l4-p1-policy-evidence-v1'){throw 'Invalid P1 evidence schema.'}
    if([string]$Evidence.SourceSchema -cne 'lfo-l4-a2-interaction-analytics-v1'){throw 'Invalid P1 source summary schema.'}
    if([string]$Evidence.StoreId -cnotmatch '^[a-f0-9]{32}$'){throw 'Invalid P1 store ID.'}
    if([int]$Evidence.Epoch -lt 1 -or [int]$Evidence.FirstTurn -lt 1 -or [int]$Evidence.LastTurn -lt [int]$Evidence.FirstTurn){throw 'Invalid P1 window.'}
    if([int]$Evidence.WindowTurnCount -ne ([int]$Evidence.LastTurn-[int]$Evidence.FirstTurn+1)){throw 'P1 window count mismatch.'}
    if(@($Evidence.RecurrenceDensity).Count -gt 100){throw 'P1 recurrence surface exceeds bound.'}
    if(@($Evidence.ResponseBalance).Count -gt 10){throw 'P1 response-balance surface exceeds bound.'}

    foreach($r in @($Evidence.RecurrenceDensity)){
        Assert-LfoP1ExactProperties $r @('signature_kind','signature','occurrence_count','distinct_turn_count','window_turn_count','annotated_turn_count','distinct_turn_fraction','supporting_observation_ids') 'Recurrence row'
        if([string]$r.signature_kind -notin @('actor_type','linked_response')){throw 'Unsupported P1 recurrence signature kind.'}
        if([int]$r.occurrence_count -lt 0 -or [int]$r.distinct_turn_count -lt 0 -or [int]$r.distinct_turn_count -gt [int]$Evidence.WindowTurnCount){throw 'Invalid P1 recurrence counts.'}
        if([int]$r.window_turn_count -ne [int]$Evidence.WindowTurnCount){throw 'P1 recurrence window mismatch.'}
        if([double]$r.distinct_turn_fraction -lt 0 -or [double]$r.distinct_turn_fraction -gt 1){throw 'Invalid P1 recurrence fraction.'}
        Assert-LfoP1SupportIds @($r.supporting_observation_ids) 'Recurrence row' 50
    }

    foreach($r in @($Evidence.ResponseBalance)){
        Assert-LfoP1ExactProperties $r @('actor','linked_response_count','reinforced_count','challenged_count','corrected_count','ignored_count','reinforced_fraction','challenged_fraction','corrected_fraction','ignored_fraction','supporting_observation_ids') 'Response row'
        if([string]$r.actor -notin @('USER','LOCAL','FRONTIER','FINAL')){throw 'Invalid P1 response actor.'}
        foreach($p in @('linked_response_count','reinforced_count','challenged_count','corrected_count','ignored_count')){if([int]$r.$p -lt 0){throw 'Invalid P1 response count.'}}
        foreach($p in @('reinforced_fraction','challenged_fraction','corrected_fraction','ignored_fraction')){if([double]$r.$p -lt 0 -or [double]$r.$p -gt 1){throw 'Invalid P1 response fraction.'}}
        Assert-LfoP1SupportIds @($r.supporting_observation_ids) 'Response row' 50
    }
}

function Get-LfoP1Digest {
    param([Parameter(Mandatory)][byte[]]$Bytes,[ValidateSet('SHA256','SHA1')][string]$Algorithm='SHA256')
    $hasher=[Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    try{return ([BitConverter]::ToString($hasher.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}
    finally{$hasher.Dispose()}
}

function Get-LfoP1Rules {
    param(
        [string]$RulesPath=(Join-Path $PSScriptRoot '../config/L4P1Policy.rules.json'),
        [string]$LockPath=(Join-Path $PSScriptRoot '../config/L4P1Policy.lock.json'),
        [string]$CompatibilityPath=''
    )
    $lock=(Get-Content -Raw -LiteralPath $LockPath -Encoding UTF8|ConvertFrom-Json)
    if([string]$lock.schema -cne 'lfo-l4-p1-policy-lock-v1' -or -not [bool]$lock.locked_before_acceptance){throw 'Invalid P1 policy lock.'}

    # Historical frozen behavior remains the default path.
    if([string]::IsNullOrWhiteSpace($CompatibilityPath)){
        $rules=(Get-Content -Raw -LiteralPath $RulesPath -Encoding UTF8|ConvertFrom-Json)
        if([string]$rules.schema -cne 'lfo-l4-p1-policy-rules-v1' -or [string]$rules.status -cne 'frozen_for_acceptance'){throw 'Invalid or unfrozen P1 rules.'}
        $hash=Get-LfoP1Sha256File $RulesPath
        if($hash -cne [string]$lock.rules_sha256){throw 'P1 rule hash differs from the pre-acceptance lock.'}
        return [pscustomobject]@{Rules=$rules;RulesSha256=$hash;IntegrityContract='historical-lock'}
    }

    # Explicit compatibility mode binds the immutable P1 checkpoint by
    # frozen commit + Git blob + canonical LF bytes without rewriting the
    # historically incorrect pre-acceptance byte hash.
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $bytes=[IO.File]::ReadAllBytes($RulesPath)
    $text=$utf8.GetString($bytes)
    if($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF){$text=$text.Substring(1)}
    $canonical=$text.Replace(([string][char]13+[char]10),[string][char]10)
    $canonicalBytes=$utf8.GetBytes($canonical)
    $contract=[IO.File]::ReadAllText($CompatibilityPath,$utf8)|ConvertFrom-Json
    if([string]$contract.schema -cne 'lfo-l4-p1-integrity-compatibility-v1' -or
       [string]$contract.version -cne '1.0.0' -or
       [string]$contract.canonicalization -cne 'utf8-optional-bom-crlf-to-lf-v1'){
        throw 'Unsupported P1 integrity compatibility contract.'
    }
    if([string]$contract.frozen_tag -cne 'v9.6-l4-p1-frozen' -or
       [string]$contract.frozen_commit -cne '28c0ba622761b03af445a8e08939b38396926e0c'){
        throw 'P1 integrity contract must bind the accepted frozen checkpoint.'
    }
    if([string]$lock.rules_sha256 -cne [string]$contract.historical_declared_rules_sha256){
        throw 'Historical P1 lock differs from the compatibility contract.'
    }
    $canonicalHash=Get-LfoP1Digest $canonicalBytes
    if($canonicalHash -cne [string]$contract.canonical_rules_sha256){
        throw 'P1 canonical rules differ from the compatibility contract.'
    }
    $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$canonicalBytes.Length+[char]0))
    $blobHash=Get-LfoP1Digest ([byte[]]($header+$canonicalBytes)) SHA1
    if($blobHash -cne [string]$contract.frozen_rules_git_blob){
        throw 'P1 rules differ from the frozen Git blob.'
    }
    $rules=$canonical|ConvertFrom-Json
    if([string]$rules.schema -cne 'lfo-l4-p1-policy-rules-v1' -or [string]$rules.status -cne 'frozen_for_acceptance'){
        throw 'Invalid or unfrozen P1 rules.'
    }
    return [pscustomobject]@{
        Rules=$rules
        RulesSha256=$canonicalHash
        GitBlob=$blobHash
        IntegrityContract=[string]$contract.schema
    }
}

function Test-LfoP1Condition {
    param([Parameter(Mandatory)]$Evidence,[Parameter(Mandatory)]$Condition)
    if([string]$Condition.source -ceq 'recurrence'){
        $rows=@($Evidence.RecurrenceDensity|Where-Object{[string]$_.signature_kind -ceq [string]$Condition.signature_kind -and [string]$_.signature -ceq [string]$Condition.signature})
        if($rows.Count -ne 1){return [pscustomobject]@{Matched=$false;Support=@();Descriptor=$null}}
        $r=$rows[0]
        $ok=([int]$r.occurrence_count -ge [int]$Condition.min_occurrence_count -and [int]$r.distinct_turn_count -ge [int]$Condition.min_distinct_turn_count -and [double]$r.distinct_turn_fraction -ge [double]$Condition.min_distinct_turn_fraction)
        $d=[pscustomobject][ordered]@{source='RecurrenceDensity';signature_kind=[string]$r.signature_kind;signature=[string]$r.signature;occurrence_count=[int]$r.occurrence_count;distinct_turn_count=[int]$r.distinct_turn_count;distinct_turn_fraction=[double]$r.distinct_turn_fraction}
        return [pscustomobject]@{Matched=$ok;Support=@($r.supporting_observation_ids);Descriptor=$d}
    }
    throw 'Unsupported P1 rule condition source.'
}

function Get-LfoEpistemicPolicyCapsule {
    param(
        [Parameter(Mandatory)]$Evidence,
        [switch]$Enabled,
        [string]$RulesPath=(Join-Path $PSScriptRoot '../config/L4P1Policy.rules.json'),
        [string]$LockPath=(Join-Path $PSScriptRoot '../config/L4P1Policy.lock.json'),
        [string]$CompatibilityPath=''
    )
    Assert-LfoP1Evidence $Evidence
    $bundle=Get-LfoP1Rules -RulesPath $RulesPath -LockPath $LockPath -CompatibilityPath $CompatibilityPath
    $rules=$bundle.Rules

    $window=[pscustomobject][ordered]@{StoreId=[string]$Evidence.StoreId;Epoch=[int]$Evidence.Epoch;FirstTurn=[int]$Evidence.FirstTurn;LastTurn=[int]$Evidence.LastTurn}
    if(-not $Enabled){
        return [pscustomobject][ordered]@{
            Schema='lfo-l4-p1-policy-capsule-v1';PolicyVersion=[string]$rules.policy_version;PolicyRulesSha256=[string]$bundle.RulesSha256
            Enabled=$false;Decision='NO_ACTION';PolicyRuleId='';PolicyRuleVersion='';ReasonCode='DEFAULT_OFF';Window=$window
            MatchedEvidence=@();SupportingObservationIds=@()
            Interpretation='Offline policy recommendation only; not a diagnosis, user trait, detector result, answer rewrite, or intervention effect.'
        }
    }

    $matches=@()
    foreach($rule in @($rules.rules|Sort-Object @{Expression={[int]$_.priority}},@{Expression={[string]$_.id}})){
        $all=$true;$supports=New-Object System.Collections.ArrayList;$descriptors=New-Object System.Collections.ArrayList
        foreach($c in @($rule.all)){
            $m=Test-LfoP1Condition -Evidence $Evidence -Condition $c
            if(-not $m.Matched){$all=$false;break}
            foreach($id in @($m.Support)){[void]$supports.Add([string]$id)}
            [void]$descriptors.Add($m.Descriptor)
        }
        if($all){$matches += [pscustomobject]@{Rule=$rule;Support=@($supports);Descriptors=@($descriptors)}}
    }

    if(-not $matches.Count){
        return [pscustomobject][ordered]@{
            Schema='lfo-l4-p1-policy-capsule-v1';PolicyVersion=[string]$rules.policy_version;PolicyRulesSha256=[string]$bundle.RulesSha256
            Enabled=$true;Decision='NO_ACTION';PolicyRuleId='';PolicyRuleVersion='';ReasonCode='NO_FROZEN_RULE_MATCH';Window=$window
            MatchedEvidence=@();SupportingObservationIds=@()
            Interpretation='Offline policy recommendation only; not a diagnosis, user trait, detector result, answer rewrite, or intervention effect.'
        }
    }

    $selected=$matches[0]
    $limit=[int]$rules.max_support_ids
    $support=@($selected.Support|Sort-Object -Unique|Select-Object -First $limit)
    return [pscustomobject][ordered]@{
        Schema='lfo-l4-p1-policy-capsule-v1';PolicyVersion=[string]$rules.policy_version;PolicyRulesSha256=[string]$bundle.RulesSha256
        Enabled=$true;Decision=[string]$selected.Rule.output;PolicyRuleId=[string]$selected.Rule.id;PolicyRuleVersion=[string]$selected.Rule.version
        ReasonCode=[string]$selected.Rule.reason_code;Window=$window;MatchedEvidence=@($selected.Descriptors);SupportingObservationIds=$support
        Interpretation='Offline policy recommendation only; not a diagnosis, user trait, detector result, answer rewrite, or intervention effect.'
    }
}
