# Offline UMA contract and PowerShell AST checks; no model inference or service lifecycle.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$paths = @('install/Install-LFO.ps1','LFO.ps1','launch/Start-LFO.ps1','launch/Start-LFO-UMA.ps1')
$asts = @{}
foreach ($path in $paths) {
    $full = Join-Path $root ($path -replace '/','\')
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($full,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw ("PowerShell parse failed in {0}: {1}" -f $path,(@($parseErrors | ForEach-Object { $_.Message }) -join '; '))
    }
    $asts[$path] = $ast
}
$installer = Get-Content -LiteralPath (Join-Path $root 'install/Install-LFO.ps1') -Raw -Encoding UTF8
foreach ($required in @(
    "[ValidateSet('CPU','GPU','UMA')]",
    "qwen3.5:35b-a3b-q8_0",
    "lfo-qwen3.5-35b-uma16k:latest",
    'PARAMETER num_ctx $UmaContext',
    'PARAMETER num_gpu 99',
    'UMA refuses to start a second Ollama listener',
    'no automatic 35B download',
    'Start-LFO-UMA.ps1',
    'UMAModel=$UmaModel;UMAContext=$UmaContext'
)) {
    if (-not $installer.Contains($required)) { throw "Missing UMA installer contract: $required" }
}
$fnNames = @('Resolve-LfoDevice','Get-LfoModelSpec')
foreach ($name in $fnNames) {
    $found = @($asts['LFO.ps1'].FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    },$true))
    if ($found.Count -ne 1) { throw "Expected one function $name, found $($found.Count)" }
    . ([scriptblock]::Create($found[0].Extent.Text))
}
$state = [pscustomobject]@{
    LFO = [pscustomobject]@{ DefaultProfile = 'UMA' }
    Ollama = [pscustomobject]@{
        CPUModel='lfo-qwen3.5-4b-cpu5k:latest'
        GPUModel='lfo-qwen3.5-4b-gpu8k:latest'
        UMAModel='lfo-qwen3.5-35b-uma16k:latest'
        UMAContext=16384
    }
}
if ((Resolve-LfoDevice 'Auto' $state) -ne 'UMA') { throw 'UMA auto device resolution failed.' }
if ((Resolve-LfoDevice 'UMA' $state) -ne 'UMA') { throw 'Explicit UMA selection failed.' }
$uma = Get-LfoModelSpec $state 'UMA'
if ($uma.Model -ne $state.Ollama.UMAModel -or $uma.Context -ne 16384) { throw 'UMA model spec mismatch.' }
if ((Get-LfoModelSpec $state 'CPU').Context -ne 5120) { throw 'Legacy CPU context changed.' }
if ((Get-LfoModelSpec $state 'GPU').Context -ne 8192) { throw 'Legacy GPU context changed.' }
$state.LFO.DefaultProfile='CPU'
if ((Resolve-LfoDevice 'UMA' $state) -ne 'UMA') { throw 'Explicit UMA override failed on legacy host.' }
Write-Host 'PASS: UMA source syntax, installer guards, model specs and legacy context invariants.' -ForegroundColor Green
