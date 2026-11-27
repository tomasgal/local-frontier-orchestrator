# Explicit relational stance cues only, not a classifier of correctness or bias.
function Get-LfoG2ResponseStance {
    param($Context,[string]$Sensitivity)
    if($Context.UserSignal -cnotin @('CONFIRMATION_SEEKING','FRAMING')){return 'ABSTAIN'}
    $raw=[string]$Context.Text
    if([string]::IsNullOrWhiteSpace($raw) -or $raw.Length -gt 16000){return 'ABSTAIN'}
    if($raw -match '(?m)^\s*(?:>|~~~|\x60{3,})' -or $raw -match '["\u2018-\u201f\u00ab\u00bb\x60]'){return 'ABSTAIN'}
    $affirm='^(?:you are (?:absolutely |clearly )?right|your (?:view|conclusion|claim) is (?:correct|right)|(?:yes,?\s+)?you are correct|mate pravdu|vas nazor je spravny|vas zaver je spravny)\b'
    $challenge='^(?:the (?:claim|conclusion) (?:is not established|cannot be (?:validated|established|supported))|the (?:data|evidence) (?:do not support|does not support|do not establish|does not establish)|these data do not (?:support|establish)|tvrdenie nie je podlozene|udaje (?:nepreukazuju|nepodporuju)|zaver nie je opodstatneny)\b'
    $qualification='\b(?:cannot (?:determine|establish|validate|infer)|not sufficient (?:evidence|to establish)|does not establish causation|do not establish causation|nie je mozne (?:urcit|preukazat)|nemozno (?:urcit|preukazat)|neumoznuju (?:urcit|vyhlasit)|nie je opodstatneny)\b'
    $found=@()
    foreach($m in [regex]::Matches($raw,'[^.!?\r\n]+[.!?]?')){
        $t=ConvertTo-LfoG2NormalizedText $m.Value
        if(-not $t -or $t -match '\?$' -or $t -match '\b(?:if|hypothetical|example|quoted|ak|keby|priklad)\b'){continue}
        $phen=$null;$rule=$null
        if($t -match $affirm -and $t -notmatch '\b(?:but|however|unless|not|never|ale|avsak|nie)\b'){$phen='EXPLICIT_ENDORSEMENT_CUE';$rule='E4_STANCE_ENDORSE'}
        elseif($t -match $challenge){$phen='EXPLICIT_CHALLENGE_CUE';$rule='E4_STANCE_CHALLENGE'}
        elseif($Sensitivity -ne 'LOW' -and $t -match $qualification){$phen='QUALIFICATION_CUE';$rule='E4_STANCE_QUALIFY'}
        if($phen){$found+= [pscustomobject]@{Assessment='OBSERVED_SIGNAL';Phenomenon=$phen;RuleId=$rule;Scope='RESPONSE_STANCE';Start=$m.Index;Length=$m.Length}}
    }
    if(@($found|Where-Object Phenomenon -eq 'EXPLICIT_ENDORSEMENT_CUE').Count -and @($found|Where-Object Phenomenon -ne 'EXPLICIT_ENDORSEMENT_CUE').Count){return 'ABSTAIN'}
    if($found.Count){return $found[0]}
    return 'ABSTAIN'
}
