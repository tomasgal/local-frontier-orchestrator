[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'LFO'),
    [string]$SourceRef = 'main',
    [ValidateSet('CPU','GPU')][string]$Profile = 'GPU',
    [string]$BaseModel = 'qwen3.5:4b-q4_K_M',
    [switch]$SkipModelPull,
    [switch]$SkipL4Acceptance,
    [switch]$SkipLaunch
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
chcp 65001 > $null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

$RepoUrl = 'https://github.com/tomasgal/local-frontier-orchestrator.git'
$OllamaMinVersion = [version]'0.34.4'
$OllamaPinnedVersion = '0.34.4'
$OllamaUrl = 'https://github.com/ollama/ollama/releases/download/v0.34.4/ollama-windows-amd64.zip'
$OllamaSHA256 = '535193f38f3344e5b08f5d1c171c31ce11aa17f0124ff69ae26d8ec7fe06fa62'
$SurrealVersion = '3.3.0'
$SurrealUrl = 'https://github.com/surrealdb/surrealdb/releases/download/v3.3.0/surreal-v3.3.0.windows-amd64.exe'
$SurrealSHA256 = '3e5e9d363a352be81f5a983d53f0bc0cd77a90e305f01e2fed929987cf79735c'
$GpuModel = 'lfo-qwen3.5-4b-gpu8k:latest'
$CpuModel = 'lfo-qwen3.5-4b-cpu5k:latest'
$RuntimeContract = 'v9.6.3'

function Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Info([string]$Text) { Write-Host "    $Text" }
function Warn([string]$Text) { Write-Host "WARNING: $Text" -ForegroundColor Yellow }
function Assert-Lfo($Value,[string]$Message) { if (-not [bool]$Value) { throw $Message } }
function Get-Sha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Quote-PsSingle([string]$Text) { return $Text.Replace("'","''") }
function Wait-Ready([scriptblock]$Probe,[string]$Name,[int]$Seconds=60) {
    $deadline=(Get-Date).AddSeconds($Seconds)
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $nextProgress=5.0
    $progressLineOpen=$false
    do {
        try {
            & $Probe | Out-Null
            if($progressLineOpen){Write-Host ''}
            $sw.Stop()
            return
        } catch {}
        if($sw.Elapsed.TotalSeconds -ge $nextProgress){
            if(-not $progressLineOpen){
                Write-Host ("Waiting for {0}." -f $Name) -NoNewline -ForegroundColor Cyan
                $progressLineOpen=$true
            } else {
                Write-Host '.' -NoNewline -ForegroundColor DarkGray
            }
            $nextProgress += 5.0
        }
        Start-Sleep -Milliseconds 350
    } while ((Get-Date) -lt $deadline)
    if($progressLineOpen){Write-Host ''}
    $sw.Stop()
    throw "$Name did not become ready within $Seconds seconds."
}
function Get-FreePort([int]$Preferred) {
    foreach($p in $Preferred..($Preferred+40)) {
        $used = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue)
        if ($used.Count -eq 0) { return $p }
    }
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
    $listener.Start(); try { return [int]$listener.LocalEndpoint.Port } finally { $listener.Stop() }
}
function Get-ApiVersion([string]$Uri) {
    try { return [string](Invoke-RestMethod -Uri ($Uri.TrimEnd('/')+'/api/version') -TimeoutSec 2).version } catch { return $null }
}
function Parse-SemVer([string]$Text) {
    if ($Text -match '(\d+\.\d+\.\d+)') { try { return [version]$matches[1] } catch {} }
    return $null
}
function Get-OllamaExeVersion([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
        $out=(& $Path --version 2>&1 | Out-String).Trim()
        $ErrorActionPreference=$old
        if ($LASTEXITCODE -ne 0) { return $null }
        return Parse-SemVer $out
    } catch { return $null }
}
function Get-OllamaLibraryManifestPath([string]$Store,[string]$Model) {
    if ([string]::IsNullOrWhiteSpace($Store) -or [string]::IsNullOrWhiteSpace($Model)) { return $null }
    $name=$Model;$tag='latest'
    $colon=$Model.LastIndexOf(':')
    if($colon -gt 0){$name=$Model.Substring(0,$colon);$tag=$Model.Substring($colon+1)}
    if($name.IndexOf('/') -ge 0 -or $name.IndexOf('\') -ge 0){return $null}
    return Join-Path $Store ('manifests\registry.ollama.ai\library\'+$name+'\'+$tag)
}
function Test-OllamaStoreHasModel([string]$Store,[string]$Model) {
    $manifest=Get-OllamaLibraryManifestPath $Store $Model
    return (-not [string]::IsNullOrWhiteSpace($manifest) -and (Test-Path -LiteralPath $manifest -PathType Leaf))
}
function Resolve-LfoAliasModelStore([string[]]$Candidates,[string[]]$Preferred=@()) {
    $matches=New-Object Collections.Generic.List[string]
    foreach($candidate in @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)){
        try{$full=[IO.Path]::GetFullPath([string]$candidate)}catch{continue}
        if((Test-OllamaStoreHasModel $full $GpuModel) -and (Test-OllamaStoreHasModel $full $CpuModel)){
            if(-not $matches.Contains($full)){$matches.Add($full)}
        }
    }
    foreach($preferred in @($Preferred | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })){
        try{$fullPreferred=[IO.Path]::GetFullPath([string]$preferred)}catch{continue}
        foreach($match in $matches){if($match -ieq $fullPreferred){return $match}}
    }
    if($matches.Count -eq 1){return [string]$matches[0]}
    if($matches.Count -gt 1){throw ('Multiple Ollama model stores contain both LFO aliases: '+(($matches|ForEach-Object{[string]$_}) -join '; ')+'. Set LFO_OLLAMA_MODELS or preserve the intended store in install-state.json before rerunning.')}
    return $null
}
function Get-OllamaApiModelNames([string]$Uri) {
    try {
        $tags=Invoke-RestMethod -Uri ($Uri.TrimEnd('/')+'/api/tags') -TimeoutSec 5
        return @($tags.models | ForEach-Object {[string]$_.name})
    } catch { return @() }
}
function Get-SurrealExeVersion([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $old=$ErrorActionPreference; $ErrorActionPreference='Continue'
        $out=(& $Path version 2>&1 | Out-String).Trim()
        $ErrorActionPreference=$old
        if ($LASTEXITCODE -ne 0) { return $null }
        if ($out -match '(^|\D)3\.3\.0(\D|$)') { return [version]'3.3.0' }
    } catch {}
    return $null
}
function Download-Verified([string]$Uri,[string]$Destination,[string]$Sha256) {
    $parent=Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $tmp=$Destination+'.download-'+[guid]::NewGuid().ToString('N')
    $response=$null;$input=$null;$output=$null
    try {
        $name=[IO.Path]::GetFileName(([uri]$Uri).AbsolutePath)
        if ([string]::IsNullOrWhiteSpace($name)) { $name='artifact' }
        Info "Downloading $Uri"
        $request=[Net.HttpWebRequest]::Create($Uri)
        $request.UserAgent='LFO-Windows-Bootstrap/1.0'
        $request.AllowAutoRedirect=$true
        $request.Timeout=60000
        $request.ReadWriteTimeout=60000
        $response=$request.GetResponse()
        $total=[int64]$response.ContentLength
        $input=$response.GetResponseStream()
        $output=[IO.File]::Open($tmp,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=New-Object byte[] (1024*1024)
        [int64]$done=0
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $lastProgressMs=-1000
        while(($read=$input.Read($buffer,0,$buffer.Length)) -gt 0) {
            $output.Write($buffer,0,$read)
            $done += $read
            if(($sw.ElapsedMilliseconds-$lastProgressMs) -ge 250) {
                $doneMiB=[math]::Round($done/1MB,1)
                $rate=if($sw.Elapsed.TotalSeconds -gt 0){[math]::Round(($done/1MB)/$sw.Elapsed.TotalSeconds,1)}else{0}
                if($total -gt 0) {
                    $totalMiB=[math]::Round($total/1MB,1)
                    $pct=[math]::Min(100,[math]::Floor(($done*100.0)/$total))
                    Write-Progress -Activity ("Downloading "+$name) -Status ("{0} / {1} MiB  ({2} MiB/s)" -f $doneMiB,$totalMiB,$rate) -PercentComplete $pct
                } else {
                    Write-Progress -Activity ("Downloading "+$name) -Status ("{0} MiB downloaded  ({1} MiB/s)" -f $doneMiB,$rate)
                }
                $lastProgressMs=$sw.ElapsedMilliseconds
            }
        }
        $output.Flush($true)
        $output.Dispose(); $output=$null
        $input.Dispose(); $input=$null
        $response.Dispose(); $response=$null
        $sw.Stop()
        Write-Progress -Activity ("Downloading "+$name) -Completed
        Info ("Downloaded {0:N1} MiB; verifying SHA-256..." -f ($done/1MB))
        $actual=Get-Sha256 $tmp
        if ($actual -cne $Sha256.ToLowerInvariant()) { throw "SHA256 mismatch for $Uri. Expected $Sha256, got $actual." }
        Info 'SHA-256 PASS'
        Move-Item -LiteralPath $tmp -Destination $Destination -Force
    } finally {
        if($output){$output.Dispose()}
        if($input){$input.Dispose()}
        if($response){$response.Dispose()}
        Write-Progress -Activity 'Downloading' -Completed -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}
function Resolve-CommandPath([string]$Name) {
    $c=Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { if ($c.Source) { return [string]$c.Source }; return [string]$c.Path }
    return $null
}
function Resolve-CodexPath {
    foreach($name in @('codex.cmd','codex.exe','codex')) {
        $p=Resolve-CommandPath $name
        if($p){return [IO.Path]::GetFullPath($p)}
    }
    foreach($p in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'),
        (Join-Path $env:USERPROFILE '.codex\packages\standalone\current\bin\codex.exe'),
        (Join-Path $env:USERPROFILE '.local\bin\codex.exe')
    )) {
        if(Test-Path -LiteralPath $p -PathType Leaf){return [IO.Path]::GetFullPath($p)}
    }
    return $null
}
function Open-EncodedWindow([string]$Title,[string]$Code) {
    $full = '$Host.UI.RawUI.WindowTitle='''+(Quote-PsSingle $Title)+''';'+$Code
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
    Start-Process powershell.exe -WindowStyle Normal -ArgumentList @('-NoLogo','-NoProfile','-NoExit','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) | Out-Null
}

Write-Host ''
Write-Host ('Local Frontier Orchestrator (LFO) - Windows bootstrap for '+$RuntimeContract) -ForegroundColor Cyan
Write-Host 'Local-first AI orchestration with structured memory, provenance and bounded L4 epistemic tooling.'
Write-Host 'Project: https://github.com/tomasgal/local-frontier-orchestrator'
Write-Host 'Created by Tomas Gal; bootstrap and integration tooling developed with OpenAI ChatGPT/Codex assistance.'
Write-Host 'This installer will verify Windows/PowerShell/SQLite, reuse or provision Ollama and SurrealDB,'
Write-Host 'obtain the selected LFO source, prepare local runtime/data/configuration, and create CPU/GPU launchers.'
Write-Host 'Existing compatible components are reused where safe; unrelated data stores and running services are not overwritten.'
Write-Host ''
Step 'Windows / PowerShell preflight'
Assert-Lfo ($env:OS -eq 'Windows_NT') 'LFO Windows bootstrap requires Windows.'
Assert-Lfo ([Environment]::Is64BitOperatingSystem) 'LFO Windows bootstrap currently requires 64-bit Windows.'
Assert-Lfo ($PSVersionTable.PSVersion -ge [version]'5.1') 'Windows PowerShell 5.1 or newer is required.'
Assert-Lfo ($null -ne (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue)) 'Invoke-WebRequest is unavailable.'
Assert-Lfo ($null -ne (Get-Command Expand-Archive -ErrorAction SilentlyContinue)) 'Expand-Archive is unavailable.'
Info ("PowerShell {0}; Windows {1}; 64-bit={2}" -f $PSVersionTable.PSVersion,[Environment]::OSVersion.Version,[Environment]::Is64BitOperatingSystem)
try {
    $drive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($InstallRoot)))
    $freeGiB=[math]::Round($drive.AvailableFreeSpace/1GB,1)
    Info "Free space on install volume: $freeGiB GiB"
    if ($freeGiB -lt 8) { Warn 'Fresh Ollama + 4B model installation may require substantially more free space.' }
} catch {}

Step 'Frontier adapter detection'
$codexPath=Resolve-CodexPath
if(-not $codexPath){
    Warn 'Codex CLI: NOT FOUND'
    Write-Host ''
    Write-Host 'Codex CLI is required for the LFO frontier path.' -ForegroundColor Yellow
    Write-Host '  [1] Install OpenAI Codex CLI'
    Write-Host '  [2] Exit installation'
    Write-Host ''
    do {
        $choice=(Read-Host 'Select 1 or 2').Trim()
    } while($choice -notin @('1','2'))

    if($choice -eq '2'){
        Write-Host 'LFO installation cancelled: Codex CLI is required.' -ForegroundColor Yellow
        exit 2
    }

    Step 'Install OpenAI Codex CLI'
    $codexInstaller=Join-Path $env:TEMP ('codex-install-'+[guid]::NewGuid().ToString('N')+'.ps1')
    try {
        Info 'Downloading the official OpenAI Codex Windows installer...'
        Invoke-WebRequest -UseBasicParsing 'https://chatgpt.com/codex/install.ps1' -OutFile $codexInstaller
        Assert-Lfo (Test-Path -LiteralPath $codexInstaller -PathType Leaf) 'Codex installer download failed.'
        $installProc=Start-Process powershell.exe -Wait -PassThru -NoNewWindow -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$codexInstaller)
        Assert-Lfo ($installProc.ExitCode -eq 0) "OpenAI Codex installer exited with code $($installProc.ExitCode)."
    } finally {
        Remove-Item -LiteralPath $codexInstaller -Force -ErrorAction SilentlyContinue
    }

    $codexPath=Resolve-CodexPath
    Assert-Lfo $codexPath 'Codex installation completed but codex.exe could not be located. Open a new terminal and rerun the LFO bootstrap.'
}

$codexVersion=$null
try {
    $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
    $codexVersion=(& $codexPath --version 2>&1 | Out-String).Trim()
    $exit=$LASTEXITCODE
    $ErrorActionPreference=$old
    Assert-Lfo ($exit -eq 0 -and -not [string]::IsNullOrWhiteSpace($codexVersion)) 'Codex CLI was found but codex --version failed.'
} catch {
    throw "Codex CLI readiness check failed: $($_.Exception.Message)"
}
Info 'Codex CLI: FOUND'
Info "Executable: $codexPath"
Info "Version: $codexVersion"
Info 'Frontier adapter availability: CODEX_AVAILABLE'

$AppRoot=Join-Path $InstallRoot 'app'
$RuntimeRoot=Join-Path $InstallRoot 'runtime'
$ModelsRoot=Join-Path $InstallRoot 'models'
$DataRoot=Join-Path $InstallRoot 'data'
$ConfigRoot=Join-Path $InstallRoot 'config'
$PrivateRoot=Join-Path $ConfigRoot 'private'
$LaunchRoot=Join-Path $InstallRoot 'launch'
foreach($d in @($InstallRoot,$RuntimeRoot,$ModelsRoot,$DataRoot,$ConfigRoot,$PrivateRoot,$LaunchRoot)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
$oldStatePath=Join-Path $ConfigRoot 'install-state.json'
$oldState=$null
if(Test-Path -LiteralPath $oldStatePath -PathType Leaf) { try { $oldState=Get-Content -LiteralPath $oldStatePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }

Step 'Obtain canonical LFO source'
$git=Resolve-CommandPath 'git.exe'; if(-not $git){$git=Resolve-CommandPath 'git'}
if ($git) {
    Info "Using Git: $git"
    if (Test-Path -LiteralPath (Join-Path $AppRoot '.git') -PathType Container) {
        $dirty=(& $git -C $AppRoot status --porcelain 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Existing LFO app checkout is not readable by Git.' }
        if ($dirty) { throw "Installer-managed LFO checkout has local changes: $AppRoot. Preserve them elsewhere before reinstall/update." }
    } else {
        if (Test-Path -LiteralPath $AppRoot) {
            $items=@(Get-ChildItem -LiteralPath $AppRoot -Force -ErrorAction SilentlyContinue)
            if($items.Count){throw "App directory exists but is not a Git checkout: $AppRoot"}
        }
        & $git clone $RepoUrl $AppRoot | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'git clone failed.' }
    }
    & $git -C $AppRoot fetch --prune origin $SourceRef | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Unable to fetch source ref $SourceRef." }
    $targetCommit=(& $git -C $AppRoot rev-parse FETCH_HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $targetCommit -notmatch '^[0-9a-f]{40}$') { throw "Unable to resolve fetched source ref $SourceRef to an exact commit." }
    & $git -C $AppRoot checkout --detach --force $targetCommit | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Unable to checkout fetched source commit $targetCommit." }
    $SourceCommit=(& $git -C $AppRoot rev-parse HEAD 2>&1 | Out-String).Trim()
    Assert-Lfo ($SourceCommit -ceq $targetCommit) 'Installed LFO checkout does not match the fetched source commit.'
} else {
    Info 'Git not found; using GitHub source archive fallback.'
    $tmpRoot=Join-Path ([IO.Path]::GetTempPath()) ('LFO-source-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpRoot | Out-Null
    $zip=Join-Path $tmpRoot 'source.zip'
    if($SourceRef -match '^[0-9a-fA-F]{40}$'){$archiveUrl='https://codeload.github.com/tomasgal/local-frontier-orchestrator/zip/'+$SourceRef}else{$archiveUrl='https://codeload.github.com/tomasgal/local-frontier-orchestrator/zip/refs/heads/'+$SourceRef}
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $archiveUrl -OutFile $zip -TimeoutSec 600
        $expanded=Join-Path $tmpRoot 'expanded'; Expand-Archive -LiteralPath $zip -DestinationPath $expanded -Force
        $dirs=@(Get-ChildItem -LiteralPath $expanded -Directory)
        Assert-Lfo ($dirs.Count -eq 1) 'Unexpected GitHub archive layout.'
        if(Test-Path -LiteralPath $AppRoot){Remove-Item -LiteralPath $AppRoot -Recurse -Force}
        Move-Item -LiteralPath $dirs[0].FullName -Destination $AppRoot
        $SourceCommit=$SourceRef
    } finally { Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
Assert-Lfo (Test-Path -LiteralPath (Join-Path $AppRoot 'src\QwenChat.ps1')) 'LFO source checkout is incomplete.'
Assert-Lfo (Test-Path -LiteralPath (Join-Path $AppRoot 'LFO.ps1')) 'LFO source does not contain the v9.6.3 production entrypoint.'
Assert-Lfo (Test-Path -LiteralPath (Join-Path $AppRoot 'src\LfoL4Runtime.ps1')) 'LFO source does not contain the v9.6.1/v9.6.2 L4 runtime module.'
Assert-Lfo (Test-Path -LiteralPath (Join-Path $AppRoot 'tests\Test-LfoL4Recording.ps1')) 'LFO source does not contain the v9.6.1/v9.6.2 L4 recording acceptance suite.'
foreach($requiredLauncher in @('Start-LFO.ps1','Start-LFO-GPU.ps1','Start-LFO-CPU.ps1','Start-SurrealDB.ps1','Watch-LFOService.ps1')){
    Assert-Lfo (Test-Path -LiteralPath (Join-Path $AppRoot ('launch\'+$requiredLauncher))) ("Bootstrap source is missing launcher: "+$requiredLauncher)
}
Info "LFO source: $SourceCommit"
Info "Runtime contract: $RuntimeContract"

Step 'SQLite provider detection and functional self-test'
$systemSqlite=Join-Path $env:WINDIR 'System32\winsqlite3.dll'
Assert-Lfo (Test-Path -LiteralPath $systemSqlite -PathType Leaf) 'winsqlite3.dll is missing. Supported Windows 10/11 systems provide this SQLite ABI; repair Windows before installing LFO.'
. (Join-Path $AppRoot 'src\LfoMemoryStore.ps1')
$sqliteTest=Join-Path $DataRoot ('sqlite-selftest-'+[guid]::NewGuid().ToString('N')+'.sqlite')
$conn=$null
try {
    $conn=Open-LfoSqliteDatabase $sqliteTest
    Invoke-LfoSqliteExec $conn 'CREATE TABLE probe(id INTEGER PRIMARY KEY, value TEXT NOT NULL);'
    Start-LfoMemoryTransaction $conn
    Invoke-LfoSqliteNonQuery $conn 'INSERT INTO probe(value) VALUES (?);' @('LFO')
    Complete-LfoMemoryTransaction $conn
    $row=@(Invoke-LfoSqliteQuery $conn 'SELECT value FROM probe WHERE id=1;')
    Assert-Lfo ($row.Count -eq 1 -and [string]$row[0].value -ceq 'LFO') 'SQLite create/write/read transaction self-test failed.'
    Initialize-LfoSqliteInterop
    $sqliteVersion=[Runtime.InteropServices.Marshal]::PtrToStringAnsi([LfoWinSqlite]::sqlite3_libversion())
    Info "SQLite ABI PASS: winsqlite3.dll $sqliteVersion"
} finally { if($conn){Close-LfoSqliteDatabase $conn}; Remove-Item -LiteralPath $sqliteTest -Force -ErrorAction SilentlyContinue }

Step 'Resolve Ollama runtime: reuse compatible installation, otherwise provision pinned 0.34.4'
$ollamaCandidates=New-Object Collections.Generic.List[string]
if($env:LFO_OLLAMA_EXE){$ollamaCandidates.Add($env:LFO_OLLAMA_EXE)}
foreach($n in @('ollama.exe','ollama')){ $p=Resolve-CommandPath $n; if($p){$ollamaCandidates.Add($p)} }
foreach($p in @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
    (Join-Path $env:LOCALAPPDATA 'Ollama\ollama.exe'),
    (Join-Path $env:ProgramFiles 'Ollama\ollama.exe'),
    (Join-Path $RuntimeRoot ('ollama-'+$OllamaPinnedVersion+'\ollama.exe'))
)){ if($p){$ollamaCandidates.Add($p)} }
# Generic bounded discovery for portable Ollama runtimes under LocalAppData.
# This intentionally does not encode any host- or user-specific private path.
foreach($pattern in @('*\ollama.exe','*\*\ollama.exe','*\*\*\ollama.exe')) {
    try {
        foreach($item in @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA $pattern) -File -ErrorAction SilentlyContinue)) {
            if($item.FullName){$ollamaCandidates.Add($item.FullName)}
        }
    } catch {}
}
try {
    foreach($pid in @(Get-NetTCPConnection -State Listen -LocalPort 11434 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)) {
        try { $p=(Get-Process -Id $pid -ErrorAction Stop).Path; if($p){$ollamaCandidates.Insert(0,$p)} } catch {}
    }
} catch {}
$ollamaExe=$null;$ollamaExeVersion=$null
foreach($candidate in @($ollamaCandidates | Select-Object -Unique)) {
    $v=Get-OllamaExeVersion $candidate
    if($v -and $v -ge $OllamaMinVersion){$ollamaExe=[IO.Path]::GetFullPath($candidate);$ollamaExeVersion=$v;break}
}
$ollamaManaged=$false
if(-not $ollamaExe){
    $ollamaManaged=$true
    $ollamaDir=Join-Path $RuntimeRoot ('ollama-'+$OllamaPinnedVersion)
    $ollamaZip=Join-Path $RuntimeRoot ('ollama-'+$OllamaPinnedVersion+'-windows-amd64.zip')
    if(-not (Test-Path -LiteralPath $ollamaZip -PathType Leaf) -or (Get-Sha256 $ollamaZip) -cne $OllamaSHA256){Download-Verified $OllamaUrl $ollamaZip $OllamaSHA256}
    if(Test-Path -LiteralPath $ollamaDir){Remove-Item -LiteralPath $ollamaDir -Recurse -Force}
    New-Item -ItemType Directory -Path $ollamaDir | Out-Null
    Expand-Archive -LiteralPath $ollamaZip -DestinationPath $ollamaDir -Force
    $ollamaExe=Join-Path $ollamaDir 'ollama.exe'
    Assert-Lfo (Test-Path -LiteralPath $ollamaExe -PathType Leaf) 'Pinned Ollama archive did not contain ollama.exe.'
    $ollamaExeVersion=Get-OllamaExeVersion $ollamaExe
    Assert-Lfo ($ollamaExeVersion -eq [version]$OllamaPinnedVersion) 'Pinned Ollama executable version mismatch after extraction.'
    Info "Provisioned Ollama $ollamaExeVersion at $ollamaExe"
} else { Info "Reusing Ollama $ollamaExeVersion at $ollamaExe" }

# Discover any existing shared LFO alias store before deciding whether a running
# Ollama listener is actually reusable for this installation. CPU/GPU profiles
# share one model store; profile selection changes execution parameters only.
$ollamaStoreCandidates=New-Object Collections.Generic.List[string]
foreach($candidateStore in @(
    $env:LFO_OLLAMA_MODELS,
    $env:OLLAMA_MODELS,
    $(if($oldState -and $oldState.Ollama){[string]$oldState.Ollama.ModelsDirectory}else{$null}),
    $ModelsRoot,
    (Join-Path $env:USERPROFILE '.ollama\models')
)){
    if(-not [string]::IsNullOrWhiteSpace([string]$candidateStore)){$ollamaStoreCandidates.Add([string]$candidateStore)}
}
$probe=Split-Path -Parent $ollamaExe
for($depth=0;$depth -lt 4 -and $probe;$depth++) {
    $candidateStore=Join-Path $probe 'models'
    if(Test-Path -LiteralPath (Join-Path $candidateStore 'manifests') -PathType Container){$ollamaStoreCandidates.Add($candidateStore)}
    $next=Split-Path -Parent $probe
    if($next -eq $probe){break}
    $probe=$next
}
foreach($pattern in @('*\models\manifests','*\*\models\manifests','*\*\*\models\manifests')) {
    try {
        foreach($manifestDir in @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA $pattern) -Directory -ErrorAction SilentlyContinue)) {
            $ollamaStoreCandidates.Add((Split-Path -Parent $manifestDir.FullName))
        }
    } catch {}
}
$preferredStores=@(
    $(if($oldState -and $oldState.Ollama){[string]$oldState.Ollama.ModelsDirectory}else{$null}),
    $env:LFO_OLLAMA_MODELS,
    $env:OLLAMA_MODELS
)
$preExistingAliasStore=Resolve-LfoAliasModelStore -Candidates @($ollamaStoreCandidates) -Preferred $preferredStores
if($preExistingAliasStore){Info "Existing shared LFO Ollama model store: $preExistingAliasStore"}

# Prefer a compatible already-running API only when it does not conflict with a
# known LFO alias store. Otherwise leave it untouched and start an LFO listener
# on a free local port using the shared store.
$ollamaPort=11434;$ollamaBase='http://127.0.0.1:11434';$ollamaApiVersion=Get-ApiVersion $ollamaBase
$runningCompatible=$false
$runningOllamaExe=$null
try {
    $owner=@(Get-NetTCPConnection -State Listen -LocalPort 11434 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
    if($owner.Count -eq 1){try{$runningOllamaExe=(Get-Process -Id $owner[0] -ErrorAction Stop).Path}catch{}}
} catch {}
if($ollamaApiVersion){
    $rv=Parse-SemVer $ollamaApiVersion
    if($rv -and $rv -ge $OllamaMinVersion){
        $apiModels=@(Get-OllamaApiModelNames $ollamaBase)
        $apiHasLfoAliases=($apiModels -contains $GpuModel) -and ($apiModels -contains $CpuModel)
        if($preExistingAliasStore -and -not $apiHasLfoAliases){
            Warn ("Compatible Ollama is already listening on 127.0.0.1:11434, but it does not expose the existing LFO CPU/GPU aliases from "+$preExistingAliasStore+". It will be left untouched; LFO will start its own listener on a free port using that shared store.")
        } else {
            $runningCompatible=$true
            Info "Reusing compatible Ollama API already listening on 127.0.0.1:11434 (version=$ollamaApiVersion)."
            if($runningOllamaExe){ Info "Running Ollama executable: $runningOllamaExe" }
        }
    }
}
$ollamaModelsDir=$preExistingAliasStore
if(-not $ollamaModelsDir -and $ollamaManaged){
    $ollamaModelsDir=$ModelsRoot
} elseif(-not $ollamaModelsDir -and -not $runningCompatible) {
    # Discover a model store associated with the selected portable executable.
    $probe=Split-Path -Parent $ollamaExe
    for($depth=0;$depth -lt 4 -and $probe;$depth++) {
        $candidateStore=Join-Path $probe 'models'
        if(Test-Path -LiteralPath (Join-Path $candidateStore 'manifests') -PathType Container){$ollamaModelsDir=$candidateStore;break}
        $next=Split-Path -Parent $probe
        if($next -eq $probe){break}
        $probe=$next
    }
    if(-not $ollamaModelsDir) {
        $standardStore=Join-Path $env:USERPROFILE '.ollama\models'
        if(Test-Path -LiteralPath (Join-Path $standardStore 'manifests') -PathType Container){$ollamaModelsDir=$standardStore}
    }
}
if($ollamaModelsDir){Info "Ollama model store selected for LFO: $ollamaModelsDir"}

if(-not $runningCompatible){
    if(@(Get-NetTCPConnection -State Listen -LocalPort 11434 -ErrorAction SilentlyContinue).Count -gt 0){$ollamaPort=Get-FreePort 11435;$ollamaBase='http://127.0.0.1:'+$ollamaPort}
    $hostAddress='127.0.0.1:'+$ollamaPort
    $modelsCode=''
    if($ollamaModelsDir){$modelsCode='$env:OLLAMA_MODELS='''+(Quote-PsSingle $ollamaModelsDir)+''';'}
    $code='$ErrorActionPreference=''Continue'';chcp 65001 > $null;$env:OLLAMA_HOST='''+$hostAddress+''';'+$modelsCode+'$env:OLLAMA_NUM_PARALLEL=''1'';$env:OLLAMA_MAX_LOADED_MODELS=''1'';$env:OLLAMA_NO_CLOUD=''1'';$env:OLLAMA_DEBUG=''1'';Write-Host ''LFO Ollama foreground server. Live logs follow.'' -ForegroundColor Cyan;& '''+(Quote-PsSingle $ollamaExe)+''' serve;Write-Host (''Ollama exited: ''+$LASTEXITCODE) -ForegroundColor Yellow'
    Open-EncodedWindow 'LFO | Ollama foreground logs' $code
    Wait-Ready { $v=Get-ApiVersion $ollamaBase; if(-not $v){throw 'not ready'} } 'Ollama' 90
    $ollamaApiVersion=Get-ApiVersion $ollamaBase
}
Assert-Lfo ((Parse-SemVer $ollamaApiVersion) -ge $OllamaMinVersion) "Ollama API at $ollamaBase is not compatible."
$hostAddress='127.0.0.1:'+$ollamaPort
Info "Ollama API: $ollamaBase version=$ollamaApiVersion"

if(-not $SkipModelPull){
    Step "Ensure base model and CPU/GPU runtime aliases: $BaseModel"
    $oldHost=$env:OLLAMA_HOST;$oldModels=$env:OLLAMA_MODELS
    try {
        $env:OLLAMA_HOST=$hostAddress
        if($ollamaModelsDir){$env:OLLAMA_MODELS=$ollamaModelsDir}else{Remove-Item Env:OLLAMA_MODELS -ErrorAction SilentlyContinue}
        $tags=Invoke-RestMethod -Uri ($ollamaBase+'/api/tags') -TimeoutSec 10
        $sourceModel=$BaseModel
        if(@($tags.models | Where-Object {$_.name -ceq $BaseModel}).Count -eq 0){
            $compatible=@($tags.models | Where-Object {
                $_.name -match '(?i)^qwen3[.]5-4b-.*:latest$' -or
                ($_.name -match '(?i)^qwen3[.]5.*4b' -and ($_.details.quantization_level -eq 'Q4_K_M' -or -not $_.details.quantization_level))
            } | Select-Object -First 1)
            if($compatible.Count -eq 1){
                $sourceModel=[string]$compatible[0].name
                Info "Reusing existing compatible local model as alias source: $sourceModel"
            } else {
                Info "Pulling $BaseModel"
                & $ollamaExe pull $BaseModel | Out-Host
                if($LASTEXITCODE -ne 0){throw "ollama pull failed for $BaseModel"}
            }
        } else {
            Info "Base model already present: $BaseModel"
        }
        $modRoot=Join-Path $ConfigRoot 'modelfiles'
        New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
        $gpuFile=Join-Path $modRoot 'Modelfile.GPU'
        $cpuFile=Join-Path $modRoot 'Modelfile.CPU'
        [IO.File]::WriteAllText($gpuFile,"FROM $sourceModel`nPARAMETER num_ctx 8192`nPARAMETER num_gpu 99`nPARAMETER temperature 0.1`n",$utf8)
        [IO.File]::WriteAllText($cpuFile,"FROM $sourceModel`nPARAMETER num_ctx 5120`nPARAMETER num_gpu 0`nPARAMETER temperature 0.1`n",$utf8)
        & $ollamaExe create $GpuModel -f $gpuFile | Out-Host
        if($LASTEXITCODE -ne 0){throw 'Failed to create LFO GPU model alias.'}
        & $ollamaExe create $CpuModel -f $cpuFile | Out-Host
        if($LASTEXITCODE -ne 0){throw 'Failed to create LFO CPU model alias.'}
        $tags=Invoke-RestMethod -Uri ($ollamaBase+'/api/tags') -TimeoutSec 10
        Assert-Lfo (@($tags.models|Where-Object{$_.name -ceq $GpuModel}).Count -eq 1) 'GPU model alias missing after create.'
        Assert-Lfo (@($tags.models|Where-Object{$_.name -ceq $CpuModel}).Count -eq 1) 'CPU model alias missing after create.'

        # Resolve the filesystem store that now contains both aliases. This is
        # persisted once and shared by CPU/GPU launchers so a later Ollama
        # restart cannot silently fall back to another default store.
        if($ollamaModelsDir){$ollamaStoreCandidates.Add($ollamaModelsDir)}
        foreach($pattern in @('*\models\manifests','*\*\models\manifests','*\*\*\models\manifests')) {
            try {
                foreach($manifestDir in @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA $pattern) -Directory -ErrorAction SilentlyContinue)) {
                    $ollamaStoreCandidates.Add((Split-Path -Parent $manifestDir.FullName))
                }
            } catch {}
        }
        $resolvedAliasStore=Resolve-LfoAliasModelStore -Candidates @($ollamaStoreCandidates) -Preferred @($ollamaModelsDir,$preExistingAliasStore,$env:LFO_OLLAMA_MODELS,$env:OLLAMA_MODELS)
        Assert-Lfo $resolvedAliasStore 'Both LFO aliases exist through the Ollama API, but their shared filesystem model store could not be resolved. Set LFO_OLLAMA_MODELS to the intended Ollama model directory and rerun the bootstrap.'
        $ollamaModelsDir=$resolvedAliasStore
        Info "Shared LFO Ollama model store: $ollamaModelsDir"
        Info "GPU launcher model: $GpuModel"
        Info "CPU launcher model: $CpuModel"
    } finally {
        if($null -eq $oldHost){Remove-Item Env:OLLAMA_HOST -ErrorAction SilentlyContinue}else{$env:OLLAMA_HOST=$oldHost}
        if($null -eq $oldModels){Remove-Item Env:OLLAMA_MODELS -ErrorAction SilentlyContinue}else{$env:OLLAMA_MODELS=$oldModels}
    }
} else {
    Warn 'Model pull/alias creation skipped by request.'
    if($preExistingAliasStore){
        $ollamaModelsDir=$preExistingAliasStore
        Info "Shared LFO Ollama model store: $ollamaModelsDir"
    } elseif([string]::IsNullOrWhiteSpace([string]$ollamaModelsDir)){
        Warn 'No shared LFO alias store was resolved; a later launcher will refuse to start if the configured Ollama API does not expose both aliases.'
    }
}

Step 'Resolve SurrealDB runtime: reuse compatible 3.3.0 binary, otherwise provision pinned binary'
$surrealCandidates=New-Object Collections.Generic.List[string]
if($env:LFO_SURREAL_EXE){$surrealCandidates.Add($env:LFO_SURREAL_EXE)}
if($oldState -and $oldState.SurrealDB -and $oldState.SurrealDB.Executable){$surrealCandidates.Add([string]$oldState.SurrealDB.Executable)}
foreach($n in @('surreal.exe','surreal')){$p=Resolve-CommandPath $n;if($p){$surrealCandidates.Add($p)}}
$managedSurreal=Join-Path $RuntimeRoot ('surrealdb-'+$SurrealVersion+'\surreal.exe');$surrealCandidates.Add($managedSurreal)
# Generic bounded discovery for portable SurrealDB runtimes under LocalAppData.
foreach($pattern in @('*\surreal.exe','*\*\surreal.exe','*\*\*\surreal.exe','*\*\*\*\surreal.exe')) {
    try {
        foreach($item in @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA $pattern) -File -ErrorAction SilentlyContinue)) {
            if($item.FullName){$surrealCandidates.Add($item.FullName)}
        }
    } catch {}
}
try { foreach($p in @(Get-Process surreal -ErrorAction SilentlyContinue|ForEach-Object{$_.Path})){if($p){$surrealCandidates.Insert(0,$p)}} } catch {}
$surrealExe=$null
foreach($candidate in @($surrealCandidates|Select-Object -Unique)){if((Get-SurrealExeVersion $candidate) -eq [version]$SurrealVersion){$surrealExe=[IO.Path]::GetFullPath($candidate);break}}
$surrealManaged=$false
if(-not $surrealExe){
    $surrealManaged=$true
    $surrealDir=Split-Path -Parent $managedSurreal;New-Item -ItemType Directory -Path $surrealDir -Force|Out-Null
    Download-Verified $SurrealUrl $managedSurreal $SurrealSHA256
    Assert-Lfo ((Get-SurrealExeVersion $managedSurreal) -eq [version]$SurrealVersion) 'Downloaded SurrealDB version mismatch.'
    $surrealExe=$managedSurreal
    Info "Provisioned SurrealDB $SurrealVersion at $surrealExe"
} else { Info "Reusing SurrealDB $SurrealVersion binary at $surrealExe" }
$surrealHash=Get-Sha256 $surrealExe
if($surrealManaged){Assert-Lfo ($surrealHash -ceq $SurrealSHA256) 'Managed SurrealDB SHA256 changed unexpectedly.'}

Step 'Prepare isolated LFO SurrealDB datastore and credentials'
$surrealData=Join-Path $DataRoot 'surreal';New-Item -ItemType Directory -Path $surrealData -Force|Out-Null
$bootstrapCredPath=Join-Path $PrivateRoot 'surreal-bootstrap.credential.xml'
$runtimeCredPath=Join-Path $PrivateRoot 'surreal-runtime.credential.xml'
$bootstrapExists=Test-Path -LiteralPath $bootstrapCredPath -PathType Leaf
$runtimeExists=Test-Path -LiteralPath $runtimeCredPath -PathType Leaf
if($bootstrapExists -xor $runtimeExists){throw 'Only one SurrealDB credential file is present. Refusing to regenerate credentials against a possibly existing datastore.'}
if(-not $bootstrapExists){
    $existingData=@(Get-ChildItem -LiteralPath $surrealData -Force -ErrorAction SilentlyContinue)
    if($existingData.Count -gt 0){throw 'SurrealDB data already exists but LFO credentials are missing. Refusing to overwrite access state.'}
    $rootPassword=([guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N'))
    $runtimePassword=([guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N'))
    $bootstrapCred=New-Object Management.Automation.PSCredential('lfo_root',(ConvertTo-SecureString $rootPassword -AsPlainText -Force))
    $runtimeCred=New-Object Management.Automation.PSCredential('lfo_r1',(ConvertTo-SecureString $runtimePassword -AsPlainText -Force))
    $bootstrapCred|Export-Clixml -LiteralPath $bootstrapCredPath
    $runtimeCred|Export-Clixml -LiteralPath $runtimeCredPath
    Info 'Generated current-user DPAPI-protected SurrealDB credentials.'
}
$bootstrapCred=Import-Clixml -LiteralPath $bootstrapCredPath;$runtimeCred=Import-Clixml -LiteralPath $runtimeCredPath
$surrealRuntimeMarker=Join-Path $ConfigRoot 'surreal-runtime.json'
$surrealPort=18080
if($oldState -and $oldState.SurrealDB -and $oldState.SurrealDB.Port){
    $surrealPort=[int]$oldState.SurrealDB.Port
} elseif(Test-Path -LiteralPath $surrealRuntimeMarker -PathType Leaf) {
    try {
        $runtimeMarker=Get-Content -LiteralPath $surrealRuntimeMarker -Raw -Encoding UTF8 | ConvertFrom-Json
        if($runtimeMarker.Port){$surrealPort=[int]$runtimeMarker.Port}
    } catch { Warn 'Ignoring unreadable SurrealDB runtime marker.' }
}
$surrealBase='http://127.0.0.1:'+$surrealPort
. (Join-Path $AppRoot 'src\LfoEpistemicStore.ps1')
$existingLfoDb=$false
try{$c=New-LfoEpistemicConnection $surrealBase $runtimeCred;$null=Invoke-LfoEpistemicQuery $c 'RETURN 1;';$existingLfoDb=$true}catch{}

# Recover a live installer-owned datastore after a partial prior bootstrap failure,
# even when install-state.json was not reached. Runtime credentials make the probe
# installation-specific; an unrelated SurrealDB listener will not authenticate.
if(-not $existingLfoDb){
    # A file-backed SurrealDB does not persist its bind port in the datastore.
    # Recover an installer-started instance from the exact process command line:
    # Start-LfoEpistemicServer launches surreal.exe with both --bind and the
    # normalized rocksdb://.../observations.db path.
    $dbPathNormalized=(Join-Path ([IO.Path]::GetFullPath($surrealData)) 'observations.db').Replace('\','/')
    $matchingSurrealProcesses=@()
    try {
        $matchingSurrealProcesses=@(Get-CimInstance Win32_Process -Filter "Name='surreal.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -and $_.CommandLine.Replace('\','/').IndexOf($dbPathNormalized,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    } catch {}
    foreach($process in $matchingSurrealProcesses){
        $cmd=[string]$process.CommandLine
        if($cmd -match '(?i)(?:--bind|-b)\s+["'']?(?:127\.0\.0\.1|localhost):(?<port>\d{2,5})'){
            $candidatePort=[int]$Matches.port
            $candidateBase='http://127.0.0.1:'+$candidatePort
            Info ("SurrealDB recovery: process "+$process.ProcessId+" declares "+$candidateBase)
            try {
                $candidateConnection=New-LfoEpistemicConnection $candidateBase $runtimeCred -TimeoutSec 2
                $null=Invoke-LfoEpistemicQuery $candidateConnection 'RETURN 1;'
                $candidateVersion=[string](Invoke-RestMethod -Uri ($candidateBase+'/version') -TimeoutSec 2)
                if($candidateVersion -match '(^|[- ])3\.3\.0($|[ +])'){
                    $surrealPort=$candidatePort
                    $surrealBase=$candidateBase
                    $existingLfoDb=$true
                    Info "Recovered existing LFO SurrealDB datastore at $surrealBase"
                    break
                }
            } catch {}
        }
    }
}

if(-not $existingLfoDb){
    if($matchingSurrealProcesses.Count -gt 0){
        throw "An existing SurrealDB process already owns the LFO datastore at $surrealData, but its declared --bind endpoint could not be authenticated with this installation's runtime credential. Stop that process or repair the stored runtime marker before retrying."
    }
    if(@(Get-NetTCPConnection -State Listen -LocalPort $surrealPort -ErrorAction SilentlyContinue).Count -gt 0){$surrealPort=Get-FreePort 18080;$surrealBase='http://127.0.0.1:'+$surrealPort}
    $serverScript=Join-Path $AppRoot 'tools\Start-LfoEpistemicServer.ps1'
    $code='$ErrorActionPreference=''Continue'';chcp 65001 > $null;$c=Import-Clixml -LiteralPath '''+(Quote-PsSingle $bootstrapCredPath)+''';$env:SURREAL_USER=$c.UserName;$env:SURREAL_PASS=$c.GetNetworkCredential().Password;Write-Host ''LFO SurrealDB foreground server. Live logs follow.'' -ForegroundColor Cyan;& '''+(Quote-PsSingle $serverScript)+''' -Binary '''+(Quote-PsSingle $surrealExe)+''' -DataDirectory '''+(Quote-PsSingle $surrealData)+''' -Port '+$surrealPort+' -LogLevel info;Write-Host (''SurrealDB exited: ''+$LASTEXITCODE) -ForegroundColor Yellow'
    Open-EncodedWindow 'LFO | SurrealDB foreground logs' $code
    Wait-Ready { Invoke-RestMethod -Uri ($surrealBase+'/ready') -TimeoutSec 2 } 'SurrealDB' 60
}
$sv=[string](Invoke-RestMethod -Uri ($surrealBase+'/version') -TimeoutSec 5)
Assert-Lfo ($sv -match '(^|[- ])3\.3\.0($|[ +])') "Unexpected SurrealDB API version: $sv"
$schemaMarker=Join-Path $ConfigRoot 'surreal-schema-v1.json'
$runtimeSchemaReady=$false
try{$c=New-LfoEpistemicConnection $surrealBase $runtimeCred;$null=Invoke-LfoEpistemicQuery $c 'RETURN 1;';$runtimeSchemaReady=$true}catch{}
if(-not $runtimeSchemaReady){
    $admin=New-LfoEpistemicConnection $surrealBase $bootstrapCred -Bootstrap
    Initialize-LfoEpistemicSchema $admin $runtimeCred
    [IO.File]::WriteAllText($schemaMarker,(@{schema=1;initialized_at=[DateTime]::UtcNow.ToString('o');version=$SurrealVersion}|ConvertTo-Json -Compress),$utf8)
    Info 'Initialized L4 SurrealDB schema and runtime user.'
}
$c=New-LfoEpistemicConnection $surrealBase $runtimeCred;$null=Invoke-LfoEpistemicQuery $c 'RETURN 1;'
[IO.File]::WriteAllText($surrealRuntimeMarker,(@{Version=$SurrealVersion;Port=$surrealPort;BaseUri=$surrealBase;DataDirectory=$surrealData;UpdatedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress),$utf8)
Info "SurrealDB LFO datastore PASS: $surrealBase"
Info "SurrealDB runtime marker: $surrealRuntimeMarker"

Step 'Generate installed LFO configuration'
$baseConfigPath=Join-Path $AppRoot 'config\QwenChat.config.psd1'
$configText=Get-Content -LiteralPath $baseConfigPath -Raw -Encoding UTF8
$memoryDir=Join-Path $DataRoot 'memory';New-Item -ItemType Directory -Path $memoryDir -Force|Out-Null
$configText=[regex]::Replace($configText,"(?m)^\s*Model\s*=\s*'[^']*'","    Model = '"+(Quote-PsSingle $GpuModel)+"'",1)
$configText=[regex]::Replace($configText,"(?m)^\s*BaseUri\s*=\s*'[^']*'","    BaseUri = '"+(Quote-PsSingle $ollamaBase)+"'",1)
$configText=[regex]::Replace($configText,'(?m)^\s*L0StageSourcesEnabled\s*=\s*\$false','        L0StageSourcesEnabled = $true',1)
$configText=[regex]::Replace($configText,"(?m)^\s*DataDirectory\s*=\s*'[^']*'","        DataDirectory = '"+(Quote-PsSingle $memoryDir)+"'",1)
$l4Default="    L4 = @{ Enabled = `$true; Endpoint = ''; CredentialPath = '' }"
$l4Line=("    L4 = @{{ Enabled = `$true; Endpoint = '{0}'; CredentialPath = '{1}' }}" -f (Quote-PsSingle $surrealBase),(Quote-PsSingle $runtimeCredPath))
$l4Occurrences=($configText.Length-$configText.Replace($l4Default,'').Length)/$l4Default.Length
Assert-Lfo ($l4Occurrences -eq 1) ("Expected exactly one default L4 config line, found "+$l4Occurrences+".")
$configText=$configText.Replace($l4Default,$l4Line)
Assert-Lfo ($configText.Contains($l4Line)) 'Generated LFO config text does not contain the resolved L4 line.'
$installConfigPath=Join-Path $ConfigRoot 'QwenChat.install.local.psd1'
[IO.File]::WriteAllText($installConfigPath,$configText,$utf8)
$parsedInstallConfig=Import-PowerShellDataFile -LiteralPath $installConfigPath
Assert-Lfo ([string]$parsedInstallConfig.BaseUri -ceq $ollamaBase) 'Generated LFO config has the wrong Ollama BaseUri.'
Assert-Lfo ([bool]$parsedInstallConfig.Memory.L0StageSourcesEnabled) 'Generated LFO config did not enable L0 stage-source provenance.'
Assert-Lfo ([string]$parsedInstallConfig.Memory.DataDirectory -ceq $memoryDir) 'Generated LFO config has the wrong memory directory.'
Assert-Lfo ([bool]$parsedInstallConfig.L4.Enabled) 'Generated LFO config did not enable L4 recording.'
Assert-Lfo ([string]$parsedInstallConfig.L4.Endpoint -ceq $surrealBase) 'Generated LFO config has the wrong L4 endpoint.'
Assert-Lfo ([string]$parsedInstallConfig.L4.CredentialPath -ceq $runtimeCredPath) 'Generated LFO config has the wrong L4 runtime credential path.'

$l4Acceptance='SKIPPED'
if(-not $SkipL4Acceptance){
    Step 'Run v9.6.2 deterministic L4 recording acceptance'
    $acceptScript=Join-Path $AppRoot 'tests\Test-LfoL4Recording.ps1'
    $acceptProc=Start-Process powershell.exe -Wait -PassThru -NoNewWindow -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$acceptScript,'-SurrealBinary',$surrealExe)
    Assert-Lfo ($acceptProc.ExitCode -eq 0) ("v9.6.2 L4 recording acceptance failed with exit code "+$acceptProc.ExitCode)
    $l4Acceptance='PASS'
    Info 'L4 recording acceptance: release suite PASS.'
} else {
    Warn 'v9.6.2 L4 recording acceptance skipped by request.'
}

$state=[ordered]@{
    SchemaVersion=1
    InstalledAt=[DateTime]::UtcNow.ToString('o')
    InstallRoot=[IO.Path]::GetFullPath($InstallRoot)
    AppRoot=[IO.Path]::GetFullPath($AppRoot)
    SourceRef=$SourceRef
    SourceCommit=$SourceCommit
    SQLite=[ordered]@{Provider='winsqlite3.dll';Path=$systemSqlite;Version=$sqliteVersion;SelfTest='PASS'}
    Ollama=[ordered]@{Executable=$ollamaExe;ExecutableVersion=[string]$ollamaExeVersion;ApiVersion=$ollamaApiVersion;Managed=$ollamaManaged;BaseUri=$ollamaBase;HostAddress=$hostAddress;ModelsDirectory=$ollamaModelsDir;BaseModel=$BaseModel;GPUModel=$GpuModel;CPUModel=$CpuModel}
    SurrealDB=[ordered]@{Executable=$surrealExe;Version=$SurrealVersion;SHA256=$surrealHash;Managed=$surrealManaged;BaseUri=$surrealBase;Port=$surrealPort;DataDirectory=$surrealData;BootstrapCredentialPath=$bootstrapCredPath;RuntimeCredentialPath=$runtimeCredPath;Namespace='lfo';Database='epistemic'}
    Frontier=[ordered]@{CodexDetected=[bool]$codexPath;CodexExecutable=$codexPath;CodexVersion=$codexVersion;AdapterSelection='PENDING'}
    LFO=[ordered]@{RuntimeContract=$RuntimeContract;DefaultProfile=$Profile;DefaultPriority='High';ConfigPath=$installConfigPath;MemoryDirectory=$memoryDir;L0StageSourcesEnabled=$true;L4RecordingEnabled=$true;L4Acceptance=$l4Acceptance}
}
$statePath=Join-Path $ConfigRoot 'install-state.json'
[IO.File]::WriteAllText($statePath,($state|ConvertTo-Json -Depth 12),$utf8)

Step 'Publish easy launchers inside the install tree'
foreach($name in @('Start-LFO.ps1','Start-LFO-GPU.ps1','Start-LFO-CPU.ps1','Start-SurrealDB.ps1','Watch-LFOService.ps1','View-LFOConversationLog.ps1')){
    $src=Join-Path $AppRoot ('launch\'+$name);Assert-Lfo (Test-Path -LiteralPath $src -PathType Leaf) "Required launcher missing from source: $name"
    Copy-Item -LiteralPath $src -Destination (Join-Path $LaunchRoot $name) -Force
}
Copy-Item -LiteralPath (Join-Path $AppRoot 'LFO.ps1') -Destination (Join-Path $LaunchRoot 'LFO.ps1') -Force
# Add double-clickable BAT wrappers without changing the PowerShell launch contract.
$cpuBat=Join-Path $LaunchRoot 'Start-LFO-CPU.bat'
$gpuBat=Join-Path $LaunchRoot 'Start-LFO-GPU.bat'
$cpuBatText="@echo off`r`npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0Start-LFO-CPU.ps1`"`r`nexit /b %ERRORLEVEL%`r`n"
$gpuBatText="@echo off`r`npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0Start-LFO-GPU.ps1`"`r`nexit /b %ERRORLEVEL%`r`n"
[IO.File]::WriteAllText($cpuBat,$cpuBatText,[Text.Encoding]::ASCII)
[IO.File]::WriteAllText($gpuBat,$gpuBatText,[Text.Encoding]::ASCII)
# Launcher copies use their own PSScriptRoot for wrappers, while Start-LFO resolves service scripts from AppRoot via install-state.

Step 'Bootstrap complete'
Write-Host ('Install root:  '+$InstallRoot) -ForegroundColor Green
Write-Host ('Source:        '+$SourceCommit) -ForegroundColor Green
Write-Host ('Runtime:       '+$RuntimeContract) -ForegroundColor Green
Write-Host ('Profile:       '+$Profile+' (default; CPU/GPU launchers both installed)') -ForegroundColor Green
Write-Host 'Priority:      High (default production inference priority)' -ForegroundColor Green
Write-Host ('SQLite:       PASS '+$sqliteVersion) -ForegroundColor Green
Write-Host ('Ollama:       '+$ollamaApiVersion+' @ '+$ollamaBase) -ForegroundColor Green
Write-Host ('Model store:  '+$(if($ollamaModelsDir){$ollamaModelsDir}else{'UNRESOLVED'})) -ForegroundColor Green
Write-Host ('SurrealDB:    '+$SurrealVersion+' @ '+$surrealBase) -ForegroundColor Green
Write-Host ('L4 recording: ENABLED; acceptance='+$l4Acceptance+'; /analyze available; P2 OFF') -ForegroundColor Green
Write-Host ('Codex:        FOUND ('+$codexVersion+')') -ForegroundColor Green
$installedLaunchDir=Join-Path $InstallRoot 'launch'
Write-Host ('Launch dir:    '+$installedLaunchDir) -ForegroundColor Green
Write-Host ''
Write-Host 'Launch options:' -ForegroundColor Cyan
Write-Host '  .\LFO.ps1           (primary v9.6.3 entrypoint; Auto device, High priority by default)'
Write-Host '  Start-LFO-CPU.bat   (double-click or Command Prompt)'
Write-Host '  Start-LFO-GPU.bat   (double-click or Command Prompt)'
Write-Host '  .\Start-LFO-CPU.ps1 (PowerShell)'
Write-Host '  .\Start-LFO-GPU.ps1 (PowerShell)'
Write-Host '  .\View-LFOConversationLog.ps1 (current-month turn log viewer)'
Write-Host ''
Write-Host 'No shortcuts are created outside the LFO install tree; create any Windows shortcuts where you prefer.'
Write-Host 'Opening the LFO launch directory in Windows Explorer...' -ForegroundColor Cyan
try { Start-Process explorer.exe -ArgumentList ('"'+$installedLaunchDir+'"') | Out-Null } catch { Warn ("Unable to open Explorer: "+$_.Exception.Message) }

if($SkipLaunch){
    Write-Host 'Automatic Qwen/LFO launch skipped (-SkipLaunch).' -ForegroundColor Yellow
} else {
    $selectedLauncherName = if($Profile -eq 'CPU') { 'Start-LFO-CPU.ps1' } else { 'Start-LFO-GPU.ps1' }
    $selectedLauncher = Join-Path $installedLaunchDir $selectedLauncherName
    Write-Host ("Starting LFO/Qwen with the selected {0} profile..." -f $Profile) -ForegroundColor Cyan
    try {
        Start-Process powershell.exe -WindowStyle Normal -ArgumentList @('-NoLogo','-NoProfile','-NoExit','-ExecutionPolicy','Bypass','-File',('"'+$selectedLauncher+'"')) | Out-Null
    } catch {
        Warn ("Installation completed, but automatic LFO/Qwen launch failed: "+$_.Exception.Message)
        Write-Host ("Start it manually from: "+$selectedLauncher) -ForegroundColor Yellow
    }
}
