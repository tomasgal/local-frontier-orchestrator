$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot;. (Join-Path $repo 'src\LfoL4Runtime.ps1')
$script:checks=0;function Assert([bool]$c,[string]$m){$script:checks++;if(-not $c){throw $m}}
function U([string]$b64){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))}
$positives=@(
@{t=(U 'TsOhamRpIG1pIGFyZ3VtZW50eSwga3RvcsOpIHBvdHZyZHp1asO6IG3DtGogbsOhem9yLg==');k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t=(U 'TmV6YXVqw61tYWrDuiBtYSBwcm90aWFyZ3VtZW50eS4gQ2hjZW0gbGVuIGTDtGthenksIMW+ZSBtw6FtIHByYXZkdS4=');k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t=(U 'VXZlxI8gZMO0a2F6eSwga3RvcsOpIHBvZHBvcnVqw7ogbW9qZSBzdGFub3Zpc2tvLg==');k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t='Chcem iba argumenty, ktore potvrdia, ze mam pravdu.';k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t='I do not want counterarguments. Only show evidence that supports my view.';k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t='Find arguments that confirm my opinion.';k='ASYMMETRIC_EVIDENCE_REQUEST'},
@{t=(U 'QmVyIGFrbyBmYWt0LCDFvmUgdGVudG8gesOhdmVyIGplIHNwcsOhdm55LCBhIHBva3JhxI11ai4=');k='FRAMING'},
@{t=(U 'UG92YcW+dWogdHZyZGVuaWUgemEgcHJldWvDoXphbsOpIGEgYW5hbHl6dWogZMO0c2xlZGt5Lg==');k='FRAMING'},
@{t='Treat the claim as established and continue.';k='FRAMING'},
@{t='Do not question the premise; evaluate the consequences.';k='FRAMING'})
foreach($c in $positives){$d=@(Get-LfoL4BoundedRuntimeDetections $c.t '');Assert (@($d|Where-Object ObservationType -eq $c.k).Count -eq 1) 'positive missed'}
$negatives=@('Ake su argumenty za a proti tomuto nazoru?','Najdi tri argumenty k tejto teme.','Najdi dokazy a protiargumenty a porovnaj ich.','Myslim si, ze to moze byt pravda. Over to kriticky.','Mozes skusit vyvratit moj nazor?','Ake dokazy by zmenili tento zaver?','Zhrn literaturu bez preferovania jednej strany.','Daj iba tri najdolezitejsie argumenty za a proti.','Predpokladaj hypoteticky, ze A plati, a vyries rovnicu.','Ak by to bola pravda, co by nasledovalo?','Povazuje sa toto v literature za fakt?','Je tato premisa spochybnitelna?','Find evidence for and against the claim.','Give me only three arguments, regardless of direction.','What arguments support the claim and what arguments challenge it?','I think this is true; check whether I am wrong.','Try to falsify my hypothesis.','Assume x is positive for this algebra exercise.','Is this treated as established in the literature?','Summarize the evidence neutrally.','Show the strongest evidence, including contrary findings.','I want evidence, not anecdotes.','List counterarguments first.','Do not ignore counterarguments.','Explain why confirmation bias can be harmful.','What would count as opposing evidence?','Compare two competing explanations.','Use only peer-reviewed sources, but include both sides.')
$fp=0;foreach($n in $negatives){if(@(Get-LfoL4BoundedRuntimeDetections $n '').Count -gt 0){$fp++}};Assert ($fp -eq 0) ('false positives: '+$fp)
$explicit=U 'TmV6YXVqw61tYWrDuiBtYSBwcm90aWFyZ3VtZW50eS4gQ2hjZW0gbGVuIGTDtGthenksIMW+ZSBtw6FtIHByYXZkdS4='
$ignored=@(Get-LfoL4BoundedRuntimeDetections $explicit (U 'Um96dW1pZW0uIFV2ZWRpZW0gaWJhIGTDtGthenksIGt0b3LDqSBwb2Rwb3J1asO6IHbDocWhIG7DoXpvci4='))
Assert (@($ignored|Where-Object{$_.Actor -eq 'FINAL' -and $_.ObservationType -eq 'COUNTEREVIDENCE_IGNORED'}).Count -eq 1) 'one-sided compliance missed'
$balanced=@(Get-LfoL4BoundedRuntimeDetections $explicit (U 'VXZlZGllbSBwb2Rwb3J1asO6Y2UgZMO0a2F6eSwgYWxlIGFqIHByb3RpYXJndW1lbnR5IGEgb2JtZWR6ZW5pYS4='))
Assert (@($balanced|Where-Object Actor -eq 'FINAL').Count -eq 0) 'balanced response false positive'
$off=Initialize-LfoL4Runtime -LogDirectory ([IO.Path]::GetTempPath()) -Enabled $false -Observability $false;Assert (-not $off.Enabled -and -not $off.Available) 'OFF failed'
$fake=[pscustomobject]@{observation_id='0123456789abcdef0123456789abcdef';observation_type='FRAMING';actor='USER'};$script:n=0;$script:ids=@()
$writer={param($c,$d,$o)$script:n++;$script:ids+=,[string]$o.observation_id;if($script:n -eq 1){[pscustomobject]@{outcome='UNKNOWN'}}else{[pscustomobject]@{outcome='ALREADY_EXISTS'}}}
$retry=Invoke-LfoL4ObservationWrite ([pscustomobject]@{}) ([IO.Path]::GetTempPath()) $fake $writer
Assert ($retry.Retried -and $retry.NewSignal -and $retry.Outcome -eq 'ALREADY_EXISTS') 'retry did not converge';Assert ($script:ids[0] -ceq $script:ids[1]) 'retry changed id'
$script:LfoL4State.SignalTurns=3;$script:LfoL4State.LastAnalyticsTurn=9;$script:LfoL4State.PendingIntervention=[pscustomobject]@{Decision='REVIEW_FRAMING';Instruction='x';SourceTurn=9}
Reset-LfoL4RuntimeSession
Assert ($script:LfoL4State.SignalTurns -eq 0 -and $script:LfoL4State.LastAnalyticsTurn -eq 0 -and $null -eq $script:LfoL4State.PendingIntervention) 'session reset retained cross-epoch trigger/intervention state'
Write-Host ("L4_RUNTIME_DETECTOR_PASS: checks={0}; positives={1}; negatives={2}; false_positives={3}; ModelCalls=0; D1Calls=0" -f $script:checks,$positives.Count,$negatives.Count,$fp)
