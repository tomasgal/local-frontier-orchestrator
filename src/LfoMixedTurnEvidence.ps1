# v9.4-dev5 experimental pure source-of-evidence validator.
# This deliberately narrow recognizer is NOT wired into runtime persistence.
# It never reads L0/L1/L2, logs, model responses or global conversation state.
# Unsupported or ambiguous language fails closed; no inferred updates.
function Get-LfoMixedUserRamEvidence([string]$CurrentUserPrompt) {
    $none = [pscustomobject]@{
        Status = 'not-eligible'
        Reason = 'no-exact-mixed-ram-assertion'
        EvidenceText = ''
        EvidenceStart = -1
        EvidenceLength = 0
        ParsedOps = [pscustomobject]@{Valid=@();Rejected=@()}
    }
    if ([string]::IsNullOrWhiteSpace($CurrentUserPrompt)) { return $none }

    # Entire message must be a single exact OS question followed by one
    # explicit first-party RAM claim. No excerpts/quotes, logs, or additional
    # directives may surround it. Named capture's Index anchors provenance.
    $pattern = '^\s*What\s+(?:OS|operating\s+system)\s+does\s+(?<subject>[A-Z][A-Z0-9_-]{2,39})\s+run\?\s+Also,\s+(?<claim>(?<claimSubject>[A-Z][A-Z0-9_-]{2,39})\s+RAM\s+is\s+now\s+(?<gb>[0-9]{1,7})\s+GB\.?)\s*$'
    $m = [regex]::Match($CurrentUserPrompt,$pattern,
        [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if (-not $m.Success) { return $none }

    $subject = [string]$m.Groups['subject'].Value
    $claimSubject = [string]$m.Groups['claimSubject'].Value
    if (-not [string]::Equals($subject,$claimSubject,[StringComparison]::Ordinal)) {
        $none.Reason = 'subject-mismatch'
        return $none
    }
    $ram = [int64]0
    if (-not [int64]::TryParse([string]$m.Groups['gb'].Value,
        [Globalization.NumberStyles]::None,
        [Globalization.CultureInfo]::InvariantCulture,[ref]$ram) -or
        $ram -lt 1 -or $ram -gt 1048576) {
        $none.Reason = 'ram-value-out-of-range'
        return $none
    }
    $claim = $m.Groups['claim']
    $span = $CurrentUserPrompt.Substring($claim.Index,$claim.Length)
    if (-not [string]::Equals($span,[string]$claim.Value,
        [StringComparison]::Ordinal)) {
        throw 'Internal source-span mismatch'
    }

    $raw = [pscustomobject]@{
        op = 'SET_INTEGER'
        subject = $subject
        subject_type = 'server'
        predicate = 'ram_gb'
        target = $ram.ToString([Globalization.CultureInfo]::InvariantCulture)
        target_entity_type = ''
    }
    $parsed = ConvertFrom-LfoStructuredMemoryOps -RawOps @($raw) -MaxOps 1
    if (@($parsed.Valid).Count -ne 1 -or
        @($parsed.Rejected).Count -ne 0 -or
        [int64]$parsed.Valid[0].TypedValue -ne $ram) {
        throw 'Canonical current-user RAM evidence failed structured contract'
    }
    return [pscustomobject]@{
        Status = 'accepted'
        Reason = 'explicit-current-user-ram-assertion'
        EvidenceText = $span
        EvidenceStart = $claim.Index
        EvidenceLength = $claim.Length
        ParsedOps = $parsed
    }
}
