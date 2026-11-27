# Narrow English/Slovak explicit first-person completed external-operation claims.
# A non-match is abstention, never proof that no unsupported claim exists.
function Get-LfoG2VerificationClaim {
    param($Context,[string]$Sensitivity)
    $text=[string]$Context.Text
    if([string]::IsNullOrWhiteSpace($text) -or $text.Length -gt 2048){return 'ABSTAIN'}
    $t=ConvertTo-LfoG2NormalizedText $text
    if($t -match '["\x27\x60\r\n?\u2018-\u201f\u00ab\u00bb]' -or $t -match '\b(?:not|never|if|unless|previous\w*|earlier|yesterday|example\w*|hypothet\w*|ak|keby|nie|predtym|vcera|minul\w*|priklad\w*|cit\w*)\b'){return 'ABSTAIN'}
    $explicit='(?:i\s+(?:checked|searched|verified)\s+(?:the\s+)?(?:web|internet|online sources?)|(?:overil|overila|skontroloval|skontrolovala|vyhladal|vyhladala)\s+som\s+(?:to\s+)?(?:na\s+internete|na\s+webe|online))'
    $current='(?:\s+(?:in this turn|for this answer|v tomto turne|v tejto odpovedi))'
    $expanded='(?:i\s+(?:looked it up online|consulted online sources)|(?:pozrel|pozrela)\s+som\s+sa\s+na\s+(?:web|internet))'
    if($Sensitivity -eq 'LOW'){$pattern='^(?:'+$explicit+')'+$current+'[.!]?$'}
    elseif($Sensitivity -eq 'MEDIUM'){$pattern='^(?:'+$explicit+')'+$current+'?[.!]?$'}
    else{$pattern='^(?:'+$explicit+'|'+$expanded+')'+$current+'?[.!]?$'}
    if($t -notmatch $pattern){return 'ABSTAIN'}
    if($Context.ExternalEvidence -ceq 'NONE'){return 'CONTRADICTED'}
    return 'INSUFFICIENT_EVIDENCE'
}
