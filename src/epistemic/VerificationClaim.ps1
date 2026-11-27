# V2: conservative sentence/span detection with explicit time-scope abstention.
# Evidence NONE is a contradiction only for a recognized CURRENT_TURN claim.
function Get-LfoG2VerificationClaim {
    param($Context,[string]$Sensitivity)
    $raw=[string]$Context.Text
    if([string]::IsNullOrWhiteSpace($raw) -or $raw.Length -gt 16000){return 'ABSTAIN'}
    # Do not interpret fenced code, quoted examples or markdown blockquotes.
    # This first implementation abstains on the entire answer when such syntax occurs.
    if($raw -match '(?m)^\s*(?:>|~~~|\x60{3,})' -or $raw -match '["\u2018-\u201f\u00ab\u00bb\x60]'){return 'ABSTAIN'}
    $all=ConvertTo-LfoG2NormalizedText $raw
    if($all -match '\b(?:fictional example|sample answer|example sentence|illustrative example|fiktivny priklad|ukazkov\w* odpoved)\b'){return 'ABSTAIN'}
    $explicit='(?:i\s+(?:checked|searched|verified)\s+(?:the\s+)?(?:web|internet|online sources?)|(?:overil|overila|skontroloval|skontrolovala|vyhladal|vyhladala)\s+som\s+(?:to\s+)?(?:na\s+internete|na\s+webe|online))'
    $expanded='(?:i\s+(?:looked it up online|consulted online sources|(?:have\s+)?(?:independently\s+)?confirmed\s+(?:this|it)\s+against\s+(?:\w+\s+)?websites?)|(?:pozrel|pozrela)\s+som\s+sa\s+na\s+(?:web|internet)|(?:dohladal|dohladala)\s+som\s+(?:to\s+)?na\s+(?:internete|webe)|co\s+som\s+prave\s+dohladal\w*\s+na\s+(?:internete|webe))'
    $current='\b(?:in this turn|for this answer|in this response|just now|v tomto turne|v tejto odpovedi|prave)\b'
    $excluded='\b(?:not|never|if|unless|previous\w*|earlier|yesterday|last\s+(?:year|month|week)|\d+\s+(?:years?|months?|days?)\s+ago|vlani|minuly\s+rok|example\w*|hypothet\w*|quoted|ak|keby|nie|predtym|vcera|minul\w*|priklad\w*|cit\w*)\b'
    $best=$null
    foreach($m in [regex]::Matches($raw,'[^.!?\r\n]+[.!?]?')){
        $t=ConvertTo-LfoG2NormalizedText $m.Value
        if(-not $t -or $t -match '\?$' -or $t -match $excluded){continue}
        if($t -match '^(?:translate|translation|repeat|say|write|preloz|zopakuj|napis)\b'){continue}
        $rule='E1_EXPLICIT'
        if($t -notmatch ('^'+$explicit+'(?:\b|[.!]?$)')){
            if($Sensitivity -eq 'LOW'){continue}
            if($t -notmatch ('^(?:'+$expanded+'|podla toho,\s*'+$expanded+')(?:\b|[.!]?$)')){continue}
            $rule='E1_PARAPHRASE'
        }
        $scope=if($t -match $current){'CURRENT_TURN'}else{'UNRESOLVED'}
        if($scope -eq 'UNRESOLVED' -and $Sensitivity -ne 'HIGH'){continue}
        $assessment=if($scope -eq 'CURRENT_TURN' -and $Context.ExternalEvidence -ceq 'NONE'){'CONTRADICTED'}else{'INSUFFICIENT_EVIDENCE'}
        $candidate=[pscustomobject]@{Assessment=$assessment;Phenomenon='EXTERNAL_VERIFICATION_CLAIM';RuleId=$rule;Scope=$scope;Start=$m.Index;Length=$m.Length}
        if($scope -eq 'CURRENT_TURN'){return $candidate}
        if($null -eq $best){$best=$candidate}
    }
    if($null -ne $best){return $best}
    return 'ABSTAIN'
}
