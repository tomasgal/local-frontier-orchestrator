param(
    [ValidateSet('GPU','CPU')][string]$Profile,
    [string]$InstallRoot,
    [switch]$NoChat
)

if ([string]::IsNullOrWhiteSpace($InstallRoot)) { $InstallRoot = Split-Path -Parent $PSScriptRoot }
$ErrorActionPreference = 'Stop'
chcp 65001 > $null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

function Wait-LfoReady([scriptblock]$Probe,[string]$Name,[int]$Seconds=30) {
    $deadline=(Get-Date).AddSeconds($Seconds)
    do { try { & $Probe | Out-Null; return } catch { Start-Sleep -Milliseconds 300 } } while ((Get-Date) -lt $deadline)
    throw "$Name did not become ready within $Seconds seconds."
}
function Open-Monitor([string]$Service,[string]$BaseUri,[string]$MonitorPath) {
    Start-Process powershell.exe -WindowStyle Normal -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$MonitorPath,'-Service',$Service,'-BaseUri',$BaseUri) | Out-Null
}

$statePath = Join-Path $InstallRoot 'config\install-state.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "LFO install state not found: $statePath. Run Install-LFO.ps1 first." }
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Profile)) {
    if ($state.LFO -and $state.LFO.DefaultProfile -in @('CPU','GPU')) { $Profile = [string]$state.LFO.DefaultProfile } else { $Profile = 'GPU' }
}
$monitor = Join-Path $state.AppRoot 'launch\Watch-LFOService.ps1'

Write-Host ''
Write-Host 'Local Frontier Orchestrator (LFO) - Windows runtime' -ForegroundColor Cyan
Write-Host 'Runtime contract: v9.6.1 | accepted Windows bootstrap'
Write-Host 'Local-first path: Qwen via Ollama handles ordinary conversation and routing.'
Write-Host 'Frontier path: authenticated Codex CLI is called only when routing/policy requires stronger or fresh external reasoning.'
Write-Host 'Memory path: local L0/L1/L2/L3 state preserves conversation evidence, working memory and structured retrieval.'
Write-Host 'L4: conservative post-L0 recording is enabled; /analyze is manual; P1/P2 response intervention remains OFF.'
Write-Host 'Service policy: reuse compatible running services where safe; do not stop unrelated services.'
Write-Host ("Selected profile: {0}" -f $Profile)
Write-Host ''

# Ollama: reuse a compatible existing listener. If absent, start the configured executable visibly.
$ollamaUri = [string]$state.Ollama.BaseUri
$ollamaReady = $false
try { $null = Invoke-RestMethod -Uri ($ollamaUri.TrimEnd('/') + '/api/version') -TimeoutSec 2; $ollamaReady = $true } catch {}
if ($ollamaReady) {
    Open-Monitor 'Ollama' $ollamaUri $monitor
} else {
    $startOllama = Join-Path $state.AppRoot 'launch\Start-Ollama.ps1'
    $args = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',$startOllama,'-OllamaExe',[string]$state.Ollama.Executable,'-HostAddress',[string]$state.Ollama.HostAddress,'-ContextLength','8192','-NumParallel','1','-MaxLoadedModels','1')
    if (-not [string]::IsNullOrWhiteSpace([string]$state.Ollama.ModelsDirectory)) { $args += @('-ModelsDirectory',[string]$state.Ollama.ModelsDirectory) }
    Start-Process powershell.exe -WindowStyle Normal -ArgumentList $args | Out-Null
    Wait-LfoReady { Invoke-RestMethod -Uri ($ollamaUri.TrimEnd('/') + '/api/version') -TimeoutSec 2 } 'Ollama' 60
}

# SurrealDB: only an LFO-owned datastore is reused. Otherwise start it visibly.
$surrealUri = [string]$state.SurrealDB.BaseUri
$surrealReady = $false
try {
    $runtimeCredential = Import-Clixml -LiteralPath ([string]$state.SurrealDB.RuntimeCredentialPath)
    . (Join-Path $state.AppRoot 'src\LfoEpistemicStore.ps1')
    $conn = New-LfoEpistemicConnection $surrealUri $runtimeCredential
    $null = Invoke-LfoEpistemicQuery $conn 'RETURN 1;'
    $surrealReady = $true
} catch {}
if ($surrealReady) {
    Open-Monitor 'SurrealDB' $surrealUri $monitor
} else {
    $startSurreal = Join-Path $state.AppRoot 'launch\Start-SurrealDB.ps1'
    Start-Process powershell.exe -WindowStyle Normal -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',$startSurreal,'-InstallRoot',$InstallRoot) | Out-Null
    Wait-LfoReady { Invoke-RestMethod -Uri ($surrealUri.TrimEnd('/') + '/ready') -TimeoutSec 2 } 'SurrealDB' 60
}

if ($NoChat) { return }
$model = if ($Profile -eq 'CPU') { [string]$state.Ollama.CPUModel } else { [string]$state.Ollama.GPUModel }
$ctx = if ($Profile -eq 'CPU') { 5120 } else { 8192 }
$env:LFO_INSTALL_ROOT = $InstallRoot
$env:LFO_L4_ENABLED = '1'
$env:LFO_L4_ENDPOINT = $surrealUri
$env:LFO_L4_RUNTIME_CREDENTIAL = [string]$state.SurrealDB.RuntimeCredentialPath
$env:LFO_L4_OBSERVABILITY = '1'
$chat = Join-Path $state.AppRoot 'src\QwenChat.ps1'
$config = [string]$state.LFO.ConfigPath
Write-Host "Runtime ready." -ForegroundColor Green
Write-Host "Profile:   $Profile"
Write-Host "Model:     $model"
Write-Host "Ollama:    $ollamaUri"
Write-Host "SurrealDB: $surrealUri"
Write-Host "L4:        recording enabled; /analyze manual; P2 OFF"
Write-Host "Config:    $config"
Write-Host ''
& $chat -Model $model -ConfigPath $config -ContextLengthHint $ctx
exit $LASTEXITCODE
