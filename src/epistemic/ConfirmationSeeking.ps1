# V2: explicit request-level signals, not inferred psychological traits.
# Framing is tagged separately and is not counted as confirmation-seeking recall.
function Get-LfoG2ConfirmationSeeking {
    param($Context,[string]$Sensitivity)
    $raw=[string]$Context.Text
    if([string]::IsNullOrWhiteSpace($raw) -or $raw.Length -gt 8000){return 'ABSTAIN'}
    $t=ConvertTo-LfoG2NormalizedText $raw
    # Guard explicit metalinguistic, hypothetical, debate and quoted use.
    if($t -match '["\u2018-\u201f\u00ab\u00bb\x60]' -or $t -match '(?m)^\s*(?:>|~~~)' -or $t -match '\b(?:translate|translation|explain why|hypothetical|debate exercise|role.play|preloz|preklad|vysvetli preco|hypotetick\w*|debat\w*|simulaci\w*)\b'){return 'ABSTAIN'}
    if($t -match '\b(?:for and against|both sides|then show|also show|counterarguments too|pre aj proti|za aj proti|aj proti|aj protiargumenty|potom uved|vyvratit)\b'){return 'ABSTAIN'}
    if($t -match '^(?:do not|don.t|never|neber|nepovazuj|nepotvrdzuj|neignoruj)\b'){return 'ABSTAIN'}
    if($t -match '^[^?\r\n]{1,400}\?\s*(?:that|this|it|to|taketo)\b'){return 'ABSTAIN'}
    $phenomenon=$null;$rule=$null
    $only='(?:only|solely|exclusively|iba|len|vylucne)'
    $evidence='(?:evidence|arguments?|reasons?|proof|dokaz\w*|argument\w*|dovod\w*)'
    $confirm='(?:support\w*|confirm\w*|prov\w*|in favour|in favor|potvrdz\w*|podpor\w*|v prospech)'
    $view='(?:my\b|our\b|this\b|moj\w*\b|nas\w*\b|hypotez\w*\b|presvedceni\w*\b|nazor\w*\b|zaver\w*\b)'
    if($t -match ('^(?:please\s+|prosim\s+)?(?:give|find|show|provide|list|daj|najdi|ukaz|uved|chcem)\b.{0,50}\b'+$only+'\s+'+$evidence+'\b.{0,80}\b'+$confirm+'\b.{0,70}\b'+$view)){
        $phenomenon='CONFIRMATION_SEEKING';$rule='E4_EXCLUSIVE_EVIDENCE'
    }elseif($Sensitivity -ne 'LOW' -and $t -match '\b(?:ignore|omit|exclude|discard|vynechaj|ignoruj|vyluc)\b.{0,100}\b(?:counterarguments?|contradict\w*|opposing evidence|protiargument\w*|protidokaz\w*|vyvrac\w*)\b' -and $t -match ('\b'+$confirm+'\b.{0,100}\b'+$view)){
        $phenomenon='CONFIRMATION_SEEKING';$rule='E4_EXCLUDE_COUNTEREVIDENCE'
    }elseif($Sensitivity -eq 'HIGH' -and $t -match '^(?:prove my point|confirm my conclusion|potvrd moj zaver)[.!]?$'){
        $phenomenon='CONFIRMATION_CANDIDATE';$rule='E4_UNDERSPECIFIED_REQUEST'
    }elseif($Sensitivity -eq 'HIGH' -and ((Get-LfoL4TurnObservationType $raw) -ceq 'FRAMING' -or $t -match '^(?:treat\s+this\s+claim\s+as\s+established|ber\s+ako\s+fakt)\b')){
        $phenomenon='FRAMING';$rule='E4_FROZEN_FRAMING'
    }
    if($null -eq $phenomenon){return 'ABSTAIN'}
    [pscustomobject]@{Assessment='OBSERVED_SIGNAL';Phenomenon=$phenomenon;RuleId=$rule;Scope='USER_REQUEST';Start=0;Length=$raw.Length}
}
