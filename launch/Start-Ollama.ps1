param(
    [string]$OllamaExe = $env:LFO_OLLAMA_EXE,
    [string]$ModelsDirectory = $env:LFO_OLLAMA_MODELS,
    [string]$HostAddress = '127.0.0.1:11434',
    [int]$ContextLength = 32768,
    [int]$NumParallel = 1,
    [int]$MaxLoadedModels = 1,
    [switch]$AllowCloud
)

$ErrorActionPreference = 'Stop'

chcp 65001 > $null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

if ([string]::IsNullOrWhiteSpace($OllamaExe)) {
    $cmd = Get-Command ollama.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) {
        $cmd = Get-Command ollama -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($null -eq $cmd) {
        throw 'Ollama was not found on PATH. Pass -OllamaExe or set LFO_OLLAMA_EXE.'
    }
    $OllamaExe = if ($cmd.Source) { [string]$cmd.Source } else { [string]$cmd.Path }
}

if (-not (Test-Path -LiteralPath $OllamaExe)) {
    throw "Ollama executable not found: $OllamaExe"
}

if ([string]::IsNullOrWhiteSpace($ModelsDirectory)) {
    $ModelsDirectory = Join-Path $env:LOCALAPPDATA 'local-frontier-orchestrator\models'
}

New-Item -ItemType Directory -Force -Path $ModelsDirectory | Out-Null

$env:OLLAMA_HOST = $HostAddress
$env:OLLAMA_MODELS = $ModelsDirectory
$env:OLLAMA_CONTEXT_LENGTH = [string]$ContextLength
$env:OLLAMA_NUM_PARALLEL = [string]$NumParallel
$env:OLLAMA_MAX_LOADED_MODELS = [string]$MaxLoadedModels
$env:OLLAMA_NO_CLOUD = $(if ($AllowCloud) { '0' } else { '1' })

Write-Host "Starting Ollama"
Write-Host "Host: $env:OLLAMA_HOST"
Write-Host "Models: $env:OLLAMA_MODELS"
Write-Host "Default context ceiling: $env:OLLAMA_CONTEXT_LENGTH"
Write-Host "Parallel requests: $env:OLLAMA_NUM_PARALLEL"
Write-Host "Max loaded models: $env:OLLAMA_MAX_LOADED_MODELS"
Write-Host "Cloud disabled: $env:OLLAMA_NO_CLOUD"
Write-Host "Press Ctrl+C to stop."
Write-Host ""

& $OllamaExe serve
exit $LASTEXITCODE
