$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach($m in @('LfoEvidenceProvenance','LfoL4Runtime','LfoEpistemicController','LfoG2ComputePolicy','LfoG2Intervention')){. (Join-Path $root ('src/'+$m+'.ps1'))}
$c=Initialize-LfoG2Controller $root
$c.Mode='INTERVENE'
$checks=0
function Check($ok,[string]$name){if(-not $ok){throw $name};$script:checks++}
$plain='I checked the web for this answer.'
$compound='I checked the web for this answer and found several examples.'
$clean='The supplied example is insufficient to draw a general conclusion.'
$bad={param($a,$f,$i) [pscustomobject]@{Raw='raw';Answer=$compound;Valid=$true}}
$good={param($a,$f,$i) [pscustomobject]@{Raw='raw';Answer=$clean;Valid=$true}}
$r=Invoke-LfoG2InterventionCascade $c $clean 'NONE' 'CASCADE' 2 {throw 'No call allowed'}
Check ($r.Status -eq 'NOT_TRIGGERED' -and $r.RevisionCalls -eq 0 -and $r.Answer -ceq $clean) 'no signal'
$r=Invoke-LfoG2InterventionCascade $c ($plain+' The example is illustrative.') 'NONE' 'MINIMAL' 2 {throw 'No call allowed'}
Check ($r.ChangedBy -eq 'INLINE' -and $r.RevisionCalls -eq 0 -and $r.Status -eq 'SIGNAL_NOT_REDETECTED' -and $r.Answer -match 'The example is illustrative') 'safe inline'
foreach($p in @('MINIMAL','STANDARD')){
    $r=Invoke-LfoG2InterventionCascade $c $compound 'NONE' $p 2 {throw 'No call allowed'}
    Check ($r.Status -eq 'UNRESOLVED' -and $r.RevisionCalls -eq 0 -and $r.Answer -ceq $compound) ($p+' no retry')
}
$r=Invoke-LfoG2InterventionCascade $c $compound 'NONE' 'CASCADE' 2 $good
Check ($r.RevisionCalls -eq 1 -and $r.ChangedBy -eq 'REVISION' -and $r.Answer -ceq $clean) 'second run resolves'
$r=Invoke-LfoG2InterventionCascade $c $compound 'NONE' 'CASCADE' 2 {param($a,$f,$i) if($i -eq 1){& $bad $a $f $i}else{& $good $a $f $i}}
Check ($r.RevisionCalls -eq 2 -and $r.ChangedBy -eq 'REVISION' -and $r.Attempts.Count -eq 3) 'third run resolves'
$r=Invoke-LfoG2InterventionCascade $c ($compound+' The example is fictional.') 'NONE' 'CASCADE' 2 $bad
Check ($r.RevisionCalls -eq 2 -and $r.Status -eq 'UNRESOLVED_PARTIAL' -and $r.Answer -match 'Partial result' -and $r.Answer -match 'The example is fictional' -and $r.Answer -notmatch 'I checked the web') 'third run unresolved preserves partial'
$r=Invoke-LfoG2InterventionCascade $c $compound 'NONE' 'CASCADE' 1 $bad
Check ($r.RevisionCalls -eq 1 -and $r.Status -eq 'UNRESOLVED_PARTIAL') 'shared retry cap'
$r=Invoke-LfoG2InterventionCascade $c $compound 'NONE' 'CASCADE' 2 {throw 'simulated transport failure'}
Check ($r.RevisionCalls -eq 2 -and $r.Status -eq 'UNRESOLVED_PARTIAL' -and @($r.Attempts|Where-Object assessment -eq 'INVALID_RESPONSE').Count -eq 2) 'failed calls bounded'
$r=Invoke-LfoG2InterventionCascade $c $compound 'REQUESTED' 'CASCADE' 2 $bad
Check ($r.RevisionCalls -eq 0 -and $r.Answer -ceq $compound) 'no contradiction from requested'
$c.Axes.E1='OFF'
$r=Invoke-LfoG2InterventionCascade $c $compound 'NONE' 'CASCADE' 2 $bad
Check ($r.RevisionCalls -eq 0 -and $r.Answer -ceq $compound) 'disabled axis'
Check ((Get-LfoG2InterventionPlan $c 'Give me only evidence supporting my view.' 'AUTO' $true).eligible) 'intervene pre on AUTO'
Check (-not (Get-LfoG2InterventionPlan $c 'Give me only evidence supporting my view.' 'FRONTIER' $true).eligible) 'frontier excluded'
Write-Host "G2 cascade contract: $checks checks PASS."
