param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'LFO')
)

$ErrorActionPreference = 'Stop'
chcp 65001 > $null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

$statePath = Join-Path $InstallRoot 'config\install-state.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "LFO install state not found: $statePath" }
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
$binary = [string]$state.SurrealDB.Executable
$data = [string]$state.SurrealDB.DataDirectory
$port = [int]$state.SurrealDB.Port
$credentialPath = [string]$state.SurrealDB.BootstrapCredentialPath
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw "SurrealDB executable not found: $binary" }
if (-not (Test-Path -LiteralPath $data -PathType Container)) { throw "SurrealDB data directory not found: $data" }
if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) { throw "SurrealDB bootstrap credential not found: $credentialPath" }
$credential = Import-Clixml -LiteralPath $credentialPath
$env:SURREAL_USER = $credential.UserName
$env:SURREAL_PASS = $credential.GetNetworkCredential().Password
$server = Join-Path $state.AppRoot 'tools\Start-LfoEpistemicServer.ps1'
if (-not (Test-Path -LiteralPath $server -PathType Leaf)) { throw "LFO SurrealDB launcher not found: $server" }
$Host.UI.RawUI.WindowTitle = "LFO | SurrealDB $($state.SurrealDB.Version) | 127.0.0.1:$port"
Write-Host "LFO SurrealDB foreground server" -ForegroundColor Cyan
Write-Host "Binary: $binary"
Write-Host "Data:   $data"
Write-Host "Port:   $port"
Write-Host 'Live server output follows. Press Ctrl+C to stop.'
Write-Host ''
& $server -Binary $binary -DataDirectory $data -Port $port -LogLevel info
exit $LASTEXITCODE
