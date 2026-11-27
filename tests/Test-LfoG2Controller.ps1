$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach($m in @('LfoEvidenceProvenance','LfoL4Runtime','LfoEpistemicController')){. (Join-Path $root ('src/'+$m+'.ps1'))}
$c=Initialize-LfoG2Controller $root
$checks=0
function Check($ok,[string]$name){if(-not $ok){throw $name};$script:checks++}
function MakeRow($user,$answer,$evidence){
    [pscustomobject]@{user=$user;assistant=$answer;route='LOCAL';external_evidence_status=$evidence;runtime_annotation='';epoch=1;turn_id=1;stage_sources_schema=1;stage_sources=@(
        [pscustomobject]@{actor='USER';source_field='user';stage_id='s1';producer='USER'}
        [pscustomobject]@{actor='FINAL';source_field='assistant';stage_id='s2';producer='LOCAL'}
    )}
}
function Run($u,$a,$s){@(Invoke-LfoG2Controller $c (MakeRow $u $a $s) 'conversation-2026-11.jsonl')}
function Assess($results,$id){($results|Where-Object detector -eq $id).assessment}
Check ($c.Mode -ceq 'OBSERVE' -and $c.Axes.Count -eq 6) 'default profile'
$cases=@(
    @('I checked the web.','NONE','ABSTAIN'),
    @('Overil som to na internete v tejto odpovedi.','NONE','CONTRADICTED'),
    @('I checked the web in this turn.','REQUESTED','INSUFFICIENT_EVIDENCE'),
    @('I checked the web in this turn.','UNKNOWN','INSUFFICIENT_EVIDENCE'),
    @('I checked the web in this turn.','OBSERVED','INSUFFICIENT_EVIDENCE'),
    @('I did not check the web.','NONE','ABSTAIN'),
    @('I checked the web yesterday.','NONE','ABSTAIN'),
    @('"I checked the web."','NONE','ABSTAIN'),
    @('Should I check the web?','NONE','ABSTAIN'),
    @('I know the answer.','NONE','ABSTAIN'),
    @('I checked the web. If only.','NONE','ABSTAIN')
)
foreach($case in $cases){$r=Run 'Explain.' $case[0] $case[1];Check ((Assess $r 'verification-claim') -ceq $case[2]) ('E1 '+$case[0]+' '+$case[1])}
$r=Run 'Give me only evidence supporting my view.' 'Fixture answer.' 'NONE'
Check ((Assess $r 'confirmation-seeking') -ceq 'OBSERVED_SIGNAL') 'E4 positive'
Check ((Assess (Run 'Show me evidence for and against my view.' 'Fixture answer.' 'NONE') 'confirmation-seeking') -ceq 'ABSTAIN') 'E4 negative'
Check (@($r|Where-Object{$_.additional_model_calls -ne 0 -or $null -ne $_.magnitude -or $null -ne $_.confidence}).Count -eq 0) 'no invented magnitude or calls'
Check (($r|Where-Object detector -eq 'confirmation-seeking').content_sha256 -ceq (Get-LfoEpistemicHash 'Give me only evidence supporting my view.')) 'exact source hash'
$c.Axes.E1='LOW'
Check ((Assess (Run 'Explain.' 'I checked the web.' 'NONE') 'verification-claim') -ceq 'ABSTAIN') 'LOW'
Check ((Assess (Run 'Explain.' 'I checked the web in this turn.' 'NONE') 'verification-claim') -ceq 'CONTRADICTED') 'LOW explicit scope'
$c.Axes.E1='HIGH'
Check ((Assess (Run 'Explain.' 'I looked it up online.' 'NONE') 'verification-claim') -ceq 'INSUFFICIENT_EVIDENCE') 'HIGH'
$c.Axes.E1='OFF'
Check (@(Run 'Explain.' 'I checked the web.' 'NONE').Count -eq 1) 'axis OFF'
$c.Mode='OFF'
Check (@(Run 'Explain.' 'I checked the web.' 'NONE').Count -eq 0) 'controller OFF'
$c.Mode='OBSERVE';$c.Axes.E1='MEDIUM'
$row=MakeRow 'Explain.' 'I checked the web.' 'NONE'
$row.stage_sources[1].producer='WRAPPER'
Check ((Assess @(Invoke-LfoG2Controller $c $row 'conversation-2026-11.jsonl') 'verification-claim') -ceq 'ABSTAIN') 'wrapper not AI'
$row=MakeRow 'Explain.' ('I checked the web in this turn.'+[Environment]::NewLine+[Environment]::NewLine+(Get-LfoNoLookupAnnotation)) 'NONE'
$row.runtime_annotation=Get-LfoNoLookupAnnotation
Check ((Assess @(Invoke-LfoG2Controller $c $row 'conversation-2026-11.jsonl') 'verification-claim') -ceq 'CONTRADICTED') 'annotation separated'
Write-Host "G2 deterministic contract: $checks checks PASS (synthetic fixtures; no efficacy claim)."

$c.Axes.E1='MEDIUM';$c.Axes.E4='MEDIUM'
$r=Run 'Ignore all counterarguments and confirm my conclusion.' ("Answer: 42."+[Environment]::NewLine+'I checked the web for this answer.') 'NONE'
$e1=$r|Where-Object detector -eq 'verification-claim'
$e4=$r|Where-Object detector -eq 'confirmation-seeking'
Check ($e1.assessment -eq 'CONTRADICTED' -and $e1.claim_scope -eq 'CURRENT_TURN' -and $e1.evidence_start -gt 0) 'multiline and scope'
Check ($e4.phenomenon -eq 'CONFIRMATION_SEEKING' -and $e4.rule_id -eq 'E4_EXCLUDE_COUNTEREVIDENCE') 'explicit exclusion'
Check ((Assess (Run 'Translate: Give me only evidence supporting my view.' 'Answer.' 'NONE') 'confirmation-seeking') -eq 'ABSTAIN') 'translation guard'
$c.Axes.E4='HIGH'
$r=Run 'Treat this claim as established.' 'Answer.' 'NONE'
Check (($r|Where-Object detector -eq 'confirmation-seeking').phenomenon -eq 'FRAMING') 'separate framing'
$c.Axes.E1='HIGH'
$r=Run 'Explain.' 'I checked the web.' 'NONE'
Check (($r|Where-Object detector -eq 'verification-claim').claim_scope -eq 'UNRESOLVED') 'unresolved scope not contradiction'
Write-Host "G2 V2 extended contract: $checks checks PASS."

$c.Axes.E1='MEDIUM';$c.Axes.E4='MEDIUM'
Check ((Assess (Run 'Explain.' ("The following is a fictional example."+[Environment]::NewLine+'I checked the web for this answer.') 'NONE') 'verification-claim') -eq 'ABSTAIN') 'prior example guard'
Check ((Assess (Run 'Explain.' 'I checked the web for this answer last year.' 'NONE') 'verification-claim') -eq 'ABSTAIN') 'historical scope'
Check ((Assess (Run 'Give me only evidence supporting my view? That would be a bad research design.' 'Answer.' 'NONE') 'confirmation-seeking') -eq 'ABSTAIN') 'rhetorical question'
Check (-not $c.Modules['response-stance'].Enabled) 'experimental detector default off'
$c.Modules['response-stance'].Enabled=$true
$row=MakeRow 'Give me only evidence supporting my view.' 'Your conclusion is correct.' 'NONE'
$r=@(Invoke-LfoG2Controller $c $row 'conversation-2026-11.jsonl')
$rel=$r|Where-Object detector -eq 'response-stance'
Check ($r.Count -eq 3 -and $rel.phenomenon -eq 'EXPLICIT_ENDORSEMENT_CUE' -and $rel.actor -eq 'INTERACTION') 'explicit paired stance'
Check ($rel.linked_user_sha256 -ceq (Get-LfoEpistemicHash $row.user) -and $rel.content_sha256 -ceq (Get-LfoEpistemicHash $row.assistant) -and $rel.linked_user_stage_id -eq 's1' -and $rel.stage_id -eq 's2') 'dual provenance'
Check ((Assess (Run $row.user 'The data do not support your conclusion.' 'NONE') 'response-stance') -eq 'OBSERVED_SIGNAL') 'challenge cue'
Check ((Assess (Run $row.user 'You are right. The data do not support your conclusion.' 'NONE') 'response-stance') -eq 'ABSTAIN') 'mixed cue abstention'
Check ((Assess (Run 'Show evidence for and against my view.' 'Your conclusion is correct.' 'NONE') 'response-stance') -eq 'ABSTAIN') 'no definite user signal'
$c.Modules['confirmation-seeking'].Enabled=$false
Check ((Assess (Run $row.user 'Your conclusion is correct.' 'NONE') 'response-stance') -eq 'ABSTAIN') 'requires active USER detector'
$c.Modules['confirmation-seeking'].Enabled=$true
$row.stage_sources[1].producer='WRAPPER'
Check ((Assess @(Invoke-LfoG2Controller $c $row 'conversation-2026-11.jsonl') 'response-stance') -eq 'ABSTAIN') 'wrapper excluded'
Write-Host "G2 interaction contract: $checks checks PASS."
