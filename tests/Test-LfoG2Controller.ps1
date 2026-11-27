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
    @('I checked the web.','NONE','CONTRADICTED'),
    @('Overil som to na internete.','NONE','CONTRADICTED'),
    @('I checked the web.','REQUESTED','INSUFFICIENT_EVIDENCE'),
    @('I checked the web.','UNKNOWN','INSUFFICIENT_EVIDENCE'),
    @('I checked the web.','OBSERVED','INSUFFICIENT_EVIDENCE'),
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
Check ((Assess (Run 'Explain.' 'I looked it up online.' 'NONE') 'verification-claim') -ceq 'CONTRADICTED') 'HIGH'
$c.Axes.E1='OFF'
Check (@(Run 'Explain.' 'I checked the web.' 'NONE').Count -eq 1) 'axis OFF'
$c.Mode='OFF'
Check (@(Run 'Explain.' 'I checked the web.' 'NONE').Count -eq 0) 'controller OFF'
$c.Mode='OBSERVE';$c.Axes.E1='MEDIUM'
$row=MakeRow 'Explain.' 'I checked the web.' 'NONE'
$row.stage_sources[1].producer='WRAPPER'
Check ((Assess @(Invoke-LfoG2Controller $c $row 'conversation-2026-11.jsonl') 'verification-claim') -ceq 'ABSTAIN') 'wrapper not AI'
$row=MakeRow 'Explain.' ('I checked the web.'+[Environment]::NewLine+[Environment]::NewLine+(Get-LfoNoLookupAnnotation)) 'NONE'
$row.runtime_annotation=Get-LfoNoLookupAnnotation
Check ((Assess @(Invoke-LfoG2Controller $c $row 'conversation-2026-11.jsonl') 'verification-claim') -ceq 'CONTRADICTED') 'annotation separated'
Write-Host "G2 deterministic contract: $checks checks PASS (synthetic fixtures; no efficacy claim)."
