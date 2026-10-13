param([Parameter(Mandatory)][string]$ResultPath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}

$parseFiles=@(
    'install/Install-LfoWindows.ps1',
    'launch/Start-LfoWindows.ps1',
    'src/QwenChat.ps1',
    'src/QwenMemory.ps1',
    'src/LfoEpistemicPolicyCapsule.ps1',
    'src/LfoEpistemicRuntime.ps1'
)
foreach($rel in $parseFiles){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $rel),[ref]$tokens,[ref]$errors)
    Assert (@($errors).Count -eq 0) ('PowerShell parse: '+$rel+' :: '+(@($errors|ForEach-Object Message)-join '; '))
}

$release=Import-PowerShellDataFile -LiteralPath (Join-Path $root 'config/QwenChat.release.template.psd1')
Assert ([bool]$release.Memory.Enabled) 'L0/L1 memory enabled'
Assert ([bool]$release.Memory.L0StageSourcesEnabled) 'L0 stage provenance enabled'
Assert ([bool]$release.Memory.StructuredEnabled) 'L2 structured memory enabled'
Assert ([bool]$release.Memory.StructuredReadEnabled) 'L2 read enabled'
Assert ([bool]$release.Memory.L3ReadEnabled) 'L3 read enabled'
Assert ([bool]$release.Memory.L3IndexEnabled) 'L3 index enabled'
Assert ([bool]$release.Epistemic.Enabled) 'L4 infrastructure enabled'
Assert (-not [bool]$release.Epistemic.PolicyEnabled) 'automatic P1 policy OFF'
Assert (-not [bool]$release.Epistemic.InterventionEnabled) 'automatic P2 intervention OFF'
Assert ([bool]$release.Epistemic.AllowExplicitReview) 'explicit L4 review allowed'
Assert ([bool]$release.Epistemic.AllowExplicitOneShotIntervention) 'explicit one-shot L4 allowed'

$qwen=[IO.File]::ReadAllText((Join-Path $root 'src/QwenChat.ps1'))
Assert ($qwen.Contains('LfoEpistemicRuntime.ps1')) 'QwenChat loads L4 runtime bridge'
Assert ($qwen.Contains('/l4 status')) 'QwenChat exposes L4 status command'
Assert ($qwen.Contains('/l4 review')) 'QwenChat exposes L4 review command'
Assert ($qwen.Contains('/l4 next')) 'QwenChat exposes one-shot command'
Assert ($qwen.Contains('EXPLICIT ONE-SHOT EPISTEMIC INTERVENTION:')) 'bounded P2 injection boundary present'
Assert (-not $qwen.Contains('LfoEpistemicDetector')) 'D1 detector not loaded into runtime'

$runtimeSource=[IO.File]::ReadAllText((Join-Path $root 'src/LfoEpistemicRuntime.ps1'))
Assert (-not $runtimeSource.Contains('Add-LfoEpistemicObservation')) 'runtime bridge does not auto-write R1 observations'
Assert (-not $runtimeSource.Contains('Invoke-QwenLocalApi')) 'runtime bridge does not call model'

. (Join-Path $root 'src/LfoEpistemicRuntime.ps1')
$tmp=Join-Path $env:TEMP ('lfo-l4-static-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp|Out-Null
try{
    $disabled=Initialize-LfoEpistemicRuntime -Config @{Epistemic=@{Enabled=$false}} -LogDirectory $tmp
    Assert (-not [bool]$disabled.Configured) 'disabled L4 import stays inert'
    Assert (@(Get-ChildItem -LiteralPath $tmp -Force).Count -eq 0) 'disabled L4 performs no filesystem write'
    $refused=Initialize-LfoEpistemicRuntime -Config @{Epistemic=@{Enabled=$true;PolicyEnabled=$true;InterventionEnabled=$false;RecordRuntimeStatus=$true;AllowExplicitReview=$true;AllowExplicitOneShotIntervention=$true;Endpoint='http://127.0.0.1:1';CredentialPath='missing'}} -LogDirectory $tmp
    Assert ([bool]$refused.Configured) 'automatic-policy refusal sees configured L4'
    Assert (-not [bool]$refused.Available) 'automatic-policy request refused before runtime availability'
    Assert ([string]$refused.Error -match 'not authorized') 'automatic-policy refusal reason'
    Assert (@(Get-ChildItem -LiteralPath $tmp -Force).Count -eq 0) 'refused automatic L4 performs no filesystem write'
}finally{Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}

$result=[ordered]@{schema='lfo-integrated-build-static-v1';pass=$true;checks=$script:checks;model_calls=0;automatic_r1_writes=0;production_memory_touched=$false}
[IO.File]::WriteAllText($ResultPath,(($result|ConvertTo-Json -Depth 6)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
Write-Host ('INTEGRATED_BUILD_STATIC_PASS: '+$script:checks+' checks; ModelCalls=0; AutomaticR1Writes=0; ProductionMemoryTouched=False')