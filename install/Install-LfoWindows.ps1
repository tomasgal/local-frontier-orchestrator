param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'LocalFrontierOrchestrator'),
    [ValidateSet('GPU','CPU')][string]$DefaultProfile = 'GPU',
    [string]$Repository = 'https://github.com/tomasgal/local-frontier-orchestrator.git',
    [string]$Ref = 'main',
    [ValidatePattern('^[A-Za-z0-9._:/-]{1,128}$')][string]$Model = 'qwen3.5:4b-q4_K_M',
    [switch]$SkipModelPull,
    [switch]$RequireCodex
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$OllamaVersion='0.34.4'
$OllamaUrl='https://github.com/ollama/ollama/releases/download/v0.34.4/ollama-windows-amd64.zip'
$OllamaSha256='535193f38f3344e5b08f5d1c171c31ce11aa17f0124ff69ae26d8ec7fe06fa62'
$SurrealVersion='3.3.0'
$SurrealUrl='https://github.com/surrealdb/surrealdb/releases/download/v3.3.0/surreal-v3.3.0.windows-amd64.exe'
$SurrealSha256='3e5e9d363a352be81f5a983d53f0bc0cd77a90e305f01e2fed929987cf79735c'

function Write-Step([string]$Text){Write-Host '';Write-Host ('==> '+$Text) -ForegroundColor Cyan}
function Assert-FileHash([string]$Path,[string]$Expected,[string]$Name){
    $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -cne $Expected.ToLowerInvariant()){throw "$Name checksum mismatch. Expected $Expected, got $actual"}
}
function Invoke-LfoDownload([string]$Url,[string]$OutFile){
    $parent=Split-Path -Parent $OutFile
    if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
    if(Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue){
        Start-BitsTransfer -Source $Url -Destination $OutFile -DisplayName 'LFO bootstrap download' -ErrorAction Stop
    }else{
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $OutFile
    }
}
function Test-LfoPort([int]$Port){
    $c=New-Object Net.Sockets.TcpClient
    try{$c.Connect('127.0.0.1',$Port);return $true}catch{return $false}finally{$c.Dispose()}
}
function Get-FreeLfoPort([int]$Start,[int]$End){
    for($p=$Start;$p -le $End;$p++){if(-not(Test-LfoPort $p)){return $p}}
    throw "No free loopback port in range $Start-$End."
}
function Get-GitCandidates {
    return @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'),
        ([Environment]::ExpandEnvironmentVariables('%ProgramFiles(x86)%\Git\cmd\git.exe')),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    )
}
function Resolve-Git {
    $cmd=Get-Command git.exe -ErrorAction SilentlyContinue|Select-Object -First 1
    if($cmd){return [string]$cmd.Source}
    foreach($p in @(Get-GitCandidates)){if($p -and (Test-Path -LiteralPath $p -PathType Leaf)){return $p}}
    $winget=Get-Command winget.exe -ErrorAction SilentlyContinue|Select-Object -First 1
    if(-not $winget){throw 'Git is missing and winget is unavailable. Install Git for Windows, then rerun this bootstrap.'}
    Write-Step 'Installing Git for Windows via winget'
    & $winget.Source install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent
    if($LASTEXITCODE -ne 0){throw "winget Git installation failed with exit code $LASTEXITCODE"}
    foreach($p in @(Get-GitCandidates)){if($p -and (Test-Path -LiteralPath $p -PathType Leaf)){return $p}}
    throw 'Git installation completed but git.exe could not be located.'
}
function Test-WindowsSqlite {
    if(-not('LfoBootstrapWinSqliteV1' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LfoBootstrapWinSqliteV1 {
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)]
  public static extern IntPtr sqlite3_libversion();
}
'@
    }
    $p=[LfoBootstrapWinSqliteV1]::sqlite3_libversion()
    if($p -eq [IntPtr]::Zero){throw 'winsqlite3.dll loaded but sqlite3_libversion returned null.'}
    $ver=[Runtime.InteropServices.Marshal]::PtrToStringAnsi($p)
    if([string]::IsNullOrWhiteSpace($ver)){throw 'Windows SQLite version could not be read.'}
    return $ver
}
function Escape-Psd1SingleQuoted([string]$Value){return $Value.Replace("'","''")}
function Write-RootLauncher([string]$Path,[string]$Profile,[string]$AppRoot,[string]$Root){
    $app=Escape-Psd1SingleQuoted $AppRoot
    $home=Escape-Psd1SingleQuoted $Root
    $text='param()'+[Environment]::NewLine+"& '$app\launch\Start-LfoWindows.ps1' -InstallRoot '$home' -Profile '$Profile'"+[Environment]::NewLine
    [IO.File]::WriteAllText($Path,$text,(New-Object Text.UTF8Encoding($false)))
}

Write-Step 'Preflight'
if($env:OS -ne 'Windows_NT'){throw 'This bootstrap supports Windows only.'}
if($PSVersionTable.PSVersion -lt [version]'5.1'){throw 'Windows PowerShell 5.1 or newer is required.'}
if(-[Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess){throw 'Use a 64-bit PowerShell process on 64-bit Windows.'}
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
try{chcp.com 65001|Out-Null}catch{}
$OutputEncoding=New-Object Text.UTF8Encoding($false)
[Console]::InputEncoding=New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)

$InstallRoot=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallRoot))
$drive=[IO.Path]::GetPathRoot($InstallRoot)
$driveInfo=Get-PSDrive -Name $drive.Substring(0,1) -ErrorAction Stop
$freeGB=[math]::Round($driveInfo.Free/1GB,2)
if($freeGB -lt 8){throw "At least 8 GiB free space is required; detected $freeGB GiB."}
if($freeGB -lt 12){Write-Warning "Only $freeGB GiB free. 12+ GiB is recommended."}
$sqliteVersion=Test-WindowsSqlite
Write-Host ("Windows={0}; PowerShell={1}; SQLite={2}; free={3} GiB" -f [Environment]::OSVersion.Version,$PSVersionTable.PSVersion,$sqliteVersion,$freeGB)

$git=Resolve-Git
$gitVersion=& $git --version
if($LASTEXITCODE -ne 0){throw 'Git preflight failed.'}
Write-Host $gitVersion

$codex=Get-Command codex.cmd,codex -ErrorAction SilentlyContinue|Select-Object -First 1
if($RequireCodex -and -not $codex){throw 'Codex CLI is required by -RequireCodex but was not found.'}
if($codex){Write-Host ("Codex CLI: {0}" -f $codex.Source)}else{Write-Warning 'Codex CLI not found. LOCAL LFO remains usable; FRONTIER routing requires a separately authenticated Codex CLI.'}

$runtimeRoot=Join-Path $InstallRoot 'runtime'
$cacheRoot=Join-Path $InstallRoot 'cache'
$appRoot=Join-Path $InstallRoot 'app'
$modelsDir=Join-Path $InstallRoot 'models'
$stateRoot=Join-Path $InstallRoot 'state'
$memoryRoot=Join-Path $stateRoot 'memory'
$l4Workspace=Join-Path $stateRoot 'l4'
foreach($d in @($InstallRoot,$runtimeRoot,$cacheRoot,$modelsDir,$stateRoot,$memoryRoot)){New-Item -ItemType Directory -Force -Path $d|Out-Null}

Write-Step "Installing portable Ollama $OllamaVersion"
$ollamaZip=Join-Path $cacheRoot "ollama-windows-amd64-$OllamaVersion.zip"
if(-not(Test-Path -LiteralPath $ollamaZip -PathType Leaf)){Invoke-LfoDownload $OllamaUrl $ollamaZip}
Assert-FileHash $ollamaZip $OllamaSha256 'Ollama archive'
$ollamaDir=Join-Path $runtimeRoot "ollama-$OllamaVersion"
$ollamaExe=Join-Path $ollamaDir 'ollama.exe'
if(-not(Test-Path -LiteralPath $ollamaExe -PathType Leaf)){
    $tmp=Join-Path $runtimeRoot ("ollama-expand-"+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp|Out-Null
    try{
        Expand-Archive -LiteralPath $ollamaZip -DestinationPath $tmp -Force
        $found=Get-ChildItem -LiteralPath $tmp -Filter ollama.exe -File -Recurse|Select-Object -First 1
        if(-not $found){throw 'ollama.exe was not found in the verified archive.'}
        if(Test-Path -LiteralPath $ollamaDir){Remove-Item -LiteralPath $ollamaDir -Recurse -Force}
        New-Item -ItemType Directory -Force -Path $ollamaDir|Out-Null
        Copy-Item -Path (Join-Path $found.Directory.FullName '*') -Destination $ollamaDir -Recurse -Force
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Recurse -Force}}
}
if(-not(Test-Path -LiteralPath $ollamaExe -PathType Leaf)){throw 'Portable Ollama installation failed.'}
$ov=& $ollamaExe --version 2>&1
Write-Host ("Ollama binary: {0}" -f ($ov -join ' '))

Write-Step "Installing SurrealDB $SurrealVersion"
$surrealDir=Join-Path $runtimeRoot "surrealdb-$SurrealVersion"
New-Item -ItemType Directory -Force -Path $surrealDir|Out-Null
$surrealExe=Join-Path $surrealDir 'surreal.exe'
if(-not(Test-Path -LiteralPath $surrealExe -PathType Leaf)){Invoke-LfoDownload $SurrealUrl $surrealExe}
Assert-FileHash $surrealExe $SurrealSha256 'SurrealDB executable'
$sv=& $surrealExe version 2>&1
if(($sv -join ' ') -notmatch '3\.3\.0'){throw "Unexpected SurrealDB version: $($sv -join ' ')"}
Write-Host ("SurrealDB binary: {0}" -f ($sv -join ' '))

Write-Step "Checking out LFO ref '$Ref'"
if(Test-Path -LiteralPath $appRoot){
    if(-not(Test-Path -LiteralPath (Join-Path $appRoot '.git') -PathType Container)){throw "Install app directory exists but is not a Git checkout: $appRoot"}
    $dirty=& $git -C $appRoot status --porcelain
    if($LASTEXITCODE -ne 0){throw 'Existing LFO checkout is unreadable.'}
    if($dirty){throw 'Existing LFO install checkout has local changes; bootstrap will not overwrite them.'}
}else{
    & $git clone --no-checkout $Repository $appRoot
    if($LASTEXITCODE -ne 0){throw 'LFO clone failed.'}
}
& $git -C $appRoot fetch --force --tags origin $Ref
if($LASTEXITCODE -ne 0){throw "Unable to fetch LFO ref '$Ref'."}
& $git -C $appRoot checkout --detach --force FETCH_HEAD
if($LASTEXITCODE -ne 0){throw "Unable to check out LFO ref '$Ref'."}
$commit=(& $git -C $appRoot rev-parse HEAD).Trim()
Write-Host ("LFO commit: {0}" -f $commit)

Write-Step 'Verifying LFO SQLite store ABI with an actual database'
. (Join-Path $appRoot 'src\LfoMemoryStore.ps1')
$sqliteTest=Join-Path $env:TEMP ("lfo-bootstrap-sqlite-"+[guid]::NewGuid().ToString('N')+".db")
$conn=$null
try{
    $conn=Open-LfoSqliteDatabase $sqliteTest
    Invoke-LfoSqliteExec $conn 'CREATE TABLE bootstrap_check(id INTEGER PRIMARY KEY, value TEXT NOT NULL); INSERT INTO bootstrap_check(value) VALUES (''ok'');'
    $rows=@(Invoke-LfoSqliteQuery $conn 'SELECT value FROM bootstrap_check WHERE id=1;' @())
    if($rows.Count -ne 1 -or [string]$rows[0].value -cne 'ok'){throw 'SQLite read/write verification returned unexpected data.'}
}finally{if($conn){Close-LfoSqliteDatabase $conn};Remove-Item -LiteralPath $sqliteTest -Force -ErrorAction SilentlyContinue}
Write-Host 'SQLite ABI/open/write/read: PASS'

$ollamaPort=Get-FreeLfoPort 11434 11444
$surrealPort=Get-FreeLfoPort 18080 18090
$ollamaBase='http://127.0.0.1:'+$ollamaPort
$l4Endpoint='http://127.0.0.1:'+$surrealPort
$l4Credential=Join-Path $l4Workspace 'runtime.credential.xml'

Write-Step 'Generating local complete-build configuration'
$templatePath=Join-Path $appRoot 'config\QwenChat.release.template.psd1'
if(-not(Test-Path -LiteralPath $templatePath -PathType Leaf)){throw 'Release config template is missing from the selected LFO ref.'}
$configText=[IO.File]::ReadAllText($templatePath,[Text.Encoding]::UTF8)
$configText=$configText.Replace('__LFO_MODEL__',(Escape-Psd1SingleQuoted $Model))
$configText=$configText.Replace('__LFO_OLLAMA_BASEURI__',$ollamaBase)
$configText=$configText.Replace('__LFO_DATA_DIRECTORY__',(Escape-Psd1SingleQuoted $memoryRoot))
$configText=$configText.Replace('__LFO_L4_ENDPOINT__',$l4Endpoint)
$configText=$configText.Replace('__LFO_L4_CREDENTIAL__',(Escape-Psd1SingleQuoted $l4Credential))
$configDir=Join-Path $InstallRoot 'config'
New-Item -ItemType Directory -Force -Path $configDir|Out-Null
$qwenConfig=Join-Path $configDir 'QwenChat.release.psd1'
[IO.File]::WriteAllText($qwenConfig,$configText,(New-Object Text.UTF8Encoding($false)))

$installState=[ordered]@{
    schema='lfo-windows-install-v1'
    installed_at=[DateTime]::UtcNow.ToString('o')
    install_root=$InstallRoot
    repository=$Repository
    requested_ref=$Ref
    commit=$commit
    git_exe=$git
    repo_root=$appRoot
    qwen_config=$qwenConfig
    ollama_version=$OllamaVersion
    ollama_exe=$ollamaExe
    ollama_port=$ollamaPort
    models_dir=$modelsDir
    model=$Model
    surreal_version=$SurrealVersion
    surreal_exe=$surrealExe
    surreal_port=$surrealPort
    l4_workspace=$l4Workspace
    l4_runtime_credential=$l4Credential
    default_profile=$DefaultProfile
    sqlite_version=$sqliteVersion
    codex_found=[bool]$codex
}
$statePath=Join-Path $InstallRoot 'install-state.json'
[IO.File]::WriteAllText($statePath,($installState|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
Write-RootLauncher (Join-Path $InstallRoot 'Start-LFO-GPU.ps1') 'GPU' $appRoot $InstallRoot
Write-RootLauncher (Join-Path $InstallRoot 'Start-LFO-CPU.ps1') 'CPU' $appRoot $InstallRoot

Write-Step 'Starting visible Ollama and SurrealDB consoles'
& (Join-Path $appRoot 'launch\Start-LfoWindows.ps1') -InstallRoot $InstallRoot -Profile $DefaultProfile -NoChat

if(-not $SkipModelPull){
    Write-Step "Pulling local model $Model"
    $oldHost=$env:OLLAMA_HOST
    $oldModels=$env:OLLAMA_MODELS
    try{
        $env:OLLAMA_HOST='127.0.0.1:'+$ollamaPort
        $env:OLLAMA_MODELS=$modelsDir
        & $ollamaExe pull $Model
        if($LASTEXITCODE -ne 0){throw "Ollama model pull failed with exit code $LASTEXITCODE"}
    }finally{
        if($null -eq $oldHost){Remove-Item Env:OLLAMA_HOST -ErrorAction SilentlyContinue}else{$env:OLLAMA_HOST=$oldHost}
        if($null -eq $oldModels){Remove-Item Env:OLLAMA_MODELS -ErrorAction SilentlyContinue}else{$env:OLLAMA_MODELS=$oldModels}
    }
}

Write-Step 'Running zero-model installed-build preflight'
$preflightReport=Join-Path $InstallRoot 'build-preflight-report.json'
& (Join-Path $appRoot 'tools\Test-LfoWindowsBuildPreflight.ps1') -InstallRoot $InstallRoot -ResultPath $preflightReport
if($LASTEXITCODE -ne 0){throw 'Installed-build preflight failed.'}

Write-Step 'Bootstrap complete'
Write-Host ("Install root: {0}" -f $InstallRoot)
Write-Host ("LFO commit:   {0}" -f $commit)
Write-Host ("Ollama:       {0}" -f $ollamaBase)
Write-Host ("SurrealDB:    {0}" -f $l4Endpoint)
Write-Host ("GPU launcher: {0}" -f (Join-Path $InstallRoot 'Start-LFO-GPU.ps1'))
Write-Host ("CPU launcher: {0}" -f (Join-Path $InstallRoot 'Start-LFO-CPU.ps1'))
Write-Host ("Preflight:    {0}" -f $preflightReport)
Write-Host 'No existing service process was stopped. L4 policy/intervention remains default-OFF.'
