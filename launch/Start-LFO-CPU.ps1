param([string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'LFO'))
& (Join-Path $PSScriptRoot 'Start-LFO.ps1') -Profile CPU -InstallRoot $InstallRoot
exit $LASTEXITCODE
