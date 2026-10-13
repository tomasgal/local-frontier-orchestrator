$ErrorActionPreference='Stop'
$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
$contractPath=Join-Path $PSScriptRoot '..\config\L4A1Observatory.contract.json'
$docPath=Join-Path $PSScriptRoot '..\docs\L4_A1_OBSERVATORY_CONTRACT.md'
$utf8=New-Object Text.UTF8Encoding($false,$true)
$c=[IO.File]::ReadAllText((Resolve-Path $contractPath),$utf8)|ConvertFrom-Json -ErrorAction Stop
$d=[IO.File]::ReadAllText((Resolve-Path $docPath),$utf8)
Assert ($c.schema -ceq 'lfo-l4-a1-observatory-contract-v1') 'Wrong A1 contract schema'
Assert ($c.dependency_tag -ceq 'v9.6-l4-r2-frozen') 'Wrong frozen dependency'
Assert (@($c.chronology.primary).Count -eq 2 -and $c.chronology.primary[0] -ceq 'source.epoch' -and $c.chronology.primary[1] -ceq 'source.turn_id') 'Wrong chronology'
Assert ($c.chronology.observed_at_role -match 'never conversation chronology') 'observed_at chronology guard missing'
Assert (@($c.questions).Count -eq 5) 'Expected five A1 questions'
$ids=@($c.questions.id)
Assert (@('A1-Q1','A1-Q2','A1-Q3','A1-Q4','A1-Q5'|Where-Object{$_ -notin $ids}).Count -eq 0) 'Missing A1 question'
$q2=@($c.questions|Where-Object id -eq 'A1-Q2')[0]
Assert ($q2.direction -ceq 'related_observation -> current_observation') 'Wrong link direction'
Assert ($q2.boundary_policy -match 'both inside') 'Window-boundary link policy missing'
$q3=@($c.questions|Where-Object id -eq 'A1-Q3')[0]
Assert ([int]$q3.minimum_distinct_turns -eq 2) 'Recurrence threshold must be two distinct turns'
Assert (@($q3.signatures).Count -eq 2) 'Recurrence signatures missing'
$q4=@($c.questions|Where-Object id -eq 'A1-Q4')[0]
Assert ($q4.purpose -match 'non-overlapping') 'Window comparison overlap guard missing'
$q5=@($c.questions|Where-Object id -eq 'A1-Q5')[0]
Assert ($q5.raw_source_policy -match 'explicit resolver') 'Provenance raw-source guard missing'
Assert ([int]$c.window.max_support_ids_per_result -eq 50) 'Support bound mismatch'
Assert (@($c.guardrails|Where-Object{$_ -match 'No automatic detector'}).Count -eq 1) 'Detector guard missing'
Assert (@($c.guardrails|Where-Object{$_ -match 'No ordinary prompt injection'}).Count -eq 1) 'Prompt guard missing'
Assert (@($c.guardrails|Where-Object{$_ -match 'No mandatory model call'}).Count -eq 1) 'Model-call guard missing'
Assert ($d -match 'related/parent observation -> current/child observation') 'Human-readable semantic link direction missing'
Assert ($d -match 'Repeated annotations within only one source turn are not recurrence') 'Human-readable recurrence boundary missing'
Assert ($d -match 'A1 does not aggregate across stores or epochs') 'Human-readable scope guard missing'
Assert ($d -match 'A1-Q5') 'Human-readable provenance question missing'
Write-Host ('A1_ANALYTIC_CONTRACT_PASS: '+$script:checks+' checks; ModelCalls=0; ProductionMemoryTouched=False')
[pscustomobject]@{PASS=$true;Checks=$script:checks;ModelCalls=0;ProductionMemoryTouched=$false}
