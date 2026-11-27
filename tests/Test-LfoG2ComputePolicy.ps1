$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach($m in @('LfoEvidenceProvenance','LfoL4Runtime','LfoEpistemicController','LfoG2ComputePolicy')){. (Join-Path $root ('src/'+$m+'.ps1'))}
$c=Initialize-LfoG2Controller $root
function Check($ok,[string]$name){if(-not $ok){throw $name}}
$lead='Give me only evidence supporting my view.'
$neutral='Show me evidence for and against my view.'
$off=Get-LfoG2InterventionPlan $c $lead 'LOCAL' $false
Check (-not $off.eligible) 'OFF must not intervene'
$plan=Get-LfoG2InterventionPlan $c $lead 'LOCAL' $true
Check ($plan.eligible -and $plan.instruction.Length -lt 400) 'bounded definite signal'
Check (-not (Get-LfoG2InterventionPlan $c $neutral 'LOCAL' $true).eligible) 'neutral must not intervene'
Check (-not (Get-LfoG2InterventionPlan $c $lead 'AUTO' $true).eligible) 'no route changes'
$messages=@(@{role='system';content='system'},@{role='user';content=$lead})
$result=@(Add-LfoG2RequestSafeguard $messages $plan)
Check ($result.Count -eq 2 -and $result[0].content -match 'Epistemic safeguard' -and $messages[0].content -ceq 'system' -and $result[1].content -ceq $lead) 'copy only; raw user unchanged'
Check ((Get-LfoG2ComputeRecommendation 'Design an architecture' 0 $false '').recommendation -eq 'DEEP') 'complex'
Check ((Get-LfoG2ComputeRecommendation 'Continue.' 3 $false 'DEEP').recommendation -eq 'DEEP') 'continuity'
Check ((Get-LfoG2ComputeRecommendation 'What is x?' 0 $true '').recommendation -eq 'DEEP') 'explicit thinking'
Check ((Get-LfoG2ComputeRecommendation 'What is x?' 0 $false '').recommendation -eq 'FAST') 'standalone shadow fast'
$c.Mode='OFF'
Check (-not (Get-LfoG2InterventionPlan $c $lead 'LOCAL' $true).eligible) 'controller OFF'
Write-Host 'G2 compute and intervention contract PASS.'
