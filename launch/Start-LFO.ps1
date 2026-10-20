param(
    [ValidateSet('GPU','CPU')][string]$Profile,
    [string]$InstallRoot,
    [switch]$NoChat
)

if ([string]::IsNullOrWhiteSpace($InstallRoot)) { $InstallRoot = Split-Path -Parent $PSScriptRoot }
if ($NoChat) { throw '-NoChat is not supported by the v9.6.3 compatibility launcher. Start the required service explicitly instead.' }

$statePath = Join-Path $InstallRoot 'config\install-state.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "LFO install state not found: $statePath. Run Install-LFO.ps1 first." }
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Profile)) {
    if ($state.LFO -and [string]$state.LFO.DefaultProfile -in @('CPU','GPU')) { $Profile = [string]$state.LFO.DefaultProfile } else { $Profile = 'GPU' }
}
$lfo = Join-Path ([string]$state.AppRoot) 'LFO.ps1'
if (-not (Test-Path -LiteralPath $lfo -PathType Leaf)) { $lfo = Join-Path $PSScriptRoot 'LFO.ps1' }
if (-not (Test-Path -LiteralPath $lfo -PathType Leaf)) { throw 'v9.6.3 LFO.ps1 entrypoint is missing. Rerun the current bootstrap.' }
& $lfo -Device $Profile -InstallRoot $InstallRoot
exit $LASTEXITCODE
