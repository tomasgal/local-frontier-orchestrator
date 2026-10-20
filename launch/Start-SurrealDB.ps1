param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'LFO'),
    [string]$LogDirectory
)

$ErrorActionPreference = 'Stop'
chcp 65001 > $null

$statePath = Join-Path $InstallRoot 'config\install-state.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "LFO install state not found: $statePath" }
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
$binary = [string]$state.SurrealDB.Executable
$data = [string]$state.SurrealDB.DataDirectory
$port = [int]$state.SurrealDB.Port
$credentialPath = [string]$state.SurrealDB.BootstrapCredentialPath
$baseUri='http://127.0.0.1:'+$port
if (-not (Test-Path -LiteralPath $binary -PathType Leaf)) { throw "SurrealDB executable not found: $binary" }
if (-not (Test-Path -LiteralPath $data -PathType Container)) { throw "SurrealDB data directory not found: $data" }
if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) { throw "SurrealDB bootstrap credential not found: $credentialPath" }

try {
    $null=Invoke-RestMethod -Uri ($baseUri+'/ready') -TimeoutSec 2
    Write-Host ("SurrealDB already ready at {0}; no new process started." -f $baseUri) -ForegroundColor Green
    exit 0
} catch {}

if([string]::IsNullOrWhiteSpace($LogDirectory)){$LogDirectory=Join-Path $InstallRoot 'runtime\logs\services'}
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout=Join-Path $LogDirectory ('surrealdb-'+$stamp+'.stdout.log')
$stderr=Join-Path $LogDirectory ('surrealdb-'+$stamp+'.stderr.log')

$credential = Import-Clixml -LiteralPath $credentialPath
$dbPath='rocksdb://' + (Join-Path ([IO.Path]::GetFullPath($data)) 'observations.db').Replace('\','/')
$args=@('start','--bind',('127.0.0.1:'+$port),'--query-timeout','3s','--deny-guests','--deny-scripting','--deny-net','--log','info',$dbPath)
function Quote-Arg([string]$Text){return '"' + $Text.Replace('"','\"') + '"'}
$argLine=(@($args|ForEach-Object{Quote-Arg ([string]$_)}) -join ' ')

$oldUser=$env:SURREAL_USER;$oldPass=$env:SURREAL_PASS
try {
    $env:SURREAL_USER=$credential.UserName
    $env:SURREAL_PASS=$credential.GetNetworkCredential().Password
    $p=Start-Process -FilePath $binary -ArgumentList $argLine -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
} finally {
    $env:SURREAL_USER=$oldUser
    $env:SURREAL_PASS=$oldPass
}

$deadline=(Get-Date).AddSeconds(60)
$lineOpen=$false
do {
    try {
        $null=Invoke-RestMethod -Uri ($baseUri+'/ready') -TimeoutSec 2
        if($lineOpen){Write-Host ''}
        Write-Host ("SurrealDB ready headless: PID {0}; endpoint={1}" -f $p.Id,$baseUri) -ForegroundColor Green
        Write-Host "stdout: $stdout"
        Write-Host "stderr: $stderr"
        exit 0
    } catch {}
    if(-not $lineOpen){Write-Host 'Waiting for SurrealDB.' -NoNewline -ForegroundColor Cyan;$lineOpen=$true}else{Write-Host '.' -NoNewline -ForegroundColor DarkGray}
    Start-Sleep -Seconds 1
} while((Get-Date) -lt $deadline)
if($lineOpen){Write-Host ''}
try{Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue}catch{}
throw "SurrealDB did not become ready at $baseUri within 60 seconds. See $stderr"
