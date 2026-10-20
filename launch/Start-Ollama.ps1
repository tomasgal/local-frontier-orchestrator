param(
    [string]$OllamaExe = $env:LFO_OLLAMA_EXE,
    [string]$ModelsDirectory = $env:LFO_OLLAMA_MODELS,
    [string]$HostAddress = '127.0.0.1:11434',
    [int]$ContextLength = 32768,
    [int]$NumParallel = 1,
    [int]$MaxLoadedModels = 1,
    [string]$LogDirectory = (Join-Path $env:LOCALAPPDATA 'LFO\runtime\logs\services'),
    [switch]$AllowCloud
)

$ErrorActionPreference = 'Stop'
chcp 65001 > $null

if ([string]::IsNullOrWhiteSpace($OllamaExe)) {
    $cmd = Get-Command ollama.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) { $cmd = Get-Command ollama -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($null -eq $cmd) { throw 'Ollama was not found on PATH. Pass -OllamaExe or set LFO_OLLAMA_EXE.' }
    $OllamaExe = if ($cmd.Source) { [string]$cmd.Source } else { [string]$cmd.Path }
}
if (-not (Test-Path -LiteralPath $OllamaExe -PathType Leaf)) { throw "Ollama executable not found: $OllamaExe" }

$parts=$HostAddress.Split(':')
$port=[int]$parts[$parts.Count-1]
$baseUri='http://127.0.0.1:'+$port
try {
    $v=Invoke-RestMethod -Uri ($baseUri+'/api/version') -TimeoutSec 2
    Write-Host ("Ollama already ready at {0} (version={1}); no new process started." -f $baseUri,$v.version) -ForegroundColor Green
    exit 0
} catch {}

New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout=Join-Path $LogDirectory ('ollama-'+$stamp+'.stdout.log')
$stderr=Join-Path $LogDirectory ('ollama-'+$stamp+'.stderr.log')

$old=@{
    OLLAMA_HOST=$env:OLLAMA_HOST
    OLLAMA_MODELS=$env:OLLAMA_MODELS
    OLLAMA_CONTEXT_LENGTH=$env:OLLAMA_CONTEXT_LENGTH
    OLLAMA_NUM_PARALLEL=$env:OLLAMA_NUM_PARALLEL
    OLLAMA_MAX_LOADED_MODELS=$env:OLLAMA_MAX_LOADED_MODELS
    OLLAMA_NO_CLOUD=$env:OLLAMA_NO_CLOUD
    OLLAMA_DEBUG=$env:OLLAMA_DEBUG
}
try {
    $env:OLLAMA_HOST=$HostAddress
    if (-not [string]::IsNullOrWhiteSpace($ModelsDirectory)) {
        New-Item -ItemType Directory -Force -Path $ModelsDirectory | Out-Null
        $env:OLLAMA_MODELS=$ModelsDirectory
    } else {
        Remove-Item Env:OLLAMA_MODELS -ErrorAction SilentlyContinue
    }
    $env:OLLAMA_CONTEXT_LENGTH=[string]$ContextLength
    $env:OLLAMA_NUM_PARALLEL=[string]$NumParallel
    $env:OLLAMA_MAX_LOADED_MODELS=[string]$MaxLoadedModels
    $env:OLLAMA_NO_CLOUD=$(if($AllowCloud){'0'}else{'1'})
    $env:OLLAMA_DEBUG='0'
    $p=Start-Process -FilePath $OllamaExe -ArgumentList 'serve' -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
} finally {
    foreach($k in $old.Keys){[Environment]::SetEnvironmentVariable($k,$old[$k],'Process')}
}

$deadline=(Get-Date).AddSeconds(60)
$lineOpen=$false
do {
    try {
        $v=Invoke-RestMethod -Uri ($baseUri+'/api/version') -TimeoutSec 2
        if($lineOpen){Write-Host ''}
        Write-Host ("Ollama ready headless: PID {0}; version={1}" -f $p.Id,$v.version) -ForegroundColor Green
        Write-Host "stdout: $stdout"
        Write-Host "stderr: $stderr"
        exit 0
    } catch {}
    if(-not $lineOpen){Write-Host 'Waiting for Ollama.' -NoNewline -ForegroundColor Cyan;$lineOpen=$true}else{Write-Host '.' -NoNewline -ForegroundColor DarkGray}
    Start-Sleep -Seconds 1
} while((Get-Date) -lt $deadline)
if($lineOpen){Write-Host ''}
try{Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}catch{}
throw "Ollama did not become ready at $baseUri within 60 seconds. See $stderr"
