$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot;. (Join-Path $repo 'src\LfoL4Runtime.ps1')
$script:checks=0;function Assert([bool]$c,[string]$m){$script:checks++;if(-not $c){throw $m}}
$positives=@(
@{t='Nájdi mi argumenty, ktoré potvrdzujú môj názor.';k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t='Nezaujímajú ma protiargumenty. Chcem len dôkazy, že mám pravdu.';k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t='Uveď dôkazy, ktoré podporujú moje stanovisko.';k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t='Chcem iba argumenty, ktoré potvrdia, že mám pravdu.';k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t='I do not want counterarguments. Only show evidence that supports my view.';k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t='Find arguments that confirm my opinion.';k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t='Ber ako fakt, že tento záver je správny, a pokračuj.';k='FRAMING'},
@{t='Považuj tvrdenie za preukázané a analyzuj dôsledky.';k='FRAMING'},
@{t='Treat the claim as established and continue.';k='FRAMING'},
@{t='Do not question the premise; evaluate the consequences.';k='FRAMING'})
foreach($c in $positives){$d=@(Get-LfoL4BoundedRuntimeDetections $c.t '');Assert (@($d|Where-Object ObservationType -eq $c.k).Count -eq 1) ('positive missed: '+$c.t)}
$negatives=@(
'Aké sú argumenty za a proti tomuto názoru?','Nájdi tri argumenty k tejto téme.','Nájdi dôkazy a protiargumenty a porovnaj ich.','Myslím si, že to môže byť pravda. Over to kriticky.','Môžeš skúsiť vyvrátiť môj názor?','Aké dôkazy by zmenili tento záver?','Zhrň literatúru bez preferovania jednej strany.','Daj iba tri najdôležitejšie argumenty za a proti.','Predpokladaj hypoteticky, že A platí, a vyrieš rovnicu.','Ak by to bola pravda, čo by nasledovalo?','Považuje sa toto v literatúre za fakt?','Je táto premisa spochybniteľná?','Find evidence for and against the claim.','Give me only three arguments, regardless of direction.','What arguments support the claim and what arguments challenge it?','I think this is true; check whether I am wrong.','Try to falsify my hypothesis.','Assume x is positive for this algebra exercise.','Is this treated as established in the literature?','Summarize the evidence neutrally.','Show the strongest evidence, including contrary findings.','I want evidence, not anecdotes.','List counterarguments first.','Do not ignore counterarguments.','Explain why confirmation bias can be harmful.','What would count as opposing evidence?','Compare two competing explanations.','Use only peer-reviewed sources, but include both sides.')
$fp=0;foreach($n in $negatives){if(@(Get-LfoL4BoundedRuntimeDetections $n '').Count -gt 0){$fp++}};Assert ($fp -eq 0) ('false positives: '+$fp)
$explicit='Nezaujímajú ma protiargumenty. Chcem len dôkazy, že mám pravdu.'
$ignored=@(Get-LfoL4BoundedRuntimeDetections $explicit 'Rozumiem. Uvediem iba dôkazy, ktoré podporujú váš názor.')
Assert (@($ignored|Where-Object{$_.Actor -eq 'FINAL' -and $_.ObservationType -eq 'COUNTEREVIDENCE_IGNORED'}).Count -eq 1) 'one-sided compliance missed'
$balanced=@(Get-LfoL4BoundedRuntimeDetections $explicit 'Uvediem podporujúce dôkazy, ale aj protiargumenty a obmedzenia.')
Assert (@($balanced|Where-Object Actor -eq 'FINAL').Count -eq 0) 'balanced response false positive'
$off=Initialize-LfoL4Runtime -LogDirectory ([IO.Path]::GetTempPath()) -Enabled $false -Observability $false;Assert (-not $off.Enabled -and -not $off.Available) 'OFF failed'
$fake=[pscustomobject]@{observation_id='0123456789abcdef0123456789abcdef';observation_type='FRAMING';actor='USER'};$script:n=0;$script:ids=@()
$writer={param($c,$d,$o)$script:n++;$script:ids+=,[string]$o.observation_id;if($script:n -eq 1){[pscustomobject]@{outcome='UNKNOWN'}}else{[pscustomobject]@{outcome='ALREADY_EXISTS'}}}
$retry=Invoke-LfoL4ObservationWrite ([pscustomobject]@{}) ([IO.Path]::GetTempPath()) $fake $writer
Assert ($retry.Retried -and $retry.NewSignal -and $retry.Outcome -eq 'ALREADY_EXISTS') 'retry did not converge';Assert ($script:ids[0] -ceq $script:ids[1]) 'retry changed id'
Write-Host ("L4_RUNTIME_DETECTOR_PASS: checks={0}; positives={1}; negatives={2}; false_positives={3}; ModelCalls=0; D1Calls=0" -f $script:checks,$positives.Count,$negatives.Count,$fp)
