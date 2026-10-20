[CmdletBinding()]
param(
    [ValidateSet('Auto','CPU','GPU')][string]$Device,
    [string]$Experiment,
    [string]$InstallRoot,
    [switch]$Resume,

    # Internal re-entry used by unattended experiments. Not part of the public CLI.
    [switch]$InternalBatchChild,
    [string]$QwenChatPath,
    [string]$Model,
    [string]$ConfigPath,
    [Nullable[int]]$ContextLengthHint,
    [string]$BaseUri,
    [string]$DataDirectory,
    [string]$BatchInputPath,
    [ValidateSet('Normal','High','Realtime')][string]$Priority,
    [ValidateSet('On','Off')][string]$L4,
    [string]$L4Endpoint,
    [string]$L4CredentialPath,
    [switch]$BatchLocalOnly
)

$ErrorActionPreference = 'Stop'
chcp 65001 > $null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

function Resolve-LfoInstallRoot {
    param(
        [AllowNull()][string]$RequestedRoot,
        [Parameter(Mandatory=$true)][string]$ScriptRoot
    )

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        [void]$candidates.Add($RequestedRoot)
    } else {
        if (-not [string]::IsNullOrWhiteSpace($env:LFO_INSTALL_ROOT)) {
            [void]$candidates.Add([string]$env:LFO_INSTALL_ROOT)
        }
        [void]$candidates.Add($ScriptRoot)
        $scriptParent = Split-Path -Parent $ScriptRoot
        if (-not [string]::IsNullOrWhiteSpace($scriptParent)) {
            [void]$candidates.Add($scriptParent)
        }
        if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            [void]$candidates.Add((Join-Path $env:LOCALAPPDATA 'LFO'))
        }
    }

    $checked = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
        try { $full = [IO.Path]::GetFullPath([string]$candidate) } catch { continue }
        [void]$checked.Add($full)
        $statePath = Join-Path $full 'config\install-state.json'
        if (Test-Path -LiteralPath $statePath -PathType Leaf) { return $full }
    }

    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        throw "Requested LFO install root does not contain config\install-state.json: $RequestedRoot"
    }
    throw ("Unable to locate the existing LFO installation. Checked: " + ($checked -join '; ') +
        ". Pass -InstallRoot <path> if your LFO bootstrap root is elsewhere.")
}

$script:Lfo963Version = '9.6.3'

function Get-LfoInstallState {
    param([Parameter(Mandatory=$true)][string]$InstallRoot)
    $statePath = Join-Path $InstallRoot 'config\install-state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "LFO install state not found: $statePath. Run the current Install-LFO.ps1 bootstrap first."
    }
    $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $state.AppRoot -or -not (Test-Path -LiteralPath ([string]$state.AppRoot) -PathType Container)) {
        throw 'install-state.json does not contain a usable AppRoot.'
    }
    return $state
}

function Get-LfoFreeTcpPort {
    param([int]$Preferred = 12434)
    foreach ($p in $Preferred..($Preferred + 200)) {
        $listener = $null
        try {
            $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $p)
            $listener.Start()
            return $p
        } catch {
        } finally {
            if ($null -ne $listener) { try { $listener.Stop() } catch {} }
        }
    }
    throw "No free TCP port found from $Preferred through $($Preferred + 200)."
}

function Test-LfoOllamaReady {
    param([Parameter(Mandatory=$true)][string]$BaseUri)
    try {
        $null = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/api/version') -TimeoutSec 2
        return $true
    } catch { return $false }
}

function Assert-LfoOllamaModelAvailable {
    param(
        [Parameter(Mandatory=$true)][string]$BaseUri,
        [Parameter(Mandatory=$true)][string]$Model
    )
    try {
        $tags = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/api/tags') -TimeoutSec 5
        $names = @($tags.models | ForEach-Object { [string]$_.name })
        if ($Model -notin $names) {
            throw "Configured model alias '$Model' is not available from Ollama at $BaseUri."
        }
    } catch {
        if ($_.Exception.Message -like "Configured model alias*") { throw }
        throw "Unable to verify Ollama model '$Model' at ${BaseUri}: $($_.Exception.Message)"
    }
}

function Test-LfoSurrealReady {
    param([Parameter(Mandatory=$true)][string]$BaseUri)
    try {
        $null = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/ready') -TimeoutSec 2
        return $true
    } catch { return $false }
}

function Wait-LfoReady {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Probe,
        [Parameter(Mandatory=$true)][string]$Name,
        [int]$Seconds = 60
    )
    $deadline = (Get-Date).AddSeconds($Seconds)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $nextProgress = 5.0
    $progressLineOpen = $false
    do {
        try {
            if (& $Probe) {
                if ($progressLineOpen) { Write-Host '' }
                $sw.Stop()
                return
            }
        } catch {}
        if ($sw.Elapsed.TotalSeconds -ge $nextProgress) {
            if (-not $progressLineOpen) {
                Write-Host ("Waiting for {0}." -f $Name) -NoNewline -ForegroundColor Cyan
                $progressLineOpen = $true
            } else {
                Write-Host '.' -NoNewline -ForegroundColor DarkGray
            }
            $nextProgress += 5.0
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    if ($progressLineOpen) { Write-Host '' }
    $sw.Stop()
    throw "$Name did not become ready within $Seconds seconds."
}

function Resolve-LfoPriorityClass {
    param([Parameter(Mandatory=$true)][ValidateSet('Normal','High','Realtime')][string]$Priority)
    switch ($Priority) {
        'Normal'   { return [Diagnostics.ProcessPriorityClass]::Normal }
        'High'     { return [Diagnostics.ProcessPriorityClass]::High }
        'Realtime' { return [Diagnostics.ProcessPriorityClass]::RealTime }
    }
}

function Set-LfoProcessPriority {
    param(
        [Parameter(Mandatory=$true)][int]$ProcessId,
        [Parameter(Mandatory=$true)][ValidateSet('Normal','High','Realtime')][string]$Priority
    )
    try {
        $p = [Diagnostics.Process]::GetProcessById($ProcessId)
        $p.PriorityClass = Resolve-LfoPriorityClass $Priority
        $p.Refresh()
        return [string]$p.PriorityClass
    } catch {
        throw "Unable to set PID $ProcessId priority to ${Priority}: $($_.Exception.Message)"
    }
}

function Get-LfoChildProcessIds {
    param([Parameter(Mandatory=$true)][int]$ParentPid)
    try {
        return @(
            Get-CimInstance Win32_Process -Filter ("ParentProcessId={0}" -f $ParentPid) -ErrorAction Stop |
            ForEach-Object { [int]$_.ProcessId }
        )
    } catch {
        return @()
    }
}

function Set-LfoProcessTreePriority {
    param(
        [Parameter(Mandatory=$true)][int]$RootProcessId,
        [Parameter(Mandatory=$true)][ValidateSet('Normal','High','Realtime')][string]$Priority
    )
    $queue = New-Object 'System.Collections.Generic.Queue[int]'
    $seen = @{}
    $queue.Enqueue($RootProcessId)
    $rows = @()
    while ($queue.Count -gt 0) {
        $currentProcessId = $queue.Dequeue()
        if ($seen.ContainsKey($currentProcessId)) { continue }
        $seen[$currentProcessId] = $true
        try {
            $p = [Diagnostics.Process]::GetProcessById($currentProcessId)
            $p.PriorityClass = Resolve-LfoPriorityClass $Priority
            $p.Refresh()
            $rows += [pscustomobject]@{
                pid = $currentProcessId
                name = $p.ProcessName
                priority = [string]$p.PriorityClass
            }
        } catch {}
        foreach ($child in @(Get-LfoChildProcessIds $currentProcessId)) { $queue.Enqueue([int]$child) }
    }
    return @($rows)
}

function Set-LfoConfiguredOllamaPriority {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][ValidateSet('Normal','High','Realtime')][string]$Priority
    )
    $target = [string]$State.Ollama.Executable
    if ([string]::IsNullOrWhiteSpace($target)) { return @() }
    try { $target = [IO.Path]::GetFullPath($target) } catch { return @() }
    $roots = @()
    try {
        $roots = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.ExecutablePath) -and
            ([IO.Path]::GetFullPath([string]$_.ExecutablePath) -ieq $target) -and
            ([string]$_.CommandLine -match '(^|\s)serve(\s|$)')
        })
    } catch { return @() }
    $rows = @()
    foreach ($root in $roots) {
        $rows += @(Set-LfoProcessTreePriority -RootProcessId ([int]$root.ProcessId) -Priority $Priority)
    }
    return @($rows | Sort-Object pid -Unique)
}

function Stop-LfoOwnedProcessTree {
    param($Process)
    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) {
            & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
        }
    } catch {
        try { $Process.Kill() } catch {}
    }
}

function Get-LfoNvidiaGpuInfo {
    $cmd = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) { $cmd = Get-Command nvidia-smi -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($null -eq $cmd) { return @() }
    try {
        $cmdPath = if (-not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) { [string]$cmd.Source } else { [string]$cmd.Path }
        $lines = & $cmdPath --query-gpu=name,memory.total,driver_version --format=csv,noheader,nounits 2>$null
        if ($LASTEXITCODE -ne 0) { return @() }
        $rows = @()
        foreach ($line in @($lines)) {
            $parts = @([string]$line -split ',')
            if ($parts.Count -lt 3) { continue }
            $mem = 0
            [void][int]::TryParse($parts[1].Trim(), [ref]$mem)
            $rows += [pscustomobject]@{
                name = $parts[0].Trim()
                memory_mib = $mem
                driver = $parts[2].Trim()
            }
        }
        return @($rows)
    } catch { return @() }
}

function Resolve-LfoDevice {
    param(
        [AllowNull()][string]$RequestedDevice,
        [Parameter(Mandatory=$true)]$State,
        [int]$MinimumGpuVramMiB = 6144
    )
    $requested = if ([string]::IsNullOrWhiteSpace($RequestedDevice)) { 'Auto' } else { $RequestedDevice }
    if ($requested -notin @('Auto','CPU','GPU')) { throw "Invalid device '$requested'." }
    if ($requested -ne 'Auto') { return $requested }

    if ([string]::IsNullOrWhiteSpace([string]$State.Ollama.GPUModel)) { return 'CPU' }
    $gpus = @(Get-LfoNvidiaGpuInfo)
    if (@($gpus | Where-Object { [int]$_.memory_mib -ge $MinimumGpuVramMiB }).Count -gt 0) {
        return 'GPU'
    }
    return 'CPU'
}

function Get-LfoModelSpec {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][ValidateSet('CPU','GPU')][string]$Device
    )
    if ($Device -eq 'CPU') {
        return [pscustomobject]@{ Model = [string]$State.Ollama.CPUModel; Context = 5120 }
    }
    return [pscustomobject]@{ Model = [string]$State.Ollama.GPUModel; Context = 8192 }
}

function Quote-LfoArgument {
    param([Parameter(Mandatory=$true)][string]$Text)
    return '"' + $Text.Replace('"','\"') + '"'
}

function Start-LfoOwnedOllama {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$BaseUri,
        [Parameter(Mandatory=$true)][ValidateSet('Normal','High','Realtime')][string]$Priority,
        [Parameter(Mandatory=$true)][string]$LogDirectory
    )
    $exe = [string]$State.Ollama.Executable
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Ollama executable not found: $exe" }
    New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
    $uri = [uri]$BaseUri
    $hostAddress = '{0}:{1}' -f $uri.Host,$uri.Port
    $stdout = Join-Path $LogDirectory 'ollama.stdout.log'
    $stderr = Join-Path $LogDirectory 'ollama.stderr.log'

    $old = @{
        OLLAMA_HOST = $env:OLLAMA_HOST
        OLLAMA_MODELS = $env:OLLAMA_MODELS
        OLLAMA_CONTEXT_LENGTH = $env:OLLAMA_CONTEXT_LENGTH
        OLLAMA_NUM_PARALLEL = $env:OLLAMA_NUM_PARALLEL
        OLLAMA_MAX_LOADED_MODELS = $env:OLLAMA_MAX_LOADED_MODELS
        OLLAMA_NO_CLOUD = $env:OLLAMA_NO_CLOUD
    }
    try {
        $env:OLLAMA_HOST = $hostAddress
        if (-not [string]::IsNullOrWhiteSpace([string]$State.Ollama.ModelsDirectory)) {
            $env:OLLAMA_MODELS = [string]$State.Ollama.ModelsDirectory
        }
        $env:OLLAMA_CONTEXT_LENGTH = '8192'
        $env:OLLAMA_NUM_PARALLEL = '1'
        $env:OLLAMA_MAX_LOADED_MODELS = '1'
        $env:OLLAMA_NO_CLOUD = '1'
        $p = Start-Process -FilePath $exe -ArgumentList 'serve' -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    } finally {
        foreach ($k in $old.Keys) {
            [Environment]::SetEnvironmentVariable($k, $old[$k], 'Process')
        }
    }
    try {
        [void](Set-LfoProcessPriority -ProcessId $p.Id -Priority $Priority)
        Wait-LfoReady -Name 'Ollama' -Seconds 60 -Probe { Test-LfoOllamaReady $BaseUri }
        return $p
    } catch {
        Stop-LfoOwnedProcessTree $p
        throw
    }
}

function Start-LfoOwnedSurreal {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][int]$Port,
        [Parameter(Mandatory=$true)][ValidateSet('Normal','High','Realtime')][string]$Priority,
        [Parameter(Mandatory=$true)][string]$LogDirectory,
        [string]$DataDirectoryOverride
    )
    $exe = [string]$State.SurrealDB.Executable
    $data = if (-not [string]::IsNullOrWhiteSpace($DataDirectoryOverride)) {
        [string]$DataDirectoryOverride
    } else {
        [string]$State.SurrealDB.DataDirectory
    }
    $credentialPath = [string]$State.SurrealDB.BootstrapCredentialPath
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "SurrealDB executable not found: $exe" }
    if (-not (Test-Path -LiteralPath $data -PathType Container)) { throw "SurrealDB data directory not found: $data" }
    if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) { throw "SurrealDB bootstrap credential not found: $credentialPath" }

    $credential = Import-Clixml -LiteralPath $credentialPath
    $dbPath = 'rocksdb://' + (Join-Path ([IO.Path]::GetFullPath($data)) 'observations.db').Replace('\','/')
    $args = @(
        'start','--bind',("127.0.0.1:{0}" -f $Port),'--query-timeout','3s',
        '--deny-guests','--deny-scripting','--deny-net','--log','info',$dbPath
    )
    $argLine = (@($args | ForEach-Object { Quote-LfoArgument ([string]$_) }) -join ' ')
    New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
    $stdout = Join-Path $LogDirectory 'surreal.stdout.log'
    $stderr = Join-Path $LogDirectory 'surreal.stderr.log'

    $oldUser = $env:SURREAL_USER
    $oldPass = $env:SURREAL_PASS
    try {
        $env:SURREAL_USER = $credential.UserName
        $env:SURREAL_PASS = $credential.GetNetworkCredential().Password
        $p = Start-Process -FilePath $exe -ArgumentList $argLine -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    } finally {
        $env:SURREAL_USER = $oldUser
        $env:SURREAL_PASS = $oldPass
    }
    $baseUri = "http://127.0.0.1:$Port"
    try {
        [void](Set-LfoProcessPriority -ProcessId $p.Id -Priority $Priority)
        Wait-LfoReady -Name 'SurrealDB' -Seconds 60 -Probe { Test-LfoSurrealReady $baseUri }
        return [pscustomobject]@{ Process = $p; BaseUri = $baseUri }
    } catch {
        Stop-LfoOwnedProcessTree $p
        throw
    }
}

function New-LfoIsolatedSurrealDataCopy {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    $source = [string]$State.SurrealDB.DataDirectory
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Source L4 data directory not found: $source"
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $source -Force -ErrorAction Stop)) {
        Copy-Item -LiteralPath $item.FullName -Destination $Destination -Recurse -Force -ErrorAction Stop
    }
    return $Destination
}

function Get-LfoOllamaPlacement {
    param(
        [Parameter(Mandatory=$true)][string]$BaseUri,
        [Parameter(Mandatory=$true)][string]$Model
    )
    try {
        $ps = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/api/ps') -TimeoutSec 5
        $row = @($ps.models | Where-Object { [string]$_.name -eq $Model } | Select-Object -First 1)
        if ($row.Count -eq 0) { return $null }
        $m = $row[0]
        $size = [double]$m.size
        $vram = [double]$m.size_vram
        return [pscustomobject]@{
            name = [string]$m.name
            size_bytes = [int64]$m.size
            size_vram_bytes = [int64]$m.size_vram
            vram_fraction = $(if ($size -gt 0) { [Math]::Round($vram / $size, 4) } else { 0 })
            expires_at = [string]$m.expires_at
        }
    } catch { return $null }
}

function New-LfoQwen963Adapter {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][string]$DestinationPath
    )
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw "QwenChat source not found: $SourcePath" }
    $content = [IO.File]::ReadAllText($SourcePath)
    if ($content -notmatch '(?m)^param\(' -or $content -notmatch 'function Invoke-Qwen' -or $content.LastIndexOf('while ($true) {') -lt 0) {
        throw 'QwenChat source does not match the supported LFO runtime shape.'
    }

    if ($content -notmatch '\$BatchInputPath') {
        $paramPattern = '(?s)^param\((.*?)\r?\n\)'
        $m = [regex]::Match($content, $paramPattern)
        if (-not $m.Success) { throw 'Unable to locate QwenChat parameter block.' }
        $body = $m.Groups[1].Value.TrimEnd()
        $newParam = "param(`r`n" + $body + ",`r`n" +
            "    [string]`$BatchInputPath,`r`n" +
            "    [string]`$DataDirectoryOverride,`r`n" +
            "    [string]`$BaseUriOverride,`r`n" +
            "    [switch]`$BatchLocalOnly`r`n)"
        $content = $newParam + $content.Substring($m.Index + $m.Length)
    }

    $configNeedle = '$script:Config = Import-PowerShellDataFile -LiteralPath $ConfigPath'
    if ($content.IndexOf($configNeedle) -lt 0) { throw 'Unable to locate QwenChat config import.' }
    if ($content -notmatch 'LFO963_DATA_OVERRIDE') {
        $configInsert = @'

# LFO963_DATA_OVERRIDE: ephemeral batch/runtime overlay; the source config is not modified.
if (-not [string]::IsNullOrWhiteSpace($DataDirectoryOverride)) {
    $script:Config.Memory.DataDirectory = $DataDirectoryOverride
}
if (-not [string]::IsNullOrWhiteSpace($BaseUriOverride)) {
    $script:Config.BaseUri = $BaseUriOverride
}
'@
        $pos = $content.IndexOf($configNeedle) + $configNeedle.Length
        $content = $content.Insert($pos, $configInsert)
    }

    if ($content -notmatch 'LFO963_LOCAL_ONLY_FRONTIER_GUARD') {
        $frontierNeedle = "    if (`$route -eq 'FRONTIER') {"
        $invokePos = $content.IndexOf('function Invoke-Qwen')
        if ($invokePos -lt 0) { throw 'Unable to locate QwenChat Invoke-Qwen function.' }
        # The first FRONTIER branch inside Invoke-Qwen only prints the chosen route.
        # The second is the actual Codex handoff and is the only block we suppress.
        $routeDisplayPos = $content.IndexOf($frontierNeedle, $invokePos)
        if ($routeDisplayPos -lt 0) { throw 'Unable to locate QwenChat FRONTIER route-display block.' }
        $frontierPos = $content.IndexOf($frontierNeedle, $routeDisplayPos + $frontierNeedle.Length)
        if ($frontierPos -lt 0) { throw 'Unable to locate QwenChat FRONTIER handoff block.' }
        $frontierGuard = @'
    # LFO963_LOCAL_ONLY_FRONTIER_GUARD: controlled benchmark must never call Codex.
    $lfo963FrontierSuppressed = $false
    if ($BatchLocalOnly -and $route -eq 'FRONTIER') {
        $lfo963FrontierSuppressed = $true
        $finalContent = '[LFO 9.6.3 benchmark: Qwen requested FRONTIER; frontier call suppressed.]'
        $finalProducer = 'WRAPPER'
        $finalPhase = 'benchmark_frontier_suppressed'
        Write-Host "[batch LOCAL-ONLY] Qwen requested FRONTIER; Codex call suppressed." -ForegroundColor Yellow
    }

    if ($route -eq 'FRONTIER' -and -not $lfo963FrontierSuppressed) {
'@
        $content = $content.Remove($frontierPos, $frontierNeedle.Length).Insert($frontierPos, $frontierGuard)
    }

    if ($content -notmatch 'LFO963_BATCH_MODE') {
        $loopMarker = 'while ($true) {'
        $loopPos = $content.LastIndexOf($loopMarker)
        if ($loopPos -lt 0) { throw 'Unable to locate QwenChat interactive loop.' }
        $batchBlock = @'
# LFO963_BATCH_MODE: unattended experiment input. Uses the exact same Invoke-Qwen path.
if (-not [string]::IsNullOrWhiteSpace($BatchInputPath)) {
    if (-not (Test-Path -LiteralPath $BatchInputPath -PathType Leaf)) {
        throw "Batch input not found: $BatchInputPath"
    }
    $batch = Get-Content -LiteralPath $BatchInputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = @($batch.prompts)
    if ($items.Count -eq 0) { throw 'Batch input contains no prompts.' }
    $batchIndex = 0
    foreach ($item in $items) {
        $batchIndex++
        $text = if ($item -is [string]) { [string]$item } else { [string]$item.text }
        if ([string]::IsNullOrWhiteSpace($text)) { throw 'Batch prompt is empty.' }
        $preview = [regex]::Replace($text.Trim(), '\s+', ' ')
        if ($preview.Length -gt 120) { $preview = $preview.Substring(0,117) + '...' }
        Write-Host ("[batch {0}/{1}] START {2}" -f $batchIndex,$items.Count,$preview) -ForegroundColor Cyan
        $clearBefore = $false
        if ($item -isnot [string] -and $null -ne $item.clear_before) { $clearBefore = [bool]$item.clear_before }
        if ($clearBefore) {
            Write-Host ("[batch {0}/{1}] clearing isolated conversation state" -f $batchIndex,$items.Count) -ForegroundColor DarkGray
            Clear-PersistentConversationMemory
        }
        $batchSw = [Diagnostics.Stopwatch]::StartNew()
        Invoke-Qwen $text
        $batchSw.Stop()
        Write-Host ("[batch {0}/{1}] DONE {2:n2}s" -f $batchIndex,$items.Count,$batchSw.Elapsed.TotalSeconds) -ForegroundColor Green
    }
    exit 0
}

'@
        $content = $content.Insert($loopPos, $batchBlock)
    }

    $content = $content.Replace('Qwen local chat v9.6.2.', 'Qwen local chat v9.6.3.')
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($DestinationPath, $content, $utf8)
    return $DestinationPath
}

function New-LfoBatchInputFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object[]]$Prompts
    )
    $items = @()
    foreach ($p in $Prompts) {
        if ($p -is [string]) {
            $items += [ordered]@{ text = [string]$p; clear_before = $false }
        } else {
            $items += [ordered]@{
                text = [string]$p.text
                clear_before = $(if ($null -ne $p.clear_before) { [bool]$p.clear_before } else { $false })
            }
        }
    }
    $obj = [ordered]@{ prompts = $items }
    $json = $obj | ConvertTo-Json -Depth 8
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $json, $utf8)
}

function Get-LfoTraceRows {
    param([Parameter(Mandatory=$true)][string]$DataDirectory)
    $logDir = Join-Path $DataDirectory 'logs'
    if (-not (Test-Path -LiteralPath $logDir -PathType Container)) { return @() }
    $rows = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $logDir -Filter 'trace-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        foreach ($line in @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                if ([string]$row.event -eq 'turn_trace') { $rows += $row }
            } catch {}
        }
    }
    return @($rows)
}

function Get-LfoGitIdentity {
    param([Parameter(Mandatory=$true)][string]$AppRoot)
    $git = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $git) { $git = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($null -eq $git -or -not (Test-Path -LiteralPath (Join-Path $AppRoot '.git'))) { return $null }
    try {
        $sha = (& $git.Source -C $AppRoot rev-parse HEAD 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { return $null }
        return $sha
    } catch { return $null }
}

function ConvertTo-LfoSafeName {
    param([Parameter(Mandatory=$true)][string]$Text)
    $safe = [regex]::Replace($Text.Trim(), '[^A-Za-z0-9._-]+', '-')
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'experiment' }
    return $safe.Trim('-')
}

function Resolve-LfoExperimentPath {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$PackageRoot)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Resolve-Path -LiteralPath $Path).Path }
    $candidate = Join-Path $PackageRoot $Path
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return (Resolve-Path -LiteralPath $candidate).Path }
    throw "Experiment definition not found: $Path"
}

function Read-LfoExperimentDefinition {
    param([Parameter(Mandatory=$true)][string]$Path)
    $plan = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $plan.schemaVersion -or [int]$plan.schemaVersion -ne 1) { throw 'Experiment schemaVersion must be 1.' }
    if ([string]::IsNullOrWhiteSpace([string]$plan.name)) { throw 'Experiment name is required.' }
    if ($null -eq $plan.conditions -or @($plan.conditions).Count -eq 0) { throw 'Experiment must define at least one condition.' }
    if ($null -eq $plan.workload -or $null -eq $plan.workload.prompts -or @($plan.workload.prompts).Count -eq 0) {
        throw 'Experiment workload.prompts must contain at least one prompt.'
    }
    if ($null -eq $plan.repetitions -or [int]$plan.repetitions -lt 1) { throw 'Experiment repetitions must be at least 1.' }
    return $plan
}

function Get-LfoExperimentOutputRoot {
    param(
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$true)][string]$InstallRoot,
        [Parameter(Mandatory=$true)][string]$ExperimentPath
    )
    $base = $null
    if ($null -ne $Plan.outputDirectory -and -not [string]::IsNullOrWhiteSpace([string]$Plan.outputDirectory)) {
        $candidate = [string]$Plan.outputDirectory
        if ([IO.Path]::IsPathRooted($candidate)) { $base = $candidate }
        else { $base = Join-Path (Split-Path -Parent $ExperimentPath) $candidate }
    } else {
        $base = Join-Path $InstallRoot 'experiments\results'
    }
    return [IO.Path]::GetFullPath($base)
}

function Get-LfoExperimentRunDirectory {
    param(
        [Parameter(Mandatory=$true)]$Plan,
        [Parameter(Mandatory=$true)][string]$OutputRoot,
        [switch]$Resume
    )
    $name = ConvertTo-LfoSafeName ([string]$Plan.name)
    $experimentRoot = Join-Path $OutputRoot $name
    New-Item -ItemType Directory -Force -Path $experimentRoot | Out-Null
    $latestPath = Join-Path $experimentRoot 'latest.txt'
    if ($Resume) {
        if (-not (Test-Path -LiteralPath $latestPath -PathType Leaf)) { throw "No resumable run found for '$name'." }
        $runDir = (Get-Content -LiteralPath $latestPath -Raw -Encoding UTF8).Trim()
        if ([string]::IsNullOrWhiteSpace($runDir) -or -not (Test-Path -LiteralPath $runDir -PathType Container)) {
            throw "latest.txt does not point to a valid run directory: $latestPath"
        }
        return $runDir
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $runDir = Join-Path $experimentRoot $stamp
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    [IO.File]::WriteAllText($latestPath, $runDir, (New-Object Text.UTF8Encoding($false)))
    return $runDir
}

function Read-LfoCheckpoint {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [ordered]@{ completed = @(); failed = @() }
    }
    try {
        $c = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        return [ordered]@{ completed = @($c.completed); failed = @($c.failed) }
    } catch { throw "Checkpoint is unreadable: $Path" }
}

function Write-LfoCheckpoint {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Checkpoint)
    $json = $Checkpoint | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Write-LfoJsonLine {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Object)
    $line = $Object | ConvertTo-Json -Depth 16 -Compress
    [IO.File]::AppendAllText($Path, $line + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Write-LfoExperimentProgress {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$Level = 'STEP'
    )
    $stamp = Get-Date -Format 'HH:mm:ss'
    $color = switch ($Level) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'RUN'   { 'Cyan' }
        default { 'DarkGray' }
    }
    Write-Host ("[{0}] {1,-5} {2}" -f $stamp,$Level,$Message) -ForegroundColor $color
}

function Write-LfoNewLogLines {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][ref]$LineIndex,
        [Parameter(Mandatory=$true)][string]$Prefix,
        [switch]$ShowAll,
        [ref]$InlineProgressOpen
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)
    $start = [int]$LineIndex.Value
    if ($start -lt 0) { $start = 0 }
    if ($lines.Count -le $start) { return }
    for ($i = $start; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $show = $ShowAll -or
            $line -match '^\[batch ' -or
            $line -match '^\[Qwen route ' -or
            $line -match '^\[batch LOCAL-ONLY\]' -or
            $line -match '^\[policy ' -or
            $line -match '^\[L4 ' -or
            $line -match '^\[l2:' -or
            $line -match '^\[memory:' -or
            $line -match '^\[[0-9]+(?:\.[0-9]+)?s;' -or
            $line -match '^Ollama ' -or
            $line -match '^Qwen local chat '
        if ($show) {
            if ($null -ne $InlineProgressOpen -and [bool]$InlineProgressOpen.Value) {
                Write-Host ''
                $InlineProgressOpen.Value = $false
            }
            Write-Host ("{0}{1}" -f $Prefix,$line) -ForegroundColor DarkGray
        }
    }
    $LineIndex.Value = $lines.Count
}

function Start-LfoBatchQwenProcess {
    param(
        [Parameter(Mandatory=$true)][string]$SelfPath,
        [Parameter(Mandatory=$true)][string]$QwenChatPath,
        [Parameter(Mandatory=$true)][string]$Model,
        [Parameter(Mandatory=$true)][string]$ConfigPath,
        [Parameter(Mandatory=$true)][int]$ContextLengthHint,
        [Parameter(Mandatory=$true)][string]$BaseUri,
        [Parameter(Mandatory=$true)][string]$DataDirectory,
        [Parameter(Mandatory=$true)][string]$BatchInputPath,
        [Parameter(Mandatory=$true)][ValidateSet('Normal','High','Realtime')][string]$Priority,
        [Parameter(Mandatory=$true)][ValidateSet('On','Off')][string]$L4,
        [string]$L4Endpoint,
        [string]$L4CredentialPath,
        [switch]$LocalOnly,
        [Parameter(Mandatory=$true)][string]$StdoutPath,
        [Parameter(Mandatory=$true)][string]$StderrPath
    )
    $args = @(
        '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$SelfPath,
        '-InternalBatchChild',
        '-QwenChatPath',$QwenChatPath,'-Model',$Model,'-ConfigPath',$ConfigPath,
        '-ContextLengthHint',[string]$ContextLengthHint,'-BaseUri',$BaseUri,
        '-DataDirectory',$DataDirectory,'-BatchInputPath',$BatchInputPath,
        '-Priority',$Priority,'-L4',$L4
    )
    if ($L4 -eq 'On') { $args += @('-L4Endpoint',$L4Endpoint,'-L4CredentialPath',$L4CredentialPath) }
    if ($LocalOnly) { $args += '-BatchLocalOnly' }
    $argLine = (@($args | ForEach-Object { Quote-LfoArgument ([string]$_) }) -join ' ')
    $p = Start-Process powershell.exe -ArgumentList $argLine -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    Write-LfoExperimentProgress ("Qwen batch child started: PID {0}; priority={1}; L4={2}; local-only={3}" -f $p.Id,$Priority,$L4,[bool]$LocalOnly) 'RUN'
    $stdoutIndex = 0
    $stderrIndex = 0
    $heartbeat = [Diagnostics.Stopwatch]::StartNew()
    $lastHeartbeat = -5.0
    $heartbeatLineOpen = $false
    while (-not $p.HasExited) {
        Write-LfoNewLogLines -Path $StdoutPath -LineIndex ([ref]$stdoutIndex) -Prefix '    ' -InlineProgressOpen ([ref]$heartbeatLineOpen)
        Write-LfoNewLogLines -Path $StderrPath -LineIndex ([ref]$stderrIndex) -Prefix '    ERROR: ' -ShowAll -InlineProgressOpen ([ref]$heartbeatLineOpen)
        if (($heartbeat.Elapsed.TotalSeconds - $lastHeartbeat) -ge 5.0) {
            if (-not $heartbeatLineOpen) {
                $stamp = Get-Date -Format 'HH:mm:ss'
                Write-Host ("[{0}] RUN   Qwen batch PID {1} still running" -f $stamp,$p.Id) -NoNewline -ForegroundColor Cyan
                $heartbeatLineOpen = $true
            } else {
                Write-Host '.' -NoNewline -ForegroundColor DarkGray
            }
            $lastHeartbeat = $heartbeat.Elapsed.TotalSeconds
        }
        Start-Sleep -Milliseconds 300
        $p.Refresh()
    }
    $p.WaitForExit()
    try { $p.Refresh() } catch {}
    Write-LfoNewLogLines -Path $StdoutPath -LineIndex ([ref]$stdoutIndex) -Prefix '    ' -InlineProgressOpen ([ref]$heartbeatLineOpen)
    Write-LfoNewLogLines -Path $StderrPath -LineIndex ([ref]$stderrIndex) -Prefix '    ERROR: ' -ShowAll -InlineProgressOpen ([ref]$heartbeatLineOpen)
    if ($heartbeatLineOpen) {
        Write-Host ''
        $heartbeatLineOpen = $false
    }
    $heartbeat.Stop()

    # Windows PowerShell 5.1 can occasionally expose a blank ExitCode on a
    # Start-Process -PassThru object after redirected child execution. Treat
    # that as an observability defect, not automatically as a failed sample.
    $exitCode = $null
    try { $exitCode = $p.ExitCode } catch {}
    if ($null -eq $exitCode) {
        $expectedPrompts = 0
        try {
            $batchCheck = Get-Content -LiteralPath $BatchInputPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $expectedPrompts = @($batchCheck.prompts).Count
        } catch {}
        $stdoutLines = @()
        if (Test-Path -LiteralPath $StdoutPath -PathType Leaf) {
            $stdoutLines = @(Get-Content -LiteralPath $StdoutPath -Encoding UTF8 -ErrorAction SilentlyContinue)
        }
        $doneCount = @($stdoutLines | Where-Object { [string]$_ -match '^\[batch [0-9]+/[0-9]+\] DONE ' }).Count
        $stderrText = ''
        if (Test-Path -LiteralPath $StderrPath -PathType Leaf) {
            $stderrText = [string](Get-Content -LiteralPath $StderrPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        }
        if ($expectedPrompts -gt 0 -and $doneCount -eq $expectedPrompts -and [string]::IsNullOrWhiteSpace($stderrText)) {
            $exitCode = 0
            Write-LfoExperimentProgress ("PID {0}: Windows PowerShell returned no ExitCode; verified {1}/{1} batch completion marker(s) and empty stderr -> success" -f $p.Id,$expectedPrompts) 'WARN'
        } else {
            $exitCode = 1
            Write-LfoExperimentProgress ("PID {0}: Windows PowerShell returned no ExitCode and completion verification failed (DONE={1}/{2}; stderr_empty={3})" -f $p.Id,$doneCount,$expectedPrompts,[string]::IsNullOrWhiteSpace($stderrText)) 'ERROR'
        }
    }

    Write-LfoExperimentProgress ("Qwen batch PID {0} exited with code {1} after {2:n2}s" -f $p.Id,$exitCode,$heartbeat.Elapsed.TotalSeconds) $(if ($exitCode -eq 0) {'OK'} else {'ERROR'})
    return [int]$exitCode
}

function Get-LfoConditionEnabled {
    param($Condition)
    if ($null -eq $Condition.enabled) { return $true }
    return [bool]$Condition.enabled
}

function Assert-LfoExperimentEnvironmentQuiet {
    param([Parameter(Mandatory=$true)]$State,[Parameter(Mandatory=$true)]$Plan)
    $allowAmbient = $false
    if ($null -ne $Plan.allowAmbientServices) { $allowAmbient = [bool]$Plan.allowAmbientServices }
    if ($allowAmbient) { return }
    $ollamaUri = [string]$State.Ollama.BaseUri
    $surrealUri = [string]$State.SurrealDB.BaseUri
    $active = @()
    if (-not [string]::IsNullOrWhiteSpace($ollamaUri) -and (Test-LfoOllamaReady $ollamaUri)) { $active += "Ollama at $ollamaUri" }
    if (-not [string]::IsNullOrWhiteSpace($surrealUri) -and (Test-LfoSurrealReady $surrealUri)) { $active += "SurrealDB at $surrealUri" }
    if ($active.Count -gt 0) {
        throw ('Ambient LFO services are already running: ' + ($active -join '; ') + '. Close the active LFO service windows before a controlled experiment, or set allowAmbientServices=true if the ambient load is intentional.')
    }
}

function Get-LfoPromptArray {
    param($Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}

function Get-LfoMetricRowsFromTrace {
    param(
        [Parameter(Mandatory=$true)][object[]]$TraceRows,
        [Parameter(Mandatory=$true)][int]$MeasuredPromptCount,
        [Parameter(Mandatory=$true)][string]$ConditionName,
        [Parameter(Mandatory=$true)][int]$Repetition,
        [Parameter(Mandatory=$true)][string]$Priority,
        [Parameter(Mandatory=$true)][bool]$L4Enabled,
        [Parameter(Mandatory=$true)][string]$Device,
        [Parameter(Mandatory=$true)][string]$Model,
        $Placement
    )
    if ($TraceRows.Count -lt $MeasuredPromptCount) {
        throw "Expected at least $MeasuredPromptCount turn traces, got $($TraceRows.Count)."
    }
    $selected = @($TraceRows | Select-Object -Last $MeasuredPromptCount)
    $out = @()
    for ($i=0; $i -lt $selected.Count; $i++) {
        $t = $selected[$i]
        $perf = $t.performance
        if ($null -eq $perf) { throw "Measured turn $($i+1) has no model performance block." }
        $promptCount = [double]$perf.prompt_eval_count
        $promptNs = [double]$perf.prompt_eval_duration
        $evalCount = [double]$perf.eval_count
        $evalNs = [double]$perf.eval_duration
        $out += [ordered]@{
            condition = $ConditionName
            repetition = $Repetition
            prompt_index = $i + 1
            priority = $Priority
            l4_enabled = $L4Enabled
            device = $Device
            model = $Model
            route = [string]$t.route
            route_reason = [string]$t.route_reason
            prompt_eval_count = [int64]$promptCount
            prompt_eval_duration_ns = [int64]$promptNs
            prefill_tokens_per_second = $(if ($promptNs -gt 0) { [Math]::Round($promptCount * 1e9 / $promptNs, 4) } else { $null })
            eval_count = [int64]$evalCount
            eval_duration_ns = [int64]$evalNs
            decode_tokens_per_second = $(if ($evalNs -gt 0) { [Math]::Round($evalCount * 1e9 / $evalNs, 4) } else { $null })
            answer_seconds = [double]$t.answer_seconds
            local_generation_wall_seconds = $(
                $phase = @($t.dev4_phases | Where-Object { [string]$_.phase -eq 'local_generation' } | Select-Object -First 1)
                if ($phase.Count -gt 0) { [double]$phase[0].wall_seconds } else { $null }
            )
            l2_status = [string]$t.l2_status
            l3_index_status = [string]$t.l3_index_status
            dev5_local_output_mode = [string]$t.dev5_local_output_mode
            dev5_read_policy_mode = [string]$t.dev5_read_policy_mode
            ollama_size_bytes = $(if ($null -ne $Placement) { [int64]$Placement.size_bytes } else { $null })
            ollama_size_vram_bytes = $(if ($null -ne $Placement) { [int64]$Placement.size_vram_bytes } else { $null })
            ollama_vram_fraction = $(if ($null -ne $Placement) { [double]$Placement.vram_fraction } else { $null })
        }
    }
    return @($out)
}

function Write-LfoExperimentSummary {
    param(
        [Parameter(Mandatory=$true)][string]$ResultsJsonl,
        [Parameter(Mandatory=$true)][string]$RunDirectory
    )
    $rows = @()
    if (Test-Path -LiteralPath $ResultsJsonl -PathType Leaf) {
        foreach ($line in @(Get-Content -LiteralPath $ResultsJsonl -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $rows += ($line | ConvertFrom-Json) } catch {}
        }
    }
    if ($rows.Count -eq 0) { return @() }
    $summary = @()
    foreach ($group in @($rows | Group-Object condition)) {
        $decode = @($group.Group | ForEach-Object { [double]$_.decode_tokens_per_second })
        $prefill = @($group.Group | ForEach-Object { [double]$_.prefill_tokens_per_second })
        $answer = @($group.Group | ForEach-Object { [double]$_.answer_seconds })
        $summary += [pscustomobject][ordered]@{
            condition = $group.Name
            samples = $group.Count
            priority = [string]$group.Group[0].priority
            l4_enabled = [bool]$group.Group[0].l4_enabled
            device = [string]$group.Group[0].device
            decode_tok_s_mean = [Math]::Round((($decode | Measure-Object -Average).Average),4)
            prefill_tok_s_mean = [Math]::Round((($prefill | Measure-Object -Average).Average),4)
            answer_seconds_mean = [Math]::Round((($answer | Measure-Object -Average).Average),4)
        }
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $RunDirectory 'summary.json') -Encoding UTF8
    $summary | Export-Csv -LiteralPath (Join-Path $RunDirectory 'summary.csv') -NoTypeInformation -Encoding UTF8
    return @($summary)
}

function Invoke-LfoExperiment {
    param(
        [Parameter(Mandatory=$true)][string]$ExperimentPath,
        [AllowNull()][string]$DeviceOverride,
        [Parameter(Mandatory=$true)][string]$InstallRoot,
        [Parameter(Mandatory=$true)][string]$PackageRoot,
        [Parameter(Mandatory=$true)][string]$SelfPath,
        [switch]$Resume
    )

    $state = Get-LfoInstallState $InstallRoot
    $experimentPathResolved = Resolve-LfoExperimentPath $ExperimentPath $PackageRoot
    $plan = Read-LfoExperimentDefinition $experimentPathResolved
    Assert-LfoExperimentEnvironmentQuiet $state $plan

    $requestedDevice = if (-not [string]::IsNullOrWhiteSpace($DeviceOverride)) {
        $DeviceOverride
    } elseif ($null -ne $plan.device -and -not [string]::IsNullOrWhiteSpace([string]$plan.device)) {
        [string]$plan.device
    } else { 'Auto' }
    $minGpu = if ($null -ne $plan.minimumGpuVramMiB) { [int]$plan.minimumGpuVramMiB } else { 6144 }
    $device = Resolve-LfoDevice $requestedDevice $state $minGpu
    $modelSpec = Get-LfoModelSpec $state $device
    if ([string]::IsNullOrWhiteSpace([string]$modelSpec.Model)) { throw "No $device model alias is configured in install-state.json." }

    $outputRoot = Get-LfoExperimentOutputRoot $plan $InstallRoot $experimentPathResolved
    $runDir = Get-LfoExperimentRunDirectory $plan $outputRoot -Resume:$Resume
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $checkpointPath = Join-Path $runDir 'checkpoint.json'
    $resultsPath = Join-Path $runDir 'results.jsonl'
    $failuresPath = Join-Path $runDir 'failures.jsonl'
    $checkpoint = Read-LfoCheckpoint $checkpointPath

    $qwenSource = Join-Path ([string]$state.AppRoot) 'src\QwenChat.ps1'
    $adapterName = 'QwenChat.lfo963.' + [guid]::NewGuid().ToString('N') + '.ps1'
    $qwenAdapter = Join-Path (Split-Path -Parent $qwenSource) $adapterName
    [void](New-LfoQwen963Adapter $qwenSource $qwenAdapter)

    $localOnly = $(if ($null -ne $plan.localOnly) { [bool]$plan.localOnly } else { $true })

    $resolved = [ordered]@{
        runtime = 'LFO 9.6.3'
        base_runtime = 'v9.6.3 production launcher over accepted QwenChat semantics'
        experiment = [string]$plan.name
        definition = $experimentPathResolved
        started_at = (Get-Date).ToString('o')
        install_root = [IO.Path]::GetFullPath($InstallRoot)
        app_root = [string]$state.AppRoot
        app_git_sha = Get-LfoGitIdentity ([string]$state.AppRoot)
        requested_device = $requestedDevice
        resolved_device = $device
        model = [string]$modelSpec.Model
        context_length = [int]$modelSpec.Context
        minimum_gpu_vram_mib = $minGpu
        repetitions = [int]$plan.repetitions
        allow_realtime = $(if ($null -ne $plan.allowRealtime) { [bool]$plan.allowRealtime } else { $false })
        conditions = @($plan.conditions)
        workload = $plan.workload
        warmup = $plan.warmup
        isolated_prompt_processes = $true
        benchmark_local_only = $localOnly
        frontier_calls_suppressed = $localOnly
    }
    $resolved | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $runDir 'experiment.resolved.json') -Encoding UTF8

    $warmupPrompts = @()
    if ($null -ne $plan.warmup -and $null -ne $plan.warmup.prompts) { $warmupPrompts = Get-LfoPromptArray $plan.warmup.prompts }
    if ($warmupPrompts.Count -eq 0) { $warmupPrompts = @($plan.workload.prompts | Select-Object -First 1) }
    $setupPrompts = @()
    if ($null -ne $plan.workload.setupPrompts) { $setupPrompts = Get-LfoPromptArray $plan.workload.setupPrompts }
    $measuredPrompts = Get-LfoPromptArray $plan.workload.prompts

    try {
        Write-Host ("LFO 9.6.3 experiment: {0}" -f [string]$plan.name) -ForegroundColor Cyan
        Write-Host ("Device: {0}; model: {1}; repetitions: {2}" -f $device,[string]$modelSpec.Model,[int]$plan.repetitions)
        Write-Host ("Results: {0}" -f $runDir)
        Write-LfoExperimentProgress ("resolved install root: {0}" -f $InstallRoot) 'OK'
        Write-LfoExperimentProgress ("resolved model: {0}; context={1}" -f [string]$modelSpec.Model,[int]$modelSpec.Context) 'OK'
        Write-LfoExperimentProgress ("measured prompts per repetition: {0}; warm-up prompts: {1}; each measured prompt gets a fresh Qwen process + memory state" -f $measuredPrompts.Count,$warmupPrompts.Count) 'STEP'
        if ($localOnly) {
            Write-LfoExperimentProgress 'benchmark LOCAL-only guard: ON; Qwen may propose FRONTIER, but Codex will never be called' 'STEP'
        } else {
            Write-LfoExperimentProgress 'benchmark LOCAL-only guard: OFF; FRONTIER behavior follows ordinary LFO routing' 'WARN'
        }

        foreach ($condition in @($plan.conditions)) {
            if (-not (Get-LfoConditionEnabled $condition)) { continue }
            $conditionName = ConvertTo-LfoSafeName ([string]$condition.name)
            $priority = [string]$condition.priority
            if ($priority -notin @('Normal','High','Realtime')) { throw "Condition '$conditionName' has invalid priority '$priority'." }
            $l4Enabled = [bool]$condition.l4
            if ($priority -eq 'Realtime' -and -not [bool]$resolved.allow_realtime) {
                throw "Condition '$conditionName' requests Realtime but allowRealtime is false."
            }

            Write-Host ''
            Write-Host ("[{0}] priority={1}; L4={2}" -f $conditionName,$priority,$l4Enabled) -ForegroundColor Cyan
            Write-LfoExperimentProgress ("condition start: {0}" -f $conditionName) 'RUN'
            $conditionDir = Join-Path $runDir $conditionName
            New-Item -ItemType Directory -Force -Path $conditionDir | Out-Null
            $serviceLogDir = Join-Path $conditionDir 'service-logs'
            $ollamaPort = Get-LfoFreeTcpPort 12434
            $ollamaUri = "http://127.0.0.1:$ollamaPort"
            $surreal = $null
            $ollama = $null
            try {
                if ($l4Enabled) {
                    $surrealPort = Get-LfoFreeTcpPort 19080
                    $isolatedSurrealData = Join-Path $conditionDir 'l4-store'
                    Write-LfoExperimentProgress ("copying production L4 store to isolated test store: {0}" -f $isolatedSurrealData) 'STEP'
                    [void](New-LfoIsolatedSurrealDataCopy -State $state -Destination $isolatedSurrealData)
                    Write-LfoExperimentProgress ("starting isolated SurrealDB on port {0}" -f $surrealPort) 'RUN'
                    $surreal = Start-LfoOwnedSurreal -State $state -Port $surrealPort -Priority $priority `
                        -LogDirectory $serviceLogDir -DataDirectoryOverride $isolatedSurrealData
                    Write-LfoExperimentProgress ("SurrealDB ready: PID {0}; endpoint={1}" -f $surreal.Process.Id,$surreal.BaseUri) 'OK'
                } else {
                    Write-LfoExperimentProgress 'L4 disabled for this condition; SurrealDB will not be started.' 'STEP'
                }
                Write-LfoExperimentProgress ("starting owned Ollama on {0}" -f $ollamaUri) 'RUN'
                $ollama = Start-LfoOwnedOllama -State $state -BaseUri $ollamaUri -Priority $priority -LogDirectory $serviceLogDir
                Write-LfoExperimentProgress ("Ollama ready: PID {0}; priority={1}" -f $ollama.Id,$priority) 'OK'
                Assert-LfoOllamaModelAvailable -BaseUri $ollamaUri -Model ([string]$modelSpec.Model)
                Write-LfoExperimentProgress ("model alias verified: {0}" -f [string]$modelSpec.Model) 'OK'

                # Warm-up through the same QwenChat path. Its data is discarded.
                Write-LfoExperimentProgress ("warm-up start ({0} prompt(s))" -f $warmupPrompts.Count) 'RUN'
                $warmDir = Join-Path $conditionDir 'warmup'
                New-Item -ItemType Directory -Force -Path $warmDir | Out-Null
                $warmInput = Join-Path $warmDir 'batch.json'
                New-LfoBatchInputFile $warmInput $warmupPrompts
                $warmStdout = Join-Path $warmDir 'qwen.stdout.log'
                $warmStderr = Join-Path $warmDir 'qwen.stderr.log'
                $warmExit = Start-LfoBatchQwenProcess -SelfPath $SelfPath -QwenChatPath $qwenAdapter `
                    -Model ([string]$modelSpec.Model) -ConfigPath ([string]$state.LFO.ConfigPath) `
                    -ContextLengthHint ([int]$modelSpec.Context) -BaseUri $ollamaUri `
                    -DataDirectory (Join-Path $warmDir 'data') -BatchInputPath $warmInput -Priority $priority `
                    -L4 $(if ($l4Enabled) {'On'} else {'Off'}) `
                    -L4Endpoint $(if ($l4Enabled) {$surreal.BaseUri} else {''}) `
                    -L4CredentialPath $(if ($l4Enabled) {[string]$state.SurrealDB.RuntimeCredentialPath} else {''}) `
                    -LocalOnly:$localOnly `
                    -StdoutPath $warmStdout -StderrPath $warmStderr
                if ($warmExit -ne 0) { throw "Warm-up failed with exit code $warmExit. See $warmStderr" }
                Write-LfoExperimentProgress 'warm-up PASS; model is resident' 'OK'

                # The Ollama model runner now exists; explicitly normalize the whole owned process tree.
                $priorityTree = @(Set-LfoProcessTreePriority -RootProcessId $ollama.Id -Priority $priority)
                $priorityTree | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $conditionDir 'process-priority.json') -Encoding UTF8
                foreach ($priorityRow in $priorityTree) {
                    Write-LfoExperimentProgress ("priority verified: PID {0} {1} = {2}" -f $priorityRow.pid,$priorityRow.name,$priorityRow.priority) 'OK'
                }
                $placement = Get-LfoOllamaPlacement $ollamaUri ([string]$modelSpec.Model)
                if ($device -eq 'GPU' -and ($null -eq $placement -or [int64]$placement.size_vram_bytes -le 0)) {
                    throw 'GPU was requested/resolved, but Ollama reports no VRAM residency after warm-up.'
                }
                if ($device -eq 'CPU' -and $null -ne $placement -and [int64]$placement.size_vram_bytes -gt 0) {
                    throw 'CPU was requested/resolved, but Ollama reports GPU VRAM residency after warm-up.'
                }
                $placement | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $conditionDir 'ollama-placement.json') -Encoding UTF8
                if ($null -ne $placement) {
                    Write-LfoExperimentProgress ("Ollama placement: size={0:N0} MiB; VRAM={1:N0} MiB; VRAM fraction={2}" -f ($placement.size_bytes/1MB),($placement.size_vram_bytes/1MB),$placement.vram_fraction) 'OK'
                }

                for ($rep = 1; $rep -le [int]$plan.repetitions; $rep++) {
                    Write-LfoExperimentProgress ("repetition {0}/{1} start; measured prompts={2}" -f $rep,[int]$plan.repetitions,$measuredPrompts.Count) 'RUN'
                    $repDir = Join-Path $conditionDir ('rep-{0:D3}' -f $rep)
                    New-Item -ItemType Directory -Force -Path $repDir | Out-Null

                    for ($promptIndex = 1; $promptIndex -le $measuredPrompts.Count; $promptIndex++) {
                        $key = "$conditionName|$rep|$promptIndex"
                        if (@($checkpoint.completed) -contains $key) {
                            Write-LfoExperimentProgress ("rep {0} prompt {1}/{2} already terminal; skipping (resume)" -f $rep,$promptIndex,$measuredPrompts.Count) 'STEP'
                            continue
                        }

                        $promptItem = $measuredPrompts[$promptIndex - 1]
                        $promptText = if ($promptItem -is [string]) { [string]$promptItem } else { [string]$promptItem.text }
                        $preview = [regex]::Replace($promptText.Trim(), '\s+', ' ')
                        if ($preview.Length -gt 180) { $preview = $preview.Substring(0,177) + '...' }

                        Write-LfoExperimentProgress ("rep {0} prompt {1}/{2} START: {3}" -f $rep,$promptIndex,$measuredPrompts.Count,$preview) 'RUN'
                        Write-LfoExperimentProgress ("rep {0} prompt {1}: creating fresh Qwen process and isolated memory state" -f $rep,$promptIndex) 'STEP'

                        $sampleDir = Join-Path $repDir ('prompt-{0:D2}' -f $promptIndex)
                        New-Item -ItemType Directory -Force -Path $sampleDir | Out-Null
                        $samplePrompts = @($setupPrompts + @($promptItem))
                        $batchInput = Join-Path $sampleDir 'batch.json'
                        New-LfoBatchInputFile $batchInput $samplePrompts
                        $stdout = Join-Path $sampleDir 'qwen.stdout.log'
                        $stderr = Join-Path $sampleDir 'qwen.stderr.log'
                        $dataDir = Join-Path $sampleDir 'data'

                        $exit = Start-LfoBatchQwenProcess -SelfPath $SelfPath -QwenChatPath $qwenAdapter `
                            -Model ([string]$modelSpec.Model) -ConfigPath ([string]$state.LFO.ConfigPath) `
                            -ContextLengthHint ([int]$modelSpec.Context) -BaseUri $ollamaUri `
                            -DataDirectory $dataDir -BatchInputPath $batchInput -Priority $priority `
                            -L4 $(if ($l4Enabled) {'On'} else {'Off'}) `
                            -L4Endpoint $(if ($l4Enabled) {$surreal.BaseUri} else {''}) `
                            -L4CredentialPath $(if ($l4Enabled) {[string]$state.SurrealDB.RuntimeCredentialPath} else {''}) `
                            -LocalOnly:$localOnly `
                            -StdoutPath $stdout -StderrPath $stderr

                        if ($exit -ne 0) {
                            $failure = [ordered]@{
                                timestamp = (Get-Date).ToString('o')
                                condition = $conditionName
                                repetition = $rep
                                prompt_index = $promptIndex
                                outcome = 'child_process_failure'
                                exit_code = $exit
                                prompt = $promptText
                                stderr = $stderr
                            }
                            Write-LfoJsonLine $failuresPath $failure
                            $checkpoint.completed = @($checkpoint.completed) + $key
                            $checkpoint.failed = @($checkpoint.failed) + $key
                            Write-LfoCheckpoint $checkpointPath $checkpoint
                            Write-LfoExperimentProgress ("rep {0} prompt {1}/{2} FAIL: Qwen child exit code {3}; continuing" -f $rep,$promptIndex,$measuredPrompts.Count,$exit) 'ERROR'
                            continue
                        }

                        Write-LfoExperimentProgress ("rep {0} prompt {1}: Qwen child completed; reading isolated trace" -f $rep,$promptIndex) 'STEP'
                        $traces = @(Get-LfoTraceRows $dataDir)
                        Write-LfoExperimentProgress ("rep {0} prompt {1}: trace rows found={2} (setup={3}, measured=1)" -f $rep,$promptIndex,$traces.Count,$setupPrompts.Count) 'STEP'

                        if ($traces.Count -lt 1) {
                            $failure = [ordered]@{
                                timestamp = (Get-Date).ToString('o')
                                condition = $conditionName
                                repetition = $rep
                                prompt_index = $promptIndex
                                outcome = 'missing_trace'
                                prompt = $promptText
                            }
                            Write-LfoJsonLine $failuresPath $failure
                            $checkpoint.completed = @($checkpoint.completed) + $key
                            $checkpoint.failed = @($checkpoint.failed) + $key
                            Write-LfoCheckpoint $checkpointPath $checkpoint
                            Write-LfoExperimentProgress ("rep {0} prompt {1}/{2} FAIL: no turn trace; continuing" -f $rep,$promptIndex,$measuredPrompts.Count) 'ERROR'
                            continue
                        }

                        $metricRows = @(Get-LfoMetricRowsFromTrace -TraceRows $traces -MeasuredPromptCount 1 `
                            -ConditionName $conditionName -Repetition $rep -Priority $priority -L4Enabled $l4Enabled `
                            -Device $device -Model ([string]$modelSpec.Model) -Placement $placement)
                        $metricRow = $metricRows[0]
                        $metricRow.prompt_index = $promptIndex

                        Write-LfoExperimentProgress ("rep {0} prompt {1}/{2}: route={3}; reason={4}; prompt={5} tok; generated={6} tok; decode={7} tok/s; prefill={8} tok/s; answer={9:n2}s" -f `
                            $rep,$promptIndex,$measuredPrompts.Count,$metricRow.route,$metricRow.route_reason,$metricRow.prompt_eval_count,$metricRow.eval_count,$metricRow.decode_tokens_per_second,$metricRow.prefill_tokens_per_second,$metricRow.answer_seconds) 'STEP'

                        # Any non-LOCAL turn in this fresh sample (including intentional setup)
                        # invalidates it. Codex cannot run because the adapter suppressed the handoff.
                        $nonLocalTrace = @($traces | Where-Object { [string]$_.route -ne 'LOCAL' } | Select-Object -First 1)
                        if ($localOnly -and $nonLocalTrace.Count -gt 0) {
                            $bad = $nonLocalTrace[0]
                            $failure = [ordered]@{
                                timestamp = (Get-Date).ToString('o')
                                condition = $conditionName
                                repetition = $rep
                                prompt_index = $promptIndex
                                outcome = 'routing_failure'
                                route = [string]$bad.route
                                route_reason = [string]$bad.route_reason
                                prompt = $promptText
                                prompt_eval_count = [int64]$metricRow.prompt_eval_count
                                eval_count = [int64]$metricRow.eval_count
                                decode_tokens_per_second = $metricRow.decode_tokens_per_second
                                note = 'FRONTIER was proposed by Qwen but Codex was suppressed by the benchmark LOCAL-only guard.'
                            }
                            Write-LfoJsonLine $failuresPath $failure
                            $checkpoint.completed = @($checkpoint.completed) + $key
                            $checkpoint.failed = @($checkpoint.failed) + $key
                            Write-LfoCheckpoint $checkpointPath $checkpoint
                            Write-LfoExperimentProgress ("rep {0} prompt {1}/{2} ROUTING FAILURE: route={3}; Codex NOT called; sample excluded; continuing" -f `
                                $rep,$promptIndex,$measuredPrompts.Count,[string]$bad.route) 'WARN'
                            continue
                        }

                        if ([int64]$metricRow.eval_count -le 0 -or [int64]$metricRow.eval_duration_ns -le 0) {
                            $failure = [ordered]@{
                                timestamp = (Get-Date).ToString('o')
                                condition = $conditionName
                                repetition = $rep
                                prompt_index = $promptIndex
                                outcome = 'invalid_decode_metrics'
                                prompt = $promptText
                            }
                            Write-LfoJsonLine $failuresPath $failure
                            $checkpoint.completed = @($checkpoint.completed) + $key
                            $checkpoint.failed = @($checkpoint.failed) + $key
                            Write-LfoCheckpoint $checkpointPath $checkpoint
                            Write-LfoExperimentProgress ("rep {0} prompt {1}/{2} FAIL: unusable decode metrics; continuing" -f $rep,$promptIndex,$measuredPrompts.Count) 'ERROR'
                            continue
                        }

                        Write-LfoJsonLine $resultsPath $metricRow
                        $checkpoint.completed = @($checkpoint.completed) + $key
                        $checkpoint.failed = @($checkpoint.failed | Where-Object { $_ -ne $key })
                        Write-LfoCheckpoint $checkpointPath $checkpoint
                        Write-LfoExperimentProgress ("rep {0} prompt {1}/{2} PASS; result committed" -f $rep,$promptIndex,$measuredPrompts.Count) 'OK'
                    }

                    Write-LfoExperimentProgress ("repetition {0}/{1} finished" -f $rep,[int]$plan.repetitions) 'OK'
                }
            } finally {
                if ($null -ne $ollama) {
                    Write-LfoExperimentProgress ("stopping owned Ollama PID {0}" -f $ollama.Id) 'STEP'
                    Stop-LfoOwnedProcessTree $ollama
                }
                if ($null -ne $surreal) {
                    Write-LfoExperimentProgress ("stopping isolated SurrealDB PID {0}" -f $surreal.Process.Id) 'STEP'
                    Stop-LfoOwnedProcessTree $surreal.Process
                }
                Start-Sleep -Milliseconds 400
                Write-LfoExperimentProgress ("condition end: {0}" -f $conditionName) 'OK'
            }
        }

        $summary = @(Write-LfoExperimentSummary $resultsPath $runDir)
        $failureCount = 0
        if (Test-Path -LiteralPath $failuresPath -PathType Leaf) {
            $failureCount = @(Get-Content -LiteralPath $failuresPath -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
        }
        Write-Host ''
        if ($failureCount -gt 0) {
            Write-Host ("Experiment complete with {0} excluded/failed sample(s). See failures.jsonl." -f $failureCount) -ForegroundColor Yellow
        } else {
            Write-Host 'Experiment complete; all measured samples PASS.' -ForegroundColor Green
        }
        if ($summary.Count -gt 0) {
            $summary | Format-Table condition,samples,priority,l4_enabled,device,decode_tok_s_mean,prefill_tok_s_mean,answer_seconds_mean -AutoSize
        }
        return [pscustomobject]@{ RunDirectory = $runDir; Summary = $summary; FailureCount = $failureCount }
    } finally {
        Remove-Item -LiteralPath $qwenAdapter -Force -ErrorAction SilentlyContinue
    }
}


function Invoke-LfoInternalBatchChild {
    if (-not $InternalBatchChild) { return $false }

    foreach ($required in @(
        @{Name='QwenChatPath';Value=$QwenChatPath},
        @{Name='Model';Value=$Model},
        @{Name='ConfigPath';Value=$ConfigPath},
        @{Name='BaseUri';Value=$BaseUri},
        @{Name='DataDirectory';Value=$DataDirectory},
        @{Name='BatchInputPath';Value=$BatchInputPath},
        @{Name='Priority';Value=$Priority},
        @{Name='L4';Value=$L4}
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
            throw "Internal batch parameter missing: $($required.Name)"
        }
    }
    if ($null -eq $ContextLengthHint -or [int]$ContextLengthHint -le 0) {
        throw 'Internal batch ContextLengthHint is missing or invalid.'
    }

    [Diagnostics.Process]::GetCurrentProcess().PriorityClass = Resolve-LfoPriorityClass $Priority

    $env:LFO_L4_ENABLED = $(if ($L4 -eq 'On') { '1' } else { '0' })
    if ($L4 -eq 'On') {
        if ([string]::IsNullOrWhiteSpace($L4Endpoint) -or [string]::IsNullOrWhiteSpace($L4CredentialPath)) {
            throw 'Internal L4 batch mode requires endpoint and runtime credential.'
        }
        $env:LFO_L4_ENDPOINT = $L4Endpoint
        $env:LFO_L4_RUNTIME_CREDENTIAL = $L4CredentialPath
        $env:LFO_L4_OBSERVABILITY = '1'
    } else {
        Remove-Item Env:LFO_L4_ENDPOINT -ErrorAction SilentlyContinue
        Remove-Item Env:LFO_L4_RUNTIME_CREDENTIAL -ErrorAction SilentlyContinue
        $env:LFO_L4_OBSERVABILITY = '0'
    }

    & $QwenChatPath -Model $Model -ConfigPath $ConfigPath -ContextLengthHint ([int]$ContextLengthHint) `
        -BaseUriOverride $BaseUri -DataDirectoryOverride $DataDirectory -BatchInputPath $BatchInputPath `
        -BatchLocalOnly:$BatchLocalOnly
    exit $LASTEXITCODE
}



try {
    [void](Invoke-LfoInternalBatchChild)

    $scriptRoot = $PSScriptRoot
    $selfPath = $MyInvocation.MyCommand.Path
    $resolvedInstallRoot = Resolve-LfoInstallRoot -RequestedRoot $InstallRoot -ScriptRoot $scriptRoot
    $state = Get-LfoInstallState $resolvedInstallRoot

    if (-not [string]::IsNullOrWhiteSpace($Experiment)) {
        $result = Invoke-LfoExperiment -ExperimentPath $Experiment -DeviceOverride $Device `
            -InstallRoot $resolvedInstallRoot -PackageRoot $scriptRoot -SelfPath $selfPath -Resume:$Resume
        if ($null -ne $result) {
            Write-Host ("Results directory: {0}" -f $result.RunDirectory) -ForegroundColor DarkGray
        }
        exit 0
    }

    if ($Resume) { throw '-Resume is valid only with -Experiment.' }

    $requestedDevice = if ([string]::IsNullOrWhiteSpace($Device)) { 'Auto' } else { $Device }
    $resolvedDevice = Resolve-LfoDevice $requestedDevice $state 6144
    $modelSpec = Get-LfoModelSpec $state $resolvedDevice
    $config = [string]$state.LFO.ConfigPath
    if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { throw "LFO config not found: $config" }
    $runtimePriority = if (-not [string]::IsNullOrWhiteSpace($Priority)) {
        $Priority
    } elseif ($state.LFO -and [string]$state.LFO.DefaultPriority -in @('Normal','High','Realtime')) {
        [string]$state.LFO.DefaultPriority
    } else {
        'High'
    }

    $logs = Join-Path $resolvedInstallRoot ('runtime\logs\lfo963-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    $ownedOllama = $null
    $ownedSurreal = $null
    $qwenAdapter = $null
    try {
        $ollamaUri = [string]$state.Ollama.BaseUri
        if ([string]::IsNullOrWhiteSpace($ollamaUri)) { throw 'Ollama BaseUri is missing from install-state.json.' }
        if (-not (Test-LfoOllamaReady $ollamaUri)) {
            $ownedOllama = Start-LfoOwnedOllama -State $state -BaseUri $ollamaUri -Priority $runtimePriority -LogDirectory $logs
        }
        Assert-LfoOllamaModelAvailable -BaseUri $ollamaUri -Model ([string]$modelSpec.Model)
        $runtimePriorityRows = @(Set-LfoConfiguredOllamaPriority -State $state -Priority $runtimePriority)
        if ($runtimePriorityRows.Count -gt 0) {
            foreach ($row in $runtimePriorityRows) {
                Write-Host ("Priority verified: PID {0} {1} = {2}" -f $row.pid,$row.name,$row.priority) -ForegroundColor DarkGray
            }
        } elseif ($null -eq $ownedOllama) {
            Write-Warning "Ollama is already running, but its configured process tree could not be identified for priority verification."
        }

        $surrealUri = [string]$state.SurrealDB.BaseUri
        if ([string]::IsNullOrWhiteSpace($surrealUri)) { throw 'SurrealDB BaseUri is missing from install-state.json.' }
        if (-not (Test-LfoSurrealReady $surrealUri)) {
            $surrealPort = ([uri]$surrealUri).Port
            $ownedSurreal = Start-LfoOwnedSurreal -State $state -Port $surrealPort -Priority Normal -LogDirectory $logs
            $surrealUri = $ownedSurreal.BaseUri
        }

        $qwenSource = Join-Path ([string]$state.AppRoot) 'src\QwenChat.ps1'
        $qwenAdapter = Join-Path (Split-Path -Parent $qwenSource) ('QwenChat.lfo963.' + [guid]::NewGuid().ToString('N') + '.ps1')
        [void](New-LfoQwen963Adapter $qwenSource $qwenAdapter)

        $env:LFO_INSTALL_ROOT = $resolvedInstallRoot
        $env:LFO_L4_ENABLED = '1'
        $env:LFO_L4_ENDPOINT = $surrealUri
        $env:LFO_L4_RUNTIME_CREDENTIAL = [string]$state.SurrealDB.RuntimeCredentialPath
        $env:LFO_L4_OBSERVABILITY = '1'

        Write-Host ''
        Write-Host 'Local Frontier Orchestrator (LFO) 9.6.3' -ForegroundColor Cyan
        Write-Host 'Runtime contract: v9.6.3 | controlled Windows runtime and unattended experiments.'
        Write-Host ("Install root: {0}" -f $resolvedInstallRoot)
        Write-Host ("Device:      {0} (requested: {1})" -f $resolvedDevice,$requestedDevice)
        Write-Host ("Model:       {0}" -f [string]$modelSpec.Model)
        Write-Host ("Priority:    {0} (default: High)" -f $runtimePriority)
        Write-Host 'L4:          ON'
        Write-Host ("Logs:        {0}" -f $logs)
        Write-Host ''

        $args = @(
            '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$qwenAdapter,
            '-Model',[string]$modelSpec.Model,'-ConfigPath',$config,
            '-ContextLengthHint',[string]$modelSpec.Context,'-BaseUriOverride',$ollamaUri
        )
        $argLine = (@($args | ForEach-Object { Quote-LfoArgument ([string]$_) }) -join ' ')
        $chat = Start-Process powershell.exe -ArgumentList $argLine -NoNewWindow -PassThru
        [void](Set-LfoProcessPriority -ProcessId $chat.Id -Priority $runtimePriority)
        $chat.WaitForExit()
        try { $chat.Refresh() } catch {}
        if ($chat.ExitCode -ne 0) { throw "QwenChat exited with code $($chat.ExitCode)." }
    } finally {
        if ($qwenAdapter) { Remove-Item -LiteralPath $qwenAdapter -Force -ErrorAction SilentlyContinue }
        if ($null -ne $ownedOllama) { Stop-LfoOwnedProcessTree $ownedOllama }
        if ($null -ne $ownedSurreal) { Stop-LfoOwnedProcessTree $ownedSurreal.Process }
    }
    exit 0
} catch {
    Write-Host ''
    Write-Host 'LFO 9.6.3 FAILED' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($VerbosePreference -ne 'SilentlyContinue' -and $_.ScriptStackTrace) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    exit 1
}