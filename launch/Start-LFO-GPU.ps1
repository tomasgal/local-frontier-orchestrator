param([string]$InstallRoot)
if ([string]::IsNullOrWhiteSpace($InstallRoot)) { $InstallRoot = Split-Path -Parent $PSScriptRoot }
& (Join-Path $PSScriptRoot 'Start-LFO.ps1') -Profile GPU -InstallRoot $InstallRoot
exit $LASTEXITCODE
