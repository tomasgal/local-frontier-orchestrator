param(
    [string]$Model,
    [switch]$Think,
    [Nullable[int]]$CodexTimeoutSec,
    [string]$ConfigPath,
    [Nullable[int]]$ContextLengthHint,
    [Nullable[int]]$MemoryRecentTurns,
    [Nullable[int]]$MemoryContextMaxChars,
    [Nullable[int]]$MemoryRecentContextMaxChars
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\QwenChat.config.psd1'
}
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "QwenChat config not found: $ConfigPath"
}

$script:Config = Import-PowerShellDataFile -LiteralPath $ConfigPath

if ([string]::IsNullOrWhiteSpace($Model)) {
    $Model = [string]$script:Config.Model
}
if ([string]::IsNullOrWhiteSpace($Model)) {
    throw 'No Ollama model is configured. Set Model in config or pass -Model.'
}

if ($null -eq $CodexTimeoutSec) {
    $CodexTimeoutSec = [int]$script:Config.CodexTimeoutSec
}
if ($CodexTimeoutSec -le 0) {
    throw 'CodexTimeoutSec must be greater than zero.'
}

$BaseUri = [string]$script:Config.BaseUri
if ([string]::IsNullOrWhiteSpace($BaseUri)) {
    throw 'BaseUri is missing from QwenChat config.'
}

$PolicyDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'policy'

function Read-PolicyTemplate([string]$FileName) {
    $path = Join-Path $PolicyDir $FileName
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Policy file not found: $path"
    }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8).TrimEnd()
}

$script:OrchestratorSystemTemplate = Read-PolicyTemplate 'orchestrator-system.txt'
$script:SynthesisSystemTemplate    = Read-PolicyTemplate 'synthesis-system.txt'
$script:FrontierSubagentTemplate   = Read-PolicyTemplate 'frontier-subagent.txt'
$script:MemoryNoteTemplate          = Read-PolicyTemplate 'memory-note-system.txt'
$script:MemoryCompactionTemplate    = Read-PolicyTemplate 'memory-compaction-system.txt'

$ThinkEnabled = [bool]$Think

$script:MemoryEnabled = [bool]$script:Config.Memory.Enabled
$script:MemoryRecentTurns = if ($null -ne $MemoryRecentTurns) { [int]$MemoryRecentTurns } else { [int]$script:Config.Memory.RecentTurns }
$script:MemoryContextMaxChars = if ($null -ne $MemoryContextMaxChars) { [int]$MemoryContextMaxChars } else { [int]$script:Config.Memory.ContextMaxChars }
$script:MemoryRecentContextMaxChars = if ($null -ne $MemoryRecentContextMaxChars) { [int]$MemoryRecentContextMaxChars } else { [int]$script:Config.Memory.RecentContextMaxChars }
$script:MemoryCompactionEvery = [int]$script:Config.Memory.CompactionEvery
$script:ContextLengthHint = if ($null -ne $ContextLengthHint) { [int]$ContextLengthHint } else { 0 }

$dataTemplate = [string]$script:Config.Memory.DataDirectory
if ([string]::IsNullOrWhiteSpace($dataTemplate)) { $dataTemplate = '%LOCALAPPDATA%\\LocalFrontierOrchestrator' }
$script:DataRoot = [Environment]::ExpandEnvironmentVariables($dataTemplate)
$script:StateDir = Join-Path $script:DataRoot 'state'
$script:LogDir = Join-Path $script:DataRoot 'logs'
$script:WorkingMemoryPath = Join-Path $script:StateDir 'working_memory.json'
$script:PendingNotesPath = Join-Path $script:StateDir 'pending_notes.jsonl'
$script:RuntimeStatePath = Join-Path $script:StateDir 'runtime_state.json'
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Expand-RuntimePolicy([string]$Template) {
    $currentLocalDate = (Get-Date).ToString('yyyy-MM-dd')
    return $Template.Replace('{{CURRENT_DATE}}', $currentLocalDate)
}

function Get-OrchestratorSystemPrompt {
    return Expand-RuntimePolicy $script:OrchestratorSystemTemplate
}

function Reset-Messages {
    $script:Messages = @(
        @{ role = 'system'; content = (Get-OrchestratorSystemPrompt) }
    )
}

function Refresh-SystemPrompt {
    if ($script:Messages.Count -eq 0 -or $script:Messages[0].role -ne 'system') {
        Reset-Messages
        return
    }
    $script:Messages[0].content = Get-OrchestratorSystemPrompt
}

Reset-Messages

function Write-TextUtf8NoBom([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, $script:Utf8NoBom)
}

function Write-JsonAtomic([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 16
    $tmp = "$Path.tmp"
    Write-TextUtf8NoBom $tmp $json
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Append-JsonLine([string]$Path, $Object) {
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $json = $Object | ConvertTo-Json -Depth 16 -Compress
    [System.IO.File]::AppendAllText($Path, $json + [Environment]::NewLine, $script:Utf8NoBom)
}

function Get-MonthlyLogPath([string]$Kind) {
    $month = (Get-Date).ToString('yyyy-MM')
    return (Join-Path $script:LogDir ("{0}-{1}.jsonl" -f $Kind, $month))
}

function New-DefaultWorkingMemory {
    return [ordered]@{
        version = 1
        current_focus = ''
        topics = @()
        context_items = @()
        decisions = @()
        open_loops = @()
        preferences = @()
        updated_at = $null
    }
}

function New-DefaultRuntimeState {
    return [ordered]@{
        version = 1
        epoch = 1
        next_turn_id = 1
        completed_since_compaction = 0
    }
}

function Get-WorkingMemoryRaw {
    if (-not (Test-Path -LiteralPath $script:WorkingMemoryPath)) {
        return ((New-DefaultWorkingMemory) | ConvertTo-Json -Depth 12 -Compress)
    }
    return (Get-Content -LiteralPath $script:WorkingMemoryPath -Raw -Encoding UTF8).Trim()
}

function Get-PendingNoteRecords {
    if (-not (Test-Path -LiteralPath $script:PendingNotesPath)) { return @() }
    $result = @()
    foreach ($line in (Get-Content -LiteralPath $script:PendingNotesPath -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $result += ($line | ConvertFrom-Json)
        } catch {
        }
    }
    return @($result)
}

function Clear-PendingNotes {
    Write-TextUtf8NoBom $script:PendingNotesPath ''
}

function Get-MemoryContextBlock {
    if (-not $script:MemoryEnabled) { return '' }

    $working = Get-WorkingMemoryRaw
    $pending = @(Get-PendingNoteRecords)
    $pendingJson = if ($pending.Count -gt 0) {
        ($pending | ConvertTo-Json -Depth 12 -Compress)
    } else {
        '[]'
    }

    $maxChars = [Math]::Max(1200, $script:MemoryContextMaxChars)
    $header1 = "WORKING MEMORY (compacted, persistent):`n"
    $header2 = "`nPENDING MEMORY NOTES (newer than the compacted memory):`n"
    $block = $header1 + $working + $header2 + $pendingJson

    if ($block.Length -le $maxChars) { return $block }

    $workingBudget = [Math]::Max(600, [int]($maxChars * 0.55))
    $pendingBudget = [Math]::Max(400, $maxChars - $workingBudget - $header1.Length - $header2.Length - 40)

    $workingPart = if ($working.Length -gt $workingBudget) {
        $working.Substring(0, $workingBudget) + ' ...[memory truncated]'
    } else {
        $working
    }

    $pendingPart = if ($pendingJson.Length -gt $pendingBudget) {
        '...[older notes truncated] ' + $pendingJson.Substring($pendingJson.Length - $pendingBudget)
    } else {
        $pendingJson
    }

    return ($header1 + $workingPart + $header2 + $pendingPart)
}

function Get-RecentConversationMessages {
    $nonSystem = @($script:Messages | Where-Object { $_.role -ne 'system' })
    if ($nonSystem.Count -eq 0) { return @() }

    $maxItems = [Math]::Max(1, ($script:MemoryRecentTurns * 2) + 1)
    $items = @($nonSystem | Select-Object -Last $maxItems)
    $maxChars = [Math]::Max(1000, $script:MemoryRecentContextMaxChars)

    $selected = @()
    $used = 0
    for ($i = $items.Count - 1; $i -ge 0; $i--) {
        $content = [string]$items[$i].content
        $cost = $content.Length + 32
        if ($selected.Count -gt 0 -and ($used + $cost) -gt $maxChars) { break }
        $selected = @($items[$i]) + $selected
        $used += $cost
    }
    return @($selected)
}

function Get-QwenConversationMessages {
    $systemText = Get-OrchestratorSystemPrompt
    $memoryBlock = Get-MemoryContextBlock
    if (-not [string]::IsNullOrWhiteSpace($memoryBlock)) {
        $systemText += @"

PERSISTENT CONVERSATION MEMORY:
$memoryBlock

Use this memory to resolve references and preserve continuity. It is context, not proof:
frequency or repetition increases conversational relevance, never factual certainty.
"@
    }

    $out = @(
        @{ role = 'system'; content = $systemText }
    )
    $out += @(Get-RecentConversationMessages)
    return @($out)
}

function Get-RecentConversationText([switch]$ExcludeLastUser) {
    $items = @(Get-RecentConversationMessages)
    if ($ExcludeLastUser -and $items.Count -gt 0 -and [string]$items[-1].role -eq 'user') {
        if ($items.Count -eq 1) {
            $items = @()
        } else {
            $items = @($items[0..($items.Count - 2)])
        }
    }
    if ($items.Count -eq 0) { return '(none)' }

    $lines = @()
    foreach ($m in $items) {
        $role = ([string]$m.role).ToUpperInvariant()
        $lines += ("{0}: {1}" -f $role, [string]$m.content)
    }
    return ($lines -join "`n`n")
}

function Get-JsonObjectFromModelText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw 'Memory model returned empty content.'
    }
    $clean = $Text.Trim()
    $clean = [regex]::Replace($clean, '(?is)^\s*```(?:json)?\s*', '')
    $clean = [regex]::Replace($clean, '(?is)\s*```\s*
    try {
        $v = Invoke-RestMethod -Uri "$BaseUri/api/version" -Method Get -TimeoutSec 3
        Write-Host ("Ollama {0}; model {1}" -f $v.version, $Model)
    } catch {
        Write-Host "Ollama is not responding at $BaseUri." -ForegroundColor Red
        Write-Host "Start Ollama in another console first (for example: .\launch\Start-Ollama.ps1)."
        exit 1
    }
}

function Trim-Messages {
    $maxMessages = [int]$script:Config.HistoryMaxMessages
    if ($maxMessages -lt 2) { $maxMessages = 12 }

    if ($script:Messages.Count -gt $maxMessages) {
        $system = @($script:Messages | Where-Object { $_.role -eq 'system' } | Select-Object -First 1)
        $tailCount = $maxMessages - 1
        $tail = @($script:Messages | Where-Object { $_.role -ne 'system' } | Select-Object -Last $tailCount)
        $script:Messages = @($system + $tail)
    }
}


function Get-FrontierPolicyReason([string]$Prompt) {
    if ([string]::IsNullOrWhiteSpace($Prompt)) { return $null }

    $gates = $script:Config.HardGates

    if ($Prompt -match [string]$gates.ProductSpecPattern -and
        $Prompt -match [string]$gates.ProductIdentityPattern) {
        return 'named-product-specification'
    }

    foreach ($rule in @($gates.Rules)) {
        if ($Prompt -match [string]$rule.Pattern) {
            return [string]$rule.Reason
        }
    }
    return $null
}

function Get-HardGateContext([string]$Prompt) {
    $gates = $script:Config.HardGates
    $maxPromptChars = [int]$gates.FollowUpMaxPromptChars
    $maxContextChars = [int]$gates.FollowUpContextChars
    $followUpPattern = [string]$gates.FollowUpPattern

    if ([string]::IsNullOrWhiteSpace($Prompt) -or $Prompt.Length -gt $maxPromptChars) {
        return ''
    }

    if ($Prompt -notmatch $followUpPattern) {
        return ''
    }

    $lastUser = @(
        $script:Messages |
            Where-Object { $_.role -eq 'user' } |
            Select-Object -Last 1
    )
    if ($lastUser.Count -eq 0) { return '' }

    $text = [string]$lastUser[0].content
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    if ($text.Length -gt $maxContextChars) {
        $text = $text.Substring($text.Length - $maxContextChars)
    }
    return $text.Trim()
}

function Get-CodexProcessSpec {
    $cmd = Get-Command codex.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) {
        $cmd = Get-Command codex -ErrorAction Stop | Select-Object -First 1
    }
    $path = [string]$cmd.Source
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = [string]$cmd.Path
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw 'The codex command could not be located.'
    }

    # Send prompts over stdin; never interpolate them into a shell command line.
    $fixedArgs = '--ask-for-approval never --sandbox read-only --search exec --json --ephemeral --ignore-user-config --skip-git-repo-check --cd "{0}" -' -f $env:TEMP
    $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()

    switch ($ext) {
        '.cmd' {
            return @{
                FileName = $env:ComSpec
                Arguments = '/d /s /c ""{0}" {1}"' -f $path, $fixedArgs
            }
        }
        '.bat' {
            return @{
                FileName = $env:ComSpec
                Arguments = '/d /s /c ""{0}" {1}"' -f $path, $fixedArgs
            }
        }
        '.ps1' {
            return @{
                FileName = 'powershell.exe'
                Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $path, $fixedArgs
            }
        }
        default {
            return @{
                FileName = $path
                Arguments = $fixedArgs
            }
        }
    }
}

function Invoke-CodexReadOnly([string]$Prompt) {
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        throw 'ask_codex received an empty prompt.'
    }
    $maxFrontierPromptChars = [int]$script:Config.Frontier.MaxPromptChars
    if ($Prompt.Length -gt $maxFrontierPromptChars) {
        throw "ask_codex prompt is too long (maximum: $maxFrontierPromptChars characters)."
    }

    $spec = Get-CodexProcessSpec
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $spec.FileName
    $psi.Arguments = $spec.Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    # codex exec reads stdin as UTF-8. Windows PowerShell 5.1 can otherwise
    # encode redirected text using a legacy code page, corrupting Slovak text.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    if ($psi.PSObject.Properties.Name -contains 'StandardInputEncoding')  { $psi.StandardInputEncoding = $utf8NoBom }
    if ($psi.PSObject.Properties.Name -contains 'StandardOutputEncoding') { $psi.StandardOutputEncoding = $utf8NoBom }
    if ($psi.PSObject.Properties.Name -contains 'StandardErrorEncoding')  { $psi.StandardErrorEncoding = $utf8NoBom }

    # Use the existing authenticated ChatGPT/Codex session rather than an OpenAI API key.
    [void]$psi.EnvironmentVariables.Remove('OPENAI_API_KEY')
    [void]$psi.EnvironmentVariables.Remove('CODEX_API_KEY')
    [void]$psi.EnvironmentVariables.Remove('OPENAI_BASE_URL')

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    try {
        if (-not $p.Start()) {
            throw 'codex exec could not be started.'
        }

        $stdoutTask = $p.StandardOutput.ReadToEndAsync()
        $stderrTask = $p.StandardError.ReadToEndAsync()

        $delegatedPrompt = Expand-RuntimePolicy $script:FrontierSubagentTemplate
        $delegatedPrompt = $delegatedPrompt.Replace('{{TASK}}', $Prompt)
        # Write exact UTF-8 bytes; do not let Windows PowerShell choose an OEM/ANSI encoding.
        $stdinBytes = [System.Text.Encoding]::UTF8.GetBytes($delegatedPrompt)
        $p.StandardInput.BaseStream.Write($stdinBytes, 0, $stdinBytes.Length)
        $p.StandardInput.BaseStream.Flush()
        $p.StandardInput.Close()

        if (-not $p.WaitForExit($CodexTimeoutSec * 1000)) {
            try { & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null } catch { }
            throw "codex exec exceeded the ${CodexTimeoutSec}s timeout."
        }

        # Required to complete asynchronous stdout/stderr reads after WaitForExit(timeout).
        $p.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result

        if ($p.ExitCode -ne 0) {
            $detail = ([string]$stderr).Trim()
            if ($detail.Length -gt 2000) { $detail = $detail.Substring($detail.Length - 2000) }
            throw ("codex exec exited with code {0}. {1}" -f $p.ExitCode, $detail)
        }

        $finalText = $null
        foreach ($line in ($stdout -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $evt = $line | ConvertFrom-Json
            } catch {
                continue
            }
            if ($evt.type -eq 'item.completed' -and $evt.item.type -eq 'agent_message' -and $evt.item.text) {
                $finalText = [string]$evt.item.text
            }
            if ($evt.type -eq 'turn.failed') {
                $msg = [string]$evt.error.message
                if (-not [string]::IsNullOrWhiteSpace($msg)) {
                    throw "codex exec turn failed: $msg"
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($finalText)) {
            throw 'codex exec did not return a final agent_message.'
        }
        return $finalText.Trim()
    } finally {
        if ($null -ne $p) { $p.Dispose() }
    }
}

function Invoke-QwenLocalApi {
    $bodyObj = @{
        model      = $Model
        messages   = @(Get-QwenConversationMessages)
        think      = $script:ThinkEnabled
        stream     = $false
        keep_alive = '5m'
        # Hardware/runtime placement (GPU/CPU, context length, threads) belongs
        # to the selected Ollama model profile. Keep only per-request generation
        # controls here so QwenChat does not override host-specific profiles.
        options    = @{
            num_predict = $(if ($script:ThinkEnabled) {
                [int]$script:Config.LocalGeneration.NumPredictThink
            } else {
                [int]$script:Config.LocalGeneration.NumPredictNormal
            })
            temperature = [double]$script:Config.LocalGeneration.Temperature
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 12 -Compress
    return Invoke-RestMethod -Uri "$BaseUri/api/chat" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
}

function Invoke-QwenSynthesis([string]$OriginalPrompt, [string]$FrontierResult) {
    $synthesisSystem = Expand-RuntimePolicy $script:SynthesisSystemTemplate
    $memoryBlock = Get-MemoryContextBlock
    $recentConversation = Get-RecentConversationText -ExcludeLastUser

    $synthesisUser = @"
PERSISTENT CONVERSATION MEMORY:
$memoryBlock

RECENT CONVERSATION:
$recentConversation

ORIGINAL USER REQUEST:
$OriginalPrompt

FRONTIER RESULT:
$FrontierResult
"@

    $bodyObj = @{
        model      = $Model
        messages   = @(
            @{ role = 'system'; content = $synthesisSystem },
            @{ role = 'user'; content = $synthesisUser }
        )
        think      = $script:ThinkEnabled
        stream     = $false
        keep_alive = '5m'
        options    = @{
            num_predict = $(if ($script:ThinkEnabled) {
                [int]$script:Config.SynthesisGeneration.NumPredictThink
            } else {
                [int]$script:Config.SynthesisGeneration.NumPredictNormal
            })
            temperature      = [double]$script:Config.SynthesisGeneration.Temperature
            presence_penalty = [double]$script:Config.SynthesisGeneration.PresencePenalty
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 12 -Compress
    return Invoke-RestMethod -Uri "$BaseUri/api/chat" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
}

function Show-QwenThinking($Response) {
    $thinking = [string]$Response.message.thinking
    if ($script:ThinkEnabled -and $thinking) {
        Write-Host "`n--- thinking ---" -ForegroundColor DarkGray
        Write-Host $thinking -ForegroundColor DarkGray
        Write-Host "--- answer ---" -ForegroundColor DarkGray
    }
}

function Get-CleanQwenContent($Response) {
    $content = [string]$Response.message.content
    if ([string]::IsNullOrWhiteSpace($content)) { return '' }

    if (-not $script:ThinkEnabled) {
        if ($content -match '(?is)<think>.*?</think>') {
            Write-Host "`n[Qwen reasoning leaked into content; the wrapper hid it.]" -ForegroundColor DarkGray
            $content = [regex]::Replace($content, '(?is)<think>.*?</think>\s*', '')
        } elseif ($content -match '(?is)</think>') {
            # Compatibility guard: some Qwen/Ollama combinations expose the
            # closing tag while the opening thinking tag is consumed by the
            # chat template/parser. Preserve a leading ROUTE marker if present.
            $leadingRoute = $null
            if ($content -match '(?im)^\s*(ROUTE:\s*(?:LOCAL|FRONTIER))\s*$') {
                $leadingRoute = $Matches[1].ToUpperInvariant()
            }
            Write-Host "`n[Qwen reasoning leaked into content; the wrapper hid it after </think>.]" -ForegroundColor DarkGray
            $content = [regex]::Replace($content, '(?is)^.*?</think>\s*', '')
            if ($leadingRoute -and $content -notmatch '(?im)^\s*ROUTE:\s*(?:LOCAL|FRONTIER)\s*$') {
                $content = "$leadingRoute`n$content"
            }
        }
    }

    return $content.Trim()
}

function Get-QwenRoute([string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return 'UNKNOWN' }
    if ($Content -match '(?im)^\s*ROUTE:\s*FRONTIER\s*$') { return 'FRONTIER' }
    if ($Content -match '(?im)^\s*ROUTE:\s*LOCAL\s*$') { return 'LOCAL' }
    return 'UNKNOWN'
}

function Remove-QwenRouteMarker([string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return '' }
    $clean = [regex]::Replace($Content, '(?im)^\s*ROUTE:\s*LOCAL\s*\r?\n?', '', 1)
    $clean = [regex]::Replace($clean, '(?im)^\s*ROUTE:\s*FRONTIER\s*\r?\n?', '', 1)
    return $clean.Trim()
}

function Test-UnfinishedSynthesis($Response, [string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return $true }

    # Ollama reports done_reason=length when generation reaches num_predict.
    # Never show a token-cap-truncated synthesis as a complete answer; the
    # caller will fall back to the already complete frontier result instead.
    if ([string]$Response.done_reason -eq 'length') { return $true }

    $unfinishedThreshold = [int]$script:Config.SynthesisGeneration.UnfinishedEvalThreshold
    if ($Response.eval_count -ge $unfinishedThreshold -and
        $Content -match '(?is)^\s*(okay,?\s+let me|let me|first,?\s+i\s+need|we\s+need|i\s+need\s+to|let''s\s+(?:tackle|work|analyze))') {
        return $true
    }
    return $false
}

function Invoke-Qwen([string]$Prompt) {
    Refresh-SystemPrompt

    # Capture context before appending the current user turn.
    $recentContext = Get-HardGateContext $Prompt

    $script:Messages += @{ role = 'user'; content = $Prompt }
    Trim-Messages

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $policyReason = Get-FrontierPolicyReason $Prompt
    $route = $null
    $r = $null
    $frontierResult = $null
    $finalContent = $null
    $localRaw = $null

    if (-not [string]::IsNullOrWhiteSpace($policyReason)) {
        $route = 'FRONTIER'
        Write-Host ("`n[policy -> FRONTIER; reason={0}]" -f $policyReason) -ForegroundColor DarkCyan
    } else {
        # No Ollama tool schema is exposed here. Qwen decides with a plain-text
        # route marker and, on LOCAL, the same generation is already the answer.
        $r = Invoke-QwenLocalApi
        Show-QwenThinking $r
        $candidate = Get-CleanQwenContent $r
        $localRaw = $candidate
        $route = Get-QwenRoute $candidate

        if ($route -eq 'FRONTIER') {
            Write-Host "`n[Qwen route -> FRONTIER]" -ForegroundColor DarkCyan
        } elseif ($route -eq 'LOCAL') {
            Write-Host "`n[Qwen route -> LOCAL]" -ForegroundColor DarkGray
            $finalContent = Remove-QwenRouteMarker $candidate
        } else {
            # Fail closed on cost/escalation: malformed routing never triggers
            # frontier automatically. Treat the generation as a local answer.
            Write-Host "`n[Qwen route marker missing; fail-closed -> LOCAL]" -ForegroundColor Yellow
            $route = 'LOCAL'
            $finalContent = Remove-QwenRouteMarker $candidate
        }
    }

    if ($route -eq 'FRONTIER') {
        $memoryBlock = Get-MemoryContextBlock
        $recentConversation = Get-RecentConversationText -ExcludeLastUser

        $codexPrompt = @"
PERSISTENT CONVERSATION MEMORY:
$memoryBlock

RECENT CONVERSATION:
$recentConversation

CURRENT USER REQUEST:
$Prompt
"@

        if (-not [string]::IsNullOrWhiteSpace($recentContext)) {
            $codexPrompt += @"

FOLLOW-UP ANCHOR (previous user turn):
$recentContext
"@
        }

        Write-Host ("[ask_codex; {0} characters]" -f $codexPrompt.Length) -ForegroundColor DarkCyan
        try {
            $frontierResult = Invoke-CodexReadOnly $codexPrompt
            Write-Host ("[ask_codex -> Qwen; {0} characters]" -f $frontierResult.Length) -ForegroundColor DarkCyan
        } catch {
            $frontierResult = "ask_codex failed: $($_.Exception.Message)"
            Write-Host "[$frontierResult]" -ForegroundColor Yellow
        }

        if ($frontierResult -like 'ask_codex failed:*') {
            $finalContent = $frontierResult
        } else {
            $r = Invoke-QwenSynthesis $Prompt $frontierResult
            Show-QwenThinking $r
            $candidate = Get-CleanQwenContent $r

            if (Test-UnfinishedSynthesis $r $candidate) {
                Write-Host "`n[Qwen synthesis did not complete; showing the frontier result directly.]" -ForegroundColor Yellow
                $finalContent = $frontierResult
            } else {
                $finalContent = $candidate
            }
        }
    }

    $sw.Stop()

    if ([string]::IsNullOrWhiteSpace($finalContent)) {
        Write-Host "`n[The model did not produce final content within the token limit.]" -ForegroundColor Yellow
    } else {
        Write-Host "`n$finalContent"
        # Keep the routing protocol visible in internal conversation history.
        # The marker is hidden from the user-facing output above, but storing it
        # prevents previous assistant turns from becoming counterexamples to the
        # system instruction that every normal turn must start with ROUTE: ...
        $historyContent = "ROUTE: $route`n$finalContent"
        $script:Messages += @{ role = 'assistant'; content = $historyContent }
        Trim-Messages
    }

    if ($null -ne $r) {
        $tokps = $null
        if ($r.eval_duration -gt 0 -and $r.eval_count) {
            $tokps = [Math]::Round(($r.eval_count * 1e9) / $r.eval_duration, 2)
        }

        Write-Host ("`n[{0:n2}s; prompt {1} tok; generated {2} tok; {3} tok/s; think={4}; route={5}]" -f `
            $sw.Elapsed.TotalSeconds, $r.prompt_eval_count, $r.eval_count, $tokps, $script:ThinkEnabled, $route) `
            -ForegroundColor DarkGray
    } else {
        Write-Host ("`n[{0:n2}s; think={1}; route={2}]" -f `
            $sw.Elapsed.TotalSeconds, $script:ThinkEnabled, $route) -ForegroundColor DarkGray
    }
}


Initialize-PersistentMemory
$script:PolicyFingerprint = Get-PolicyFingerprint

Test-Ollama
Write-Host ""
Write-Host "Qwen local chat v8 (external policy/config). Commands: /exit, /clear, /paste, /think on, /think off"
Write-Host "Frontier action: ask_codex (read-only, max 1 call per user turn)"
Write-Host "Routing: hard freshness/web gate + Qwen ROUTE: LOCAL/FRONTIER (no Ollama tools)"
Write-Host ("Thinking is now: {0} (controlled by the Ollama API think parameter)" -f $ThinkEnabled)
if ($script:MemoryEnabled) {
    Write-Host ("Persistent memory: ON; recent turns={0}; compact every={1}; data={2}" -f $script:MemoryRecentTurns, $script:MemoryCompactionEvery, $script:DataRoot)
}
Write-Host ""

while ($true) {
    $prompt = Read-Host "Qwen>"
    if ($null -eq $prompt) { continue }

    switch -Regex ($prompt.Trim()) {
        '^/exit$' {
            exit 0
        }
        '^/clear
        '^/paste$' {
            $clip = Get-Clipboard -Raw
            if ([string]::IsNullOrWhiteSpace($clip)) {
                Write-Host "Clipboard is empty." -ForegroundColor Yellow
                continue
            }
            Write-Host ("[Sending clipboard: {0} characters]" -f $clip.Length) -ForegroundColor DarkGray
            Invoke-Qwen $clip
            continue
        }
        '^/think\s+on$' {
            $ThinkEnabled = $true
            Write-Host "Thinking enabled."
            continue
        }
        '^/think\s+off$' {
            $ThinkEnabled = $false
            Write-Host "Thinking disabled."
            continue
        }
        '^\s*$' {
            continue
        }
        default {
            Invoke-Qwen $prompt
        }
    }
}, '')
    $start = $clean.IndexOf('{')
    $end = $clean.LastIndexOf('}')
    if ($start -ge 0 -and $end -gt $start) {
        $clean = $clean.Substring($start, $end - $start + 1)
    }
    return ($clean | ConvertFrom-Json)
}

function Invoke-QwenMemoryCall([string]$SystemPrompt, [string]$UserPrompt, [int]$NumPredict) {
    $bodyObj = @{
        model = $Model
        messages = @(
            @{ role = 'system'; content = $SystemPrompt },
            @{ role = 'user'; content = $UserPrompt }
        )
        think = $false
        stream = $false
        keep_alive = '5m'
        options = @{
            num_predict = $NumPredict
            temperature = [double]$script:Config.Memory.Temperature
        }
    }
    $body = $bodyObj | ConvertTo-Json -Depth 14 -Compress
    return Invoke-RestMethod -Uri "$BaseUri/api/chat" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
}

function Invoke-QwenMemoryNote(
    [int]$TurnId,
    [string]$Prompt,
    [string]$FinalContent,
    [string]$Route,
    [string]$FrontierResult
) {
    $memory = Get-MemoryContextBlock
    $frontierForNote = [string]$FrontierResult
    $frontierLimit = [int]$script:Config.Memory.FrontierForNoteMaxChars
    if (-not [string]::IsNullOrWhiteSpace($frontierForNote) -and $frontierForNote.Length -gt $frontierLimit) {
        $frontierForNote = $frontierForNote.Substring(0, $frontierLimit) + ' ...[truncated]'
    }
    if ([string]::IsNullOrWhiteSpace($frontierForNote)) { $frontierForNote = '(none)' }

    $userText = @"
TURN ID: $TurnId
ROUTE: $Route

CURRENT MEMORY:
$memory

USER:
$Prompt

FINAL ASSISTANT ANSWER:
$FinalContent

FRONTIER RESULT IF USED:
$frontierForNote
"@

    $r = Invoke-QwenMemoryCall `
        (Expand-RuntimePolicy $script:MemoryNoteTemplate) `
        $userText `
        ([int]$script:Config.Memory.NoteNumPredict)

    $raw = [string]$r.message.content
    $parsed = Get-JsonObjectFromModelText $raw
    return [pscustomobject]@{
        Raw = $raw
        Parsed = $parsed
        EvalCount = $r.eval_count
        EvalDuration = $r.eval_duration
    }
}

function Invoke-MemoryCompaction {
    $pending = @(Get-PendingNoteRecords)
    if ($pending.Count -eq 0) { return $false }

    $working = Get-WorkingMemoryRaw
    $pendingJson = $pending | ConvertTo-Json -Depth 14

    $userText = @"
EXISTING WORKING MEMORY:
$working

NEW MEMORY NOTES:
$pendingJson
"@

    $r = Invoke-QwenMemoryCall `
        (Expand-RuntimePolicy $script:MemoryCompactionTemplate) `
        $userText `
        ([int]$script:Config.Memory.CompactionNumPredict)

    $raw = [string]$r.message.content
    $parsed = Get-JsonObjectFromModelText $raw

    if ($parsed.PSObject.Properties.Name -notcontains 'updated_at') {
        $parsed | Add-Member -NotePropertyName updated_at -NotePropertyValue ((Get-Date).ToString('o'))
    } else {
        $parsed.updated_at = (Get-Date).ToString('o')
    }

    Write-JsonAtomic $script:WorkingMemoryPath $parsed
    Clear-PendingNotes
    return $true
}

function Get-PolicyFingerprint {
    $parts = @()
    foreach ($name in @(
        'orchestrator-system.txt',
        'synthesis-system.txt',
        'frontier-subagent.txt',
        'memory-note-system.txt',
        'memory-compaction-system.txt'
    )) {
        $path = Join-Path $PolicyDir $name
        if (Test-Path -LiteralPath $path) {
            $h = Get-FileHash -LiteralPath $path -Algorithm SHA256
            $parts += ("{0}:{1}" -f $name, $h.Hash)
        }
    }
    return ($parts -join ';')
}

function Load-RecentConversationFromDisk {
    if (-not $script:MemoryEnabled) { return }
    $turns = @()
    $files = @(Get-ChildItem -LiteralPath $script:LogDir -Filter 'conversation-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($f in $files) {
        foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
            } catch {
                continue
            }
            if ([string]$row.event -eq 'turn' -and [int]$row.epoch -eq [int]$script:RuntimeState.epoch) {
                $turns += $row
            }
        }
    }

    $turns = @($turns | Select-Object -Last $script:MemoryRecentTurns)
    foreach ($t in $turns) {
        $script:Messages += @{ role = 'user'; content = [string]$t.user }
        $assistantStored = "ROUTE: $([string]$t.route)`n$([string]$t.assistant)"
        $script:Messages += @{ role = 'assistant'; content = $assistantStored }
    }
    Trim-Messages
}

function Initialize-PersistentMemory {
    if (-not $script:MemoryEnabled) { return }

    New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null

    if (-not (Test-Path -LiteralPath $script:WorkingMemoryPath)) {
        Write-JsonAtomic $script:WorkingMemoryPath (New-DefaultWorkingMemory)
    }
    if (-not (Test-Path -LiteralPath $script:PendingNotesPath)) {
        Clear-PendingNotes
    }
    if (-not (Test-Path -LiteralPath $script:RuntimeStatePath)) {
        Write-JsonAtomic $script:RuntimeStatePath (New-DefaultRuntimeState)
    }

    try {
        $script:RuntimeState = Get-Content -LiteralPath $script:RuntimeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $script:RuntimeState = [pscustomobject](New-DefaultRuntimeState)
        Write-JsonAtomic $script:RuntimeStatePath $script:RuntimeState
    }

    Load-RecentConversationFromDisk
}

function Save-RuntimeState {
    if ($script:MemoryEnabled) {
        Write-JsonAtomic $script:RuntimeStatePath $script:RuntimeState
    }
}

function Clear-PersistentConversationMemory {
    Reset-Messages
    if (-not $script:MemoryEnabled) { return }

    $script:RuntimeState.epoch = [int]$script:RuntimeState.epoch + 1
    $script:RuntimeState.completed_since_compaction = 0
    Write-JsonAtomic $script:WorkingMemoryPath (New-DefaultWorkingMemory)
    Clear-PendingNotes
    Save-RuntimeState

    if ([bool]$script:Config.ResearchLogging.Enabled) {
        Append-JsonLine (Get-MonthlyLogPath 'trace') ([ordered]@{
            event = 'clear'
            timestamp = (Get-Date).ToString('o')
            epoch = [int]$script:RuntimeState.epoch
            note = 'Working memory and active recent context cleared; historical logs retained.'
        })
    }
}

function Persist-TurnAndMemory(
    [string]$Prompt,
    [string]$FinalContent,
    [string]$Route,
    [string]$PolicyReason,
    [string]$LocalRaw,
    [string]$FrontierResult,
    $Response,
    [double]$AnswerSeconds
) {
    if (-not $script:MemoryEnabled -and -not [bool]$script:Config.ResearchLogging.Enabled) { return }

    if ($script:MemoryEnabled) {
        $turnId = [int]$script:RuntimeState.next_turn_id
        $epoch = [int]$script:RuntimeState.epoch
    } else {
        $turnId = 0
        $epoch = 0
    }

    $timestamp = (Get-Date).ToString('o')
    $memoryBefore = if ($script:MemoryEnabled) { Get-MemoryContextBlock } else { '' }

    if ($script:MemoryEnabled) {
        Append-JsonLine (Get-MonthlyLogPath 'conversation') ([ordered]@{
            event = 'turn'
            timestamp = $timestamp
            turn_id = $turnId
            epoch = $epoch
            route = $Route
            user = $Prompt
            assistant = $FinalContent
        })

        $script:RuntimeState.next_turn_id = $turnId + 1
        Save-RuntimeState
    }

    $memoryNote = $null
    $memoryError = $null
    $compacted = $false
    $memorySw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($script:MemoryEnabled) {
        try {
            $memoryNote = Invoke-QwenMemoryNote $turnId $Prompt $FinalContent $Route $FrontierResult
            Append-JsonLine $script:PendingNotesPath ([ordered]@{
                turn_id = $turnId
                timestamp = (Get-Date).ToString('o')
                note = $memoryNote.Parsed
            })

            $script:RuntimeState.completed_since_compaction = [int]$script:RuntimeState.completed_since_compaction + 1

            if ([int]$script:RuntimeState.completed_since_compaction -ge $script:MemoryCompactionEvery) {
                try {
                    $compacted = Invoke-MemoryCompaction
                    if ($compacted) {
                        $script:RuntimeState.completed_since_compaction = 0
                    }
                } catch {
                    $memoryError = "compaction failed: $($_.Exception.Message)"
                }
            }
            Save-RuntimeState
        } catch {
            $memoryError = "memory note failed: $($_.Exception.Message)"
        }
    }

    $memorySw.Stop()
    $memoryAfter = if ($script:MemoryEnabled) { Get-MemoryContextBlock } else { '' }

    if ([bool]$script:Config.ResearchLogging.Enabled) {
        $trace = [ordered]@{
            event = 'turn_trace'
            timestamp = $timestamp
            turn_id = $turnId
            epoch = $epoch
            model = $Model
            context_length_hint = $script:ContextLengthHint
            route = $Route
            route_reason = $PolicyReason
            answer_seconds = [Math]::Round($AnswerSeconds, 3)
            memory_seconds = [Math]::Round($memorySw.Elapsed.TotalSeconds, 3)
            memory_compacted = $compacted
            memory_error = $memoryError
            policy_fingerprint = $script:PolicyFingerprint
            performance = if ($null -ne $Response) {
                [ordered]@{
                    prompt_eval_count = $Response.prompt_eval_count
                    prompt_eval_duration = $Response.prompt_eval_duration
                    eval_count = $Response.eval_count
                    eval_duration = $Response.eval_duration
                    done_reason = [string]$Response.done_reason
                }
            } else {
                $null
            }
            bias_signals = if ($null -ne $memoryNote -and $null -ne $memoryNote.Parsed.bias_signals) {
                $memoryNote.Parsed.bias_signals
            } else {
                @()
            }
        }

        if ([bool]$script:Config.ResearchLogging.IncludeRawText) {
            $trace.user = $Prompt
            $trace.local_raw = $LocalRaw
            $trace.frontier_raw = $FrontierResult
            $trace.final_answer = $FinalContent
            $trace.memory_note_raw = if ($null -ne $memoryNote) { $memoryNote.Raw } else { $null }
        }
        if ([bool]$script:Config.ResearchLogging.IncludeMemorySnapshots) {
            $trace.memory_before = $memoryBefore
            $trace.memory_after = $memoryAfter
        }

        Append-JsonLine (Get-MonthlyLogPath 'trace') $trace
    }

    if ($script:MemoryEnabled) {
        $state = if ($compacted) { 'note saved + compacted' } elseif ($memoryError) { $memoryError } else { 'note saved' }
        Write-Host ("[memory: {0}; {1:n2}s]" -f $state, $memorySw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
    }
}

function Test-Ollama {
    try {
        $v = Invoke-RestMethod -Uri "$BaseUri/api/version" -Method Get -TimeoutSec 3
        Write-Host ("Ollama {0}; model {1}" -f $v.version, $Model)
    } catch {
        Write-Host "Ollama is not responding at $BaseUri." -ForegroundColor Red
        Write-Host "Start Ollama in another console first (for example: .\launch\Start-Ollama.ps1)."
        exit 1
    }
}

function Trim-Messages {
    $maxMessages = [int]$script:Config.HistoryMaxMessages
    if ($maxMessages -lt 2) { $maxMessages = 12 }

    if ($script:Messages.Count -gt $maxMessages) {
        $system = @($script:Messages | Where-Object { $_.role -eq 'system' } | Select-Object -First 1)
        $tailCount = $maxMessages - 1
        $tail = @($script:Messages | Where-Object { $_.role -ne 'system' } | Select-Object -Last $tailCount)
        $script:Messages = @($system + $tail)
    }
}


function Get-FrontierPolicyReason([string]$Prompt) {
    if ([string]::IsNullOrWhiteSpace($Prompt)) { return $null }

    $gates = $script:Config.HardGates

    if ($Prompt -match [string]$gates.ProductSpecPattern -and
        $Prompt -match [string]$gates.ProductIdentityPattern) {
        return 'named-product-specification'
    }

    foreach ($rule in @($gates.Rules)) {
        if ($Prompt -match [string]$rule.Pattern) {
            return [string]$rule.Reason
        }
    }
    return $null
}

function Get-HardGateContext([string]$Prompt) {
    $gates = $script:Config.HardGates
    $maxPromptChars = [int]$gates.FollowUpMaxPromptChars
    $maxContextChars = [int]$gates.FollowUpContextChars
    $followUpPattern = [string]$gates.FollowUpPattern

    if ([string]::IsNullOrWhiteSpace($Prompt) -or $Prompt.Length -gt $maxPromptChars) {
        return ''
    }

    if ($Prompt -notmatch $followUpPattern) {
        return ''
    }

    $lastUser = @(
        $script:Messages |
            Where-Object { $_.role -eq 'user' } |
            Select-Object -Last 1
    )
    if ($lastUser.Count -eq 0) { return '' }

    $text = [string]$lastUser[0].content
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    if ($text.Length -gt $maxContextChars) {
        $text = $text.Substring($text.Length - $maxContextChars)
    }
    return $text.Trim()
}

function Get-CodexProcessSpec {
    $cmd = Get-Command codex.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) {
        $cmd = Get-Command codex -ErrorAction Stop | Select-Object -First 1
    }
    $path = [string]$cmd.Source
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = [string]$cmd.Path
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw 'The codex command could not be located.'
    }

    # Send prompts over stdin; never interpolate them into a shell command line.
    $fixedArgs = '--ask-for-approval never --sandbox read-only --search exec --json --ephemeral --ignore-user-config --skip-git-repo-check --cd "{0}" -' -f $env:TEMP
    $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()

    switch ($ext) {
        '.cmd' {
            return @{
                FileName = $env:ComSpec
                Arguments = '/d /s /c ""{0}" {1}"' -f $path, $fixedArgs
            }
        }
        '.bat' {
            return @{
                FileName = $env:ComSpec
                Arguments = '/d /s /c ""{0}" {1}"' -f $path, $fixedArgs
            }
        }
        '.ps1' {
            return @{
                FileName = 'powershell.exe'
                Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $path, $fixedArgs
            }
        }
        default {
            return @{
                FileName = $path
                Arguments = $fixedArgs
            }
        }
    }
}

function Invoke-CodexReadOnly([string]$Prompt) {
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        throw 'ask_codex received an empty prompt.'
    }
    $maxFrontierPromptChars = [int]$script:Config.Frontier.MaxPromptChars
    if ($Prompt.Length -gt $maxFrontierPromptChars) {
        throw "ask_codex prompt is too long (maximum: $maxFrontierPromptChars characters)."
    }

    $spec = Get-CodexProcessSpec
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $spec.FileName
    $psi.Arguments = $spec.Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    # codex exec reads stdin as UTF-8. Windows PowerShell 5.1 can otherwise
    # encode redirected text using a legacy code page, corrupting Slovak text.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    if ($psi.PSObject.Properties.Name -contains 'StandardInputEncoding')  { $psi.StandardInputEncoding = $utf8NoBom }
    if ($psi.PSObject.Properties.Name -contains 'StandardOutputEncoding') { $psi.StandardOutputEncoding = $utf8NoBom }
    if ($psi.PSObject.Properties.Name -contains 'StandardErrorEncoding')  { $psi.StandardErrorEncoding = $utf8NoBom }

    # Use the existing authenticated ChatGPT/Codex session rather than an OpenAI API key.
    [void]$psi.EnvironmentVariables.Remove('OPENAI_API_KEY')
    [void]$psi.EnvironmentVariables.Remove('CODEX_API_KEY')
    [void]$psi.EnvironmentVariables.Remove('OPENAI_BASE_URL')

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    try {
        if (-not $p.Start()) {
            throw 'codex exec could not be started.'
        }

        $stdoutTask = $p.StandardOutput.ReadToEndAsync()
        $stderrTask = $p.StandardError.ReadToEndAsync()

        $delegatedPrompt = Expand-RuntimePolicy $script:FrontierSubagentTemplate
        $delegatedPrompt = $delegatedPrompt.Replace('{{TASK}}', $Prompt)
        # Write exact UTF-8 bytes; do not let Windows PowerShell choose an OEM/ANSI encoding.
        $stdinBytes = [System.Text.Encoding]::UTF8.GetBytes($delegatedPrompt)
        $p.StandardInput.BaseStream.Write($stdinBytes, 0, $stdinBytes.Length)
        $p.StandardInput.BaseStream.Flush()
        $p.StandardInput.Close()

        if (-not $p.WaitForExit($CodexTimeoutSec * 1000)) {
            try { & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null } catch { }
            throw "codex exec exceeded the ${CodexTimeoutSec}s timeout."
        }

        # Required to complete asynchronous stdout/stderr reads after WaitForExit(timeout).
        $p.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result

        if ($p.ExitCode -ne 0) {
            $detail = ([string]$stderr).Trim()
            if ($detail.Length -gt 2000) { $detail = $detail.Substring($detail.Length - 2000) }
            throw ("codex exec exited with code {0}. {1}" -f $p.ExitCode, $detail)
        }

        $finalText = $null
        foreach ($line in ($stdout -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $evt = $line | ConvertFrom-Json
            } catch {
                continue
            }
            if ($evt.type -eq 'item.completed' -and $evt.item.type -eq 'agent_message' -and $evt.item.text) {
                $finalText = [string]$evt.item.text
            }
            if ($evt.type -eq 'turn.failed') {
                $msg = [string]$evt.error.message
                if (-not [string]::IsNullOrWhiteSpace($msg)) {
                    throw "codex exec turn failed: $msg"
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($finalText)) {
            throw 'codex exec did not return a final agent_message.'
        }
        return $finalText.Trim()
    } finally {
        if ($null -ne $p) { $p.Dispose() }
    }
}

function Invoke-QwenLocalApi {
    $bodyObj = @{
        model      = $Model
        messages   = @($script:Messages)
        think      = $script:ThinkEnabled
        stream     = $false
        keep_alive = '5m'
        # Hardware/runtime placement (GPU/CPU, context length, threads) belongs
        # to the selected Ollama model profile. Keep only per-request generation
        # controls here so QwenChat does not override host-specific profiles.
        options    = @{
            num_predict = $(if ($script:ThinkEnabled) {
                [int]$script:Config.LocalGeneration.NumPredictThink
            } else {
                [int]$script:Config.LocalGeneration.NumPredictNormal
            })
            temperature = [double]$script:Config.LocalGeneration.Temperature
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 12 -Compress
    return Invoke-RestMethod -Uri "$BaseUri/api/chat" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
}

function Invoke-QwenSynthesis([string]$OriginalPrompt, [string]$FrontierResult) {
    $synthesisSystem = Expand-RuntimePolicy $script:SynthesisSystemTemplate

    $synthesisUser = @"
ORIGINAL USER REQUEST:
$OriginalPrompt

FRONTIER RESULT:
$FrontierResult
"@

    $bodyObj = @{
        model      = $Model
        messages   = @(
            @{ role = 'system'; content = $synthesisSystem },
            @{ role = 'user'; content = $synthesisUser }
        )
        think      = $script:ThinkEnabled
        stream     = $false
        keep_alive = '5m'
        # Do not override num_gpu/num_ctx/num_thread here; they are defined
        # by the selected Ollama model profile.
        options    = @{
            num_predict = $(if ($script:ThinkEnabled) {
                [int]$script:Config.SynthesisGeneration.NumPredictThink
            } else {
                [int]$script:Config.SynthesisGeneration.NumPredictNormal
            })
            temperature      = [double]$script:Config.SynthesisGeneration.Temperature
            presence_penalty = [double]$script:Config.SynthesisGeneration.PresencePenalty
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 12 -Compress
    return Invoke-RestMethod -Uri "$BaseUri/api/chat" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
}

function Show-QwenThinking($Response) {
    $thinking = [string]$Response.message.thinking
    if ($script:ThinkEnabled -and $thinking) {
        Write-Host "`n--- thinking ---" -ForegroundColor DarkGray
        Write-Host $thinking -ForegroundColor DarkGray
        Write-Host "--- answer ---" -ForegroundColor DarkGray
    }
}

function Get-CleanQwenContent($Response) {
    $content = [string]$Response.message.content
    if ([string]::IsNullOrWhiteSpace($content)) { return '' }

    if (-not $script:ThinkEnabled) {
        if ($content -match '(?is)<think>.*?</think>') {
            Write-Host "`n[Qwen reasoning leaked into content; the wrapper hid it.]" -ForegroundColor DarkGray
            $content = [regex]::Replace($content, '(?is)<think>.*?</think>\s*', '')
        } elseif ($content -match '(?is)</think>') {
            # Compatibility guard: some Qwen/Ollama combinations expose the
            # closing tag while the opening thinking tag is consumed by the
            # chat template/parser. Preserve a leading ROUTE marker if present.
            $leadingRoute = $null
            if ($content -match '(?im)^\s*(ROUTE:\s*(?:LOCAL|FRONTIER))\s*$') {
                $leadingRoute = $Matches[1].ToUpperInvariant()
            }
            Write-Host "`n[Qwen reasoning leaked into content; the wrapper hid it after </think>.]" -ForegroundColor DarkGray
            $content = [regex]::Replace($content, '(?is)^.*?</think>\s*', '')
            if ($leadingRoute -and $content -notmatch '(?im)^\s*ROUTE:\s*(?:LOCAL|FRONTIER)\s*$') {
                $content = "$leadingRoute`n$content"
            }
        }
    }

    return $content.Trim()
}

function Get-QwenRoute([string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return 'UNKNOWN' }
    if ($Content -match '(?im)^\s*ROUTE:\s*FRONTIER\s*$') { return 'FRONTIER' }
    if ($Content -match '(?im)^\s*ROUTE:\s*LOCAL\s*$') { return 'LOCAL' }
    return 'UNKNOWN'
}

function Remove-QwenRouteMarker([string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return '' }
    $clean = [regex]::Replace($Content, '(?im)^\s*ROUTE:\s*LOCAL\s*\r?\n?', '', 1)
    $clean = [regex]::Replace($clean, '(?im)^\s*ROUTE:\s*FRONTIER\s*\r?\n?', '', 1)
    return $clean.Trim()
}

function Test-UnfinishedSynthesis($Response, [string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return $true }

    # Ollama reports done_reason=length when generation reaches num_predict.
    # Never show a token-cap-truncated synthesis as a complete answer; the
    # caller will fall back to the already complete frontier result instead.
    if ([string]$Response.done_reason -eq 'length') { return $true }

    $unfinishedThreshold = [int]$script:Config.SynthesisGeneration.UnfinishedEvalThreshold
    if ($Response.eval_count -ge $unfinishedThreshold -and
        $Content -match '(?is)^\s*(okay,?\s+let me|let me|first,?\s+i\s+need|we\s+need|i\s+need\s+to|let''s\s+(?:tackle|work|analyze))') {
        return $true
    }
    return $false
}

function Invoke-Qwen([string]$Prompt) {
    Refresh-SystemPrompt

    # Capture context before appending the current user turn.
    $recentContext = Get-HardGateContext $Prompt

    $script:Messages += @{ role = 'user'; content = $Prompt }
    Trim-Messages

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $policyReason = Get-FrontierPolicyReason $Prompt
    $route = $null
    $r = $null
    $frontierResult = $null
    $finalContent = $null

    if (-not [string]::IsNullOrWhiteSpace($policyReason)) {
        $route = 'FRONTIER'
        Write-Host ("`n[policy -> FRONTIER; reason={0}]" -f $policyReason) -ForegroundColor DarkCyan
    } else {
        # No Ollama tool schema is exposed here. Qwen decides with a plain-text
        # route marker and, on LOCAL, the same generation is already the answer.
        $r = Invoke-QwenLocalApi
        Show-QwenThinking $r
        $candidate = Get-CleanQwenContent $r
        $route = Get-QwenRoute $candidate

        if ($route -eq 'FRONTIER') {
            Write-Host "`n[Qwen route -> FRONTIER]" -ForegroundColor DarkCyan
        } elseif ($route -eq 'LOCAL') {
            Write-Host "`n[Qwen route -> LOCAL]" -ForegroundColor DarkGray
            $finalContent = Remove-QwenRouteMarker $candidate
        } else {
            # Fail closed on cost/escalation: malformed routing never triggers
            # frontier automatically. Treat the generation as a local answer.
            Write-Host "`n[Qwen route marker missing; fail-closed -> LOCAL]" -ForegroundColor Yellow
            $route = 'LOCAL'
            $finalContent = Remove-QwenRouteMarker $candidate
        }
    }

    if ($route -eq 'FRONTIER') {
        $codexPrompt = $Prompt
        if (-not [string]::IsNullOrWhiteSpace($recentContext)) {
            $codexPrompt = @"
CURRENT USER REQUEST:
$Prompt

PREVIOUS USER TURN:
$recentContext
"@
        }

        Write-Host ("[ask_codex; {0} characters]" -f $codexPrompt.Length) -ForegroundColor DarkCyan
        try {
            $frontierResult = Invoke-CodexReadOnly $codexPrompt
            Write-Host ("[ask_codex -> Qwen; {0} characters]" -f $frontierResult.Length) -ForegroundColor DarkCyan
        } catch {
            $frontierResult = "ask_codex failed: $($_.Exception.Message)"
            Write-Host "[$frontierResult]" -ForegroundColor Yellow
        }

        if ($frontierResult -like 'ask_codex failed:*') {
            $finalContent = $frontierResult
        } else {
            $r = Invoke-QwenSynthesis $Prompt $frontierResult
            Show-QwenThinking $r
            $candidate = Get-CleanQwenContent $r

            if (Test-UnfinishedSynthesis $r $candidate) {
                Write-Host "`n[Qwen synthesis did not complete; showing the frontier result directly.]" -ForegroundColor Yellow
                $finalContent = $frontierResult
            } else {
                $finalContent = $candidate
            }
        }
    }

    $sw.Stop()

    if ([string]::IsNullOrWhiteSpace($finalContent)) {
        Write-Host "`n[The model did not produce final content within the token limit.]" -ForegroundColor Yellow
    } else {
        Write-Host "`n$finalContent"
        # Keep the routing protocol visible in internal conversation history.
        # The marker is hidden from the user-facing output above, but storing it
        # prevents previous assistant turns from becoming counterexamples to the
        # system instruction that every normal turn must start with ROUTE: ...
        $historyContent = "ROUTE: $route`n$finalContent"
        $script:Messages += @{ role = 'assistant'; content = $historyContent }
        Trim-Messages
    }

    if ($null -ne $r) {
        $tokps = $null
        if ($r.eval_duration -gt 0 -and $r.eval_count) {
            $tokps = [Math]::Round(($r.eval_count * 1e9) / $r.eval_duration, 2)
        }

        Write-Host ("`n[{0:n2}s; prompt {1} tok; generated {2} tok; {3} tok/s; think={4}; route={5}]" -f `
            $sw.Elapsed.TotalSeconds, $r.prompt_eval_count, $r.eval_count, $tokps, $script:ThinkEnabled, $route) `
            -ForegroundColor DarkGray
    } else {
        Write-Host ("`n[{0:n2}s; think={1}; route={2}]" -f `
            $sw.Elapsed.TotalSeconds, $script:ThinkEnabled, $route) -ForegroundColor DarkGray
    }

    if (-not [string]::IsNullOrWhiteSpace($finalContent)) {
        Persist-TurnAndMemory `
            -Prompt $Prompt `
            -FinalContent $finalContent `
            -Route $route `
            -PolicyReason $policyReason `
            -LocalRaw $localRaw `
            -FrontierResult $frontierResult `
            -Response $r `
            -AnswerSeconds $sw.Elapsed.TotalSeconds
    }
}


Test-Ollama
Write-Host ""
Write-Host "Qwen local chat v8 (external policy/config). Commands: /exit, /clear, /paste, /think on, /think off"
Write-Host "Frontier action: ask_codex (read-only, max 1 call per user turn)"
Write-Host "Routing: hard freshness/web gate + Qwen ROUTE: LOCAL/FRONTIER (no Ollama tools)"
Write-Host ("Thinking is now: {0} (controlled by the Ollama API think parameter)" -f $ThinkEnabled)
Write-Host ""

while ($true) {
    $prompt = Read-Host "Qwen>"
    if ($null -eq $prompt) { continue }

    switch -Regex ($prompt.Trim()) {
        '^/exit$' {
            exit 0
        }
        '^/clear$' {
            Reset-Messages
            Write-Host "Conversation history cleared."
            continue
        }
        '^/paste$' {
            $clip = Get-Clipboard -Raw
            if ([string]::IsNullOrWhiteSpace($clip)) {
                Write-Host "Clipboard is empty." -ForegroundColor Yellow
                continue
            }
            Write-Host ("[Sending clipboard: {0} characters]" -f $clip.Length) -ForegroundColor DarkGray
            Invoke-Qwen $clip
            continue
        }
        '^/think\s+on$' {
            $ThinkEnabled = $true
            Write-Host "Thinking enabled."
            continue
        }
        '^/think\s+off$' {
            $ThinkEnabled = $false
            Write-Host "Thinking disabled."
            continue
        }
        '^\s*$' {
            continue
        }
        default {
            Invoke-Qwen $prompt
        }
    }
} {
            Clear-PersistentConversationMemory
            Write-Host "Working memory and active conversation context cleared. Historical logs retained."
            continue
        }
        '^/paste$' {
            $clip = Get-Clipboard -Raw
            if ([string]::IsNullOrWhiteSpace($clip)) {
                Write-Host "Clipboard is empty." -ForegroundColor Yellow
                continue
            }
            Write-Host ("[Sending clipboard: {0} characters]" -f $clip.Length) -ForegroundColor DarkGray
            Invoke-Qwen $clip
            continue
        }
        '^/think\s+on$' {
            $ThinkEnabled = $true
            Write-Host "Thinking enabled."
            continue
        }
        '^/think\s+off$' {
            $ThinkEnabled = $false
            Write-Host "Thinking disabled."
            continue
        }
        '^\s*$' {
            continue
        }
        default {
            Invoke-Qwen $prompt
        }
    }
}, '')
    $start = $clean.IndexOf('{')
    $end = $clean.LastIndexOf('}')
    if ($start -ge 0 -and $end -gt $start) {
        $clean = $clean.Substring($start, $end - $start + 1)
    }
    return ($clean | ConvertFrom-Json)
}

function Invoke-QwenMemoryCall([string]$SystemPrompt, [string]$UserPrompt, [int]$NumPredict) {
    $bodyObj = @{
        model = $Model
        messages = @(
            @{ role = 'system'; content = $SystemPrompt },
            @{ role = 'user'; content = $UserPrompt }
        )
        think = $false
        stream = $false
        keep_alive = '5m'
        options = @{
            num_predict = $NumPredict
            temperature = [double]$script:Config.Memory.Temperature
        }
    }
    $body = $bodyObj | ConvertTo-Json -Depth 14 -Compress
    return Invoke-RestMethod -Uri "$BaseUri/api/chat" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
}

function Invoke-QwenMemoryNote(
    [int]$TurnId,
    [string]$Prompt,
    [string]$FinalContent,
    [string]$Route,
    [string]$FrontierResult
) {
    $memory = Get-MemoryContextBlock
    $frontierForNote = [string]$FrontierResult
    $frontierLimit = [int]$script:Config.Memory.FrontierForNoteMaxChars
    if (-not [string]::IsNullOrWhiteSpace($frontierForNote) -and $frontierForNote.Length -gt $frontierLimit) {
        $frontierForNote = $frontierForNote.Substring(0, $frontierLimit) + ' ...[truncated]'
    }
    if ([string]::IsNullOrWhiteSpace($frontierForNote)) { $frontierForNote = '(none)' }

    $userText = @"
TURN ID: $TurnId
ROUTE: $Route

CURRENT MEMORY:
$memory

USER:
$Prompt

FINAL ASSISTANT ANSWER:
$FinalContent

FRONTIER RESULT IF USED:
$frontierForNote
"@

    $r = Invoke-QwenMemoryCall `
        (Expand-RuntimePolicy $script:MemoryNoteTemplate) `
        $userText `
        ([int]$script:Config.Memory.NoteNumPredict)

    $raw = [string]$r.message.content
    $parsed = Get-JsonObjectFromModelText $raw
    return [pscustomobject]@{
        Raw = $raw
        Parsed = $parsed
        EvalCount = $r.eval_count
        EvalDuration = $r.eval_duration
    }
}

function Invoke-MemoryCompaction {
    $pending = @(Get-PendingNoteRecords)
    if ($pending.Count -eq 0) { return $false }

    $working = Get-WorkingMemoryRaw
    $pendingJson = $pending | ConvertTo-Json -Depth 14

    $userText = @"
EXISTING WORKING MEMORY:
$working

NEW MEMORY NOTES:
$pendingJson
"@

    $r = Invoke-QwenMemoryCall `
        (Expand-RuntimePolicy $script:MemoryCompactionTemplate) `
        $userText `
        ([int]$script:Config.Memory.CompactionNumPredict)

    $raw = [string]$r.message.content
    $parsed = Get-JsonObjectFromModelText $raw

    if ($parsed.PSObject.Properties.Name -notcontains 'updated_at') {
        $parsed | Add-Member -NotePropertyName updated_at -NotePropertyValue ((Get-Date).ToString('o'))
    } else {
        $parsed.updated_at = (Get-Date).ToString('o')
    }

    Write-JsonAtomic $script:WorkingMemoryPath $parsed
    Clear-PendingNotes
    return $true
}

function Get-PolicyFingerprint {
    $parts = @()
    foreach ($name in @(
        'orchestrator-system.txt',
        'synthesis-system.txt',
        'frontier-subagent.txt',
        'memory-note-system.txt',
        'memory-compaction-system.txt'
    )) {
        $path = Join-Path $PolicyDir $name
        if (Test-Path -LiteralPath $path) {
            $h = Get-FileHash -LiteralPath $path -Algorithm SHA256
            $parts += ("{0}:{1}" -f $name, $h.Hash)
        }
    }
    return ($parts -join ';')
}

function Load-RecentConversationFromDisk {
    if (-not $script:MemoryEnabled) { return }
    $turns = @()
    $files = @(Get-ChildItem -LiteralPath $script:LogDir -Filter 'conversation-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($f in $files) {
        foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
            } catch {
                continue
            }
            if ([string]$row.event -eq 'turn' -and [int]$row.epoch -eq [int]$script:RuntimeState.epoch) {
                $turns += $row
            }
        }
    }

    $turns = @($turns | Select-Object -Last $script:MemoryRecentTurns)
    foreach ($t in $turns) {
        $script:Messages += @{ role = 'user'; content = [string]$t.user }
        $assistantStored = "ROUTE: $([string]$t.route)`n$([string]$t.assistant)"
        $script:Messages += @{ role = 'assistant'; content = $assistantStored }
    }
    Trim-Messages
}

function Initialize-PersistentMemory {
    if (-not $script:MemoryEnabled) { return }

    New-Item -ItemType Directory -Force -Path $script:StateDir | Out-Null
    New-Item -ItemType Directory -Force -Path $script:LogDir | Out-Null

    if (-not (Test-Path -LiteralPath $script:WorkingMemoryPath)) {
        Write-JsonAtomic $script:WorkingMemoryPath (New-DefaultWorkingMemory)
    }
    if (-not (Test-Path -LiteralPath $script:PendingNotesPath)) {
        Clear-PendingNotes
    }
    if (-not (Test-Path -LiteralPath $script:RuntimeStatePath)) {
        Write-JsonAtomic $script:RuntimeStatePath (New-DefaultRuntimeState)
    }

    try {
        $script:RuntimeState = Get-Content -LiteralPath $script:RuntimeStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $script:RuntimeState = [pscustomobject](New-DefaultRuntimeState)
        Write-JsonAtomic $script:RuntimeStatePath $script:RuntimeState
    }

    Load-RecentConversationFromDisk
}

function Save-RuntimeState {
    if ($script:MemoryEnabled) {
        Write-JsonAtomic $script:RuntimeStatePath $script:RuntimeState
    }
}

function Clear-PersistentConversationMemory {
    Reset-Messages
    if (-not $script:MemoryEnabled) { return }

    $script:RuntimeState.epoch = [int]$script:RuntimeState.epoch + 1
    $script:RuntimeState.completed_since_compaction = 0
    Write-JsonAtomic $script:WorkingMemoryPath (New-DefaultWorkingMemory)
    Clear-PendingNotes
    Save-RuntimeState

    if ([bool]$script:Config.ResearchLogging.Enabled) {
        Append-JsonLine (Get-MonthlyLogPath 'trace') ([ordered]@{
            event = 'clear'
            timestamp = (Get-Date).ToString('o')
            epoch = [int]$script:RuntimeState.epoch
            note = 'Working memory and active recent context cleared; historical logs retained.'
        })
    }
}

function Persist-TurnAndMemory(
    [string]$Prompt,
    [string]$FinalContent,
    [string]$Route,
    [string]$PolicyReason,
    [string]$LocalRaw,
    [string]$FrontierResult,
    $Response,
    [double]$AnswerSeconds
) {
    if (-not $script:MemoryEnabled -and -not [bool]$script:Config.ResearchLogging.Enabled) { return }

    if ($script:MemoryEnabled) {
        $turnId = [int]$script:RuntimeState.next_turn_id
        $epoch = [int]$script:RuntimeState.epoch
    } else {
        $turnId = 0
        $epoch = 0
    }

    $timestamp = (Get-Date).ToString('o')
    $memoryBefore = if ($script:MemoryEnabled) { Get-MemoryContextBlock } else { '' }

    if ($script:MemoryEnabled) {
        Append-JsonLine (Get-MonthlyLogPath 'conversation') ([ordered]@{
            event = 'turn'
            timestamp = $timestamp
            turn_id = $turnId
            epoch = $epoch
            route = $Route
            user = $Prompt
            assistant = $FinalContent
        })

        $script:RuntimeState.next_turn_id = $turnId + 1
        Save-RuntimeState
    }

    $memoryNote = $null
    $memoryError = $null
    $compacted = $false
    $memorySw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($script:MemoryEnabled) {
        try {
            $memoryNote = Invoke-QwenMemoryNote $turnId $Prompt $FinalContent $Route $FrontierResult
            Append-JsonLine $script:PendingNotesPath ([ordered]@{
                turn_id = $turnId
                timestamp = (Get-Date).ToString('o')
                note = $memoryNote.Parsed
            })

            $script:RuntimeState.completed_since_compaction = [int]$script:RuntimeState.completed_since_compaction + 1

            if ([int]$script:RuntimeState.completed_since_compaction -ge $script:MemoryCompactionEvery) {
                try {
                    $compacted = Invoke-MemoryCompaction
                    if ($compacted) {
                        $script:RuntimeState.completed_since_compaction = 0
                    }
                } catch {
                    $memoryError = "compaction failed: $($_.Exception.Message)"
                }
            }
            Save-RuntimeState
        } catch {
            $memoryError = "memory note failed: $($_.Exception.Message)"
        }
    }

    $memorySw.Stop()
    $memoryAfter = if ($script:MemoryEnabled) { Get-MemoryContextBlock } else { '' }

    if ([bool]$script:Config.ResearchLogging.Enabled) {
        $trace = [ordered]@{
            event = 'turn_trace'
            timestamp = $timestamp
            turn_id = $turnId
            epoch = $epoch
            model = $Model
            context_length_hint = $script:ContextLengthHint
            route = $Route
            route_reason = $PolicyReason
            answer_seconds = [Math]::Round($AnswerSeconds, 3)
            memory_seconds = [Math]::Round($memorySw.Elapsed.TotalSeconds, 3)
            memory_compacted = $compacted
            memory_error = $memoryError
            policy_fingerprint = $script:PolicyFingerprint
            performance = if ($null -ne $Response) {
                [ordered]@{
                    prompt_eval_count = $Response.prompt_eval_count
                    prompt_eval_duration = $Response.prompt_eval_duration
                    eval_count = $Response.eval_count
                    eval_duration = $Response.eval_duration
                    done_reason = [string]$Response.done_reason
                }
            } else {
                $null
            }
            bias_signals = if ($null -ne $memoryNote -and $null -ne $memoryNote.Parsed.bias_signals) {
                $memoryNote.Parsed.bias_signals
            } else {
                @()
            }
        }

        if ([bool]$script:Config.ResearchLogging.IncludeRawText) {
            $trace.user = $Prompt
            $trace.local_raw = $LocalRaw
            $trace.frontier_raw = $FrontierResult
            $trace.final_answer = $FinalContent
            $trace.memory_note_raw = if ($null -ne $memoryNote) { $memoryNote.Raw } else { $null }
        }
        if ([bool]$script:Config.ResearchLogging.IncludeMemorySnapshots) {
            $trace.memory_before = $memoryBefore
            $trace.memory_after = $memoryAfter
        }

        Append-JsonLine (Get-MonthlyLogPath 'trace') $trace
    }

    if ($script:MemoryEnabled) {
        $state = if ($compacted) { 'note saved + compacted' } elseif ($memoryError) { $memoryError } else { 'note saved' }
        Write-Host ("[memory: {0}; {1:n2}s]" -f $state, $memorySw.Elapsed.TotalSeconds) -ForegroundColor DarkGray
    }
}

function Test-Ollama {
    try {
        $v = Invoke-RestMethod -Uri "$BaseUri/api/version" -Method Get -TimeoutSec 3
        Write-Host ("Ollama {0}; model {1}" -f $v.version, $Model)
    } catch {
        Write-Host "Ollama is not responding at $BaseUri." -ForegroundColor Red
        Write-Host "Start Ollama in another console first (for example: .\launch\Start-Ollama.ps1)."
        exit 1
    }
}

function Trim-Messages {
    $maxMessages = [int]$script:Config.HistoryMaxMessages
    if ($maxMessages -lt 2) { $maxMessages = 12 }

    if ($script:Messages.Count -gt $maxMessages) {
        $system = @($script:Messages | Where-Object { $_.role -eq 'system' } | Select-Object -First 1)
        $tailCount = $maxMessages - 1
        $tail = @($script:Messages | Where-Object { $_.role -ne 'system' } | Select-Object -Last $tailCount)
        $script:Messages = @($system + $tail)
    }
}


function Get-FrontierPolicyReason([string]$Prompt) {
    if ([string]::IsNullOrWhiteSpace($Prompt)) { return $null }

    $gates = $script:Config.HardGates

    if ($Prompt -match [string]$gates.ProductSpecPattern -and
        $Prompt -match [string]$gates.ProductIdentityPattern) {
        return 'named-product-specification'
    }

    foreach ($rule in @($gates.Rules)) {
        if ($Prompt -match [string]$rule.Pattern) {
            return [string]$rule.Reason
        }
    }
    return $null
}

function Get-HardGateContext([string]$Prompt) {
    $gates = $script:Config.HardGates
    $maxPromptChars = [int]$gates.FollowUpMaxPromptChars
    $maxContextChars = [int]$gates.FollowUpContextChars
    $followUpPattern = [string]$gates.FollowUpPattern

    if ([string]::IsNullOrWhiteSpace($Prompt) -or $Prompt.Length -gt $maxPromptChars) {
        return ''
    }

    if ($Prompt -notmatch $followUpPattern) {
        return ''
    }

    $lastUser = @(
        $script:Messages |
            Where-Object { $_.role -eq 'user' } |
            Select-Object -Last 1
    )
    if ($lastUser.Count -eq 0) { return '' }

    $text = [string]$lastUser[0].content
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    if ($text.Length -gt $maxContextChars) {
        $text = $text.Substring($text.Length - $maxContextChars)
    }
    return $text.Trim()
}

function Get-CodexProcessSpec {
    $cmd = Get-Command codex.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $cmd) {
        $cmd = Get-Command codex -ErrorAction Stop | Select-Object -First 1
    }
    $path = [string]$cmd.Source
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = [string]$cmd.Path
    }
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw 'The codex command could not be located.'
    }

    # Send prompts over stdin; never interpolate them into a shell command line.
    $fixedArgs = '--ask-for-approval never --sandbox read-only --search exec --json --ephemeral --ignore-user-config --skip-git-repo-check --cd "{0}" -' -f $env:TEMP
    $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()

    switch ($ext) {
        '.cmd' {
            return @{
                FileName = $env:ComSpec
                Arguments = '/d /s /c ""{0}" {1}"' -f $path, $fixedArgs
            }
        }
        '.bat' {
            return @{
                FileName = $env:ComSpec
                Arguments = '/d /s /c ""{0}" {1}"' -f $path, $fixedArgs
            }
        }
        '.ps1' {
            return @{
                FileName = 'powershell.exe'
                Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" {1}' -f $path, $fixedArgs
            }
        }
        default {
            return @{
                FileName = $path
                Arguments = $fixedArgs
            }
        }
    }
}

function Invoke-CodexReadOnly([string]$Prompt) {
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        throw 'ask_codex received an empty prompt.'
    }
    $maxFrontierPromptChars = [int]$script:Config.Frontier.MaxPromptChars
    if ($Prompt.Length -gt $maxFrontierPromptChars) {
        throw "ask_codex prompt is too long (maximum: $maxFrontierPromptChars characters)."
    }

    $spec = Get-CodexProcessSpec
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $spec.FileName
    $psi.Arguments = $spec.Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    # codex exec reads stdin as UTF-8. Windows PowerShell 5.1 can otherwise
    # encode redirected text using a legacy code page, corrupting Slovak text.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    if ($psi.PSObject.Properties.Name -contains 'StandardInputEncoding')  { $psi.StandardInputEncoding = $utf8NoBom }
    if ($psi.PSObject.Properties.Name -contains 'StandardOutputEncoding') { $psi.StandardOutputEncoding = $utf8NoBom }
    if ($psi.PSObject.Properties.Name -contains 'StandardErrorEncoding')  { $psi.StandardErrorEncoding = $utf8NoBom }

    # Use the existing authenticated ChatGPT/Codex session rather than an OpenAI API key.
    [void]$psi.EnvironmentVariables.Remove('OPENAI_API_KEY')
    [void]$psi.EnvironmentVariables.Remove('CODEX_API_KEY')
    [void]$psi.EnvironmentVariables.Remove('OPENAI_BASE_URL')

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    try {
        if (-not $p.Start()) {
            throw 'codex exec could not be started.'
        }

        $stdoutTask = $p.StandardOutput.ReadToEndAsync()
        $stderrTask = $p.StandardError.ReadToEndAsync()

        $delegatedPrompt = Expand-RuntimePolicy $script:FrontierSubagentTemplate
        $delegatedPrompt = $delegatedPrompt.Replace('{{TASK}}', $Prompt)
        # Write exact UTF-8 bytes; do not let Windows PowerShell choose an OEM/ANSI encoding.
        $stdinBytes = [System.Text.Encoding]::UTF8.GetBytes($delegatedPrompt)
        $p.StandardInput.BaseStream.Write($stdinBytes, 0, $stdinBytes.Length)
        $p.StandardInput.BaseStream.Flush()
        $p.StandardInput.Close()

        if (-not $p.WaitForExit($CodexTimeoutSec * 1000)) {
            try { & taskkill.exe /PID $p.Id /T /F 2>$null | Out-Null } catch { }
            throw "codex exec exceeded the ${CodexTimeoutSec}s timeout."
        }

        # Required to complete asynchronous stdout/stderr reads after WaitForExit(timeout).
        $p.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result

        if ($p.ExitCode -ne 0) {
            $detail = ([string]$stderr).Trim()
            if ($detail.Length -gt 2000) { $detail = $detail.Substring($detail.Length - 2000) }
            throw ("codex exec exited with code {0}. {1}" -f $p.ExitCode, $detail)
        }

        $finalText = $null
        foreach ($line in ($stdout -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $evt = $line | ConvertFrom-Json
            } catch {
                continue
            }
            if ($evt.type -eq 'item.completed' -and $evt.item.type -eq 'agent_message' -and $evt.item.text) {
                $finalText = [string]$evt.item.text
            }
            if ($evt.type -eq 'turn.failed') {
                $msg = [string]$evt.error.message
                if (-not [string]::IsNullOrWhiteSpace($msg)) {
                    throw "codex exec turn failed: $msg"
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($finalText)) {
            throw 'codex exec did not return a final agent_message.'
        }
        return $finalText.Trim()
    } finally {
        if ($null -ne $p) { $p.Dispose() }
    }
}

function Invoke-QwenLocalApi {
    $bodyObj = @{
        model      = $Model
        messages   = @($script:Messages)
        think      = $script:ThinkEnabled
        stream     = $false
        keep_alive = '5m'
        # Hardware/runtime placement (GPU/CPU, context length, threads) belongs
        # to the selected Ollama model profile. Keep only per-request generation
        # controls here so QwenChat does not override host-specific profiles.
        options    = @{
            num_predict = $(if ($script:ThinkEnabled) {
                [int]$script:Config.LocalGeneration.NumPredictThink
            } else {
                [int]$script:Config.LocalGeneration.NumPredictNormal
            })
            temperature = [double]$script:Config.LocalGeneration.Temperature
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 12 -Compress
    return Invoke-RestMethod -Uri "$BaseUri/api/chat" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
}

function Invoke-QwenSynthesis([string]$OriginalPrompt, [string]$FrontierResult) {
    $synthesisSystem = Expand-RuntimePolicy $script:SynthesisSystemTemplate

    $synthesisUser = @"
ORIGINAL USER REQUEST:
$OriginalPrompt

FRONTIER RESULT:
$FrontierResult
"@

    $bodyObj = @{
        model      = $Model
        messages   = @(
            @{ role = 'system'; content = $synthesisSystem },
            @{ role = 'user'; content = $synthesisUser }
        )
        think      = $script:ThinkEnabled
        stream     = $false
        keep_alive = '5m'
        # Do not override num_gpu/num_ctx/num_thread here; they are defined
        # by the selected Ollama model profile.
        options    = @{
            num_predict = $(if ($script:ThinkEnabled) {
                [int]$script:Config.SynthesisGeneration.NumPredictThink
            } else {
                [int]$script:Config.SynthesisGeneration.NumPredictNormal
            })
            temperature      = [double]$script:Config.SynthesisGeneration.Temperature
            presence_penalty = [double]$script:Config.SynthesisGeneration.PresencePenalty
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 12 -Compress
    return Invoke-RestMethod -Uri "$BaseUri/api/chat" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
}

function Show-QwenThinking($Response) {
    $thinking = [string]$Response.message.thinking
    if ($script:ThinkEnabled -and $thinking) {
        Write-Host "`n--- thinking ---" -ForegroundColor DarkGray
        Write-Host $thinking -ForegroundColor DarkGray
        Write-Host "--- answer ---" -ForegroundColor DarkGray
    }
}

function Get-CleanQwenContent($Response) {
    $content = [string]$Response.message.content
    if ([string]::IsNullOrWhiteSpace($content)) { return '' }

    if (-not $script:ThinkEnabled) {
        if ($content -match '(?is)<think>.*?</think>') {
            Write-Host "`n[Qwen reasoning leaked into content; the wrapper hid it.]" -ForegroundColor DarkGray
            $content = [regex]::Replace($content, '(?is)<think>.*?</think>\s*', '')
        } elseif ($content -match '(?is)</think>') {
            # Compatibility guard: some Qwen/Ollama combinations expose the
            # closing tag while the opening thinking tag is consumed by the
            # chat template/parser. Preserve a leading ROUTE marker if present.
            $leadingRoute = $null
            if ($content -match '(?im)^\s*(ROUTE:\s*(?:LOCAL|FRONTIER))\s*$') {
                $leadingRoute = $Matches[1].ToUpperInvariant()
            }
            Write-Host "`n[Qwen reasoning leaked into content; the wrapper hid it after </think>.]" -ForegroundColor DarkGray
            $content = [regex]::Replace($content, '(?is)^.*?</think>\s*', '')
            if ($leadingRoute -and $content -notmatch '(?im)^\s*ROUTE:\s*(?:LOCAL|FRONTIER)\s*$') {
                $content = "$leadingRoute`n$content"
            }
        }
    }

    return $content.Trim()
}

function Get-QwenRoute([string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return 'UNKNOWN' }
    if ($Content -match '(?im)^\s*ROUTE:\s*FRONTIER\s*$') { return 'FRONTIER' }
    if ($Content -match '(?im)^\s*ROUTE:\s*LOCAL\s*$') { return 'LOCAL' }
    return 'UNKNOWN'
}

function Remove-QwenRouteMarker([string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return '' }
    $clean = [regex]::Replace($Content, '(?im)^\s*ROUTE:\s*LOCAL\s*\r?\n?', '', 1)
    $clean = [regex]::Replace($clean, '(?im)^\s*ROUTE:\s*FRONTIER\s*\r?\n?', '', 1)
    return $clean.Trim()
}

function Test-UnfinishedSynthesis($Response, [string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return $true }

    # Ollama reports done_reason=length when generation reaches num_predict.
    # Never show a token-cap-truncated synthesis as a complete answer; the
    # caller will fall back to the already complete frontier result instead.
    if ([string]$Response.done_reason -eq 'length') { return $true }

    $unfinishedThreshold = [int]$script:Config.SynthesisGeneration.UnfinishedEvalThreshold
    if ($Response.eval_count -ge $unfinishedThreshold -and
        $Content -match '(?is)^\s*(okay,?\s+let me|let me|first,?\s+i\s+need|we\s+need|i\s+need\s+to|let''s\s+(?:tackle|work|analyze))') {
        return $true
    }
    return $false
}

function Invoke-Qwen([string]$Prompt) {
    Refresh-SystemPrompt

    # Capture context before appending the current user turn.
    $recentContext = Get-HardGateContext $Prompt

    $script:Messages += @{ role = 'user'; content = $Prompt }
    Trim-Messages

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $policyReason = Get-FrontierPolicyReason $Prompt
    $route = $null
    $r = $null
    $frontierResult = $null
    $finalContent = $null

    if (-not [string]::IsNullOrWhiteSpace($policyReason)) {
        $route = 'FRONTIER'
        Write-Host ("`n[policy -> FRONTIER; reason={0}]" -f $policyReason) -ForegroundColor DarkCyan
    } else {
        # No Ollama tool schema is exposed here. Qwen decides with a plain-text
        # route marker and, on LOCAL, the same generation is already the answer.
        $r = Invoke-QwenLocalApi
        Show-QwenThinking $r
        $candidate = Get-CleanQwenContent $r
        $route = Get-QwenRoute $candidate

        if ($route -eq 'FRONTIER') {
            Write-Host "`n[Qwen route -> FRONTIER]" -ForegroundColor DarkCyan
        } elseif ($route -eq 'LOCAL') {
            Write-Host "`n[Qwen route -> LOCAL]" -ForegroundColor DarkGray
            $finalContent = Remove-QwenRouteMarker $candidate
        } else {
            # Fail closed on cost/escalation: malformed routing never triggers
            # frontier automatically. Treat the generation as a local answer.
            Write-Host "`n[Qwen route marker missing; fail-closed -> LOCAL]" -ForegroundColor Yellow
            $route = 'LOCAL'
            $finalContent = Remove-QwenRouteMarker $candidate
        }
    }

    if ($route -eq 'FRONTIER') {
        $codexPrompt = $Prompt
        if (-not [string]::IsNullOrWhiteSpace($recentContext)) {
            $codexPrompt = @"
CURRENT USER REQUEST:
$Prompt

PREVIOUS USER TURN:
$recentContext
"@
        }

        Write-Host ("[ask_codex; {0} characters]" -f $codexPrompt.Length) -ForegroundColor DarkCyan
        try {
            $frontierResult = Invoke-CodexReadOnly $codexPrompt
            Write-Host ("[ask_codex -> Qwen; {0} characters]" -f $frontierResult.Length) -ForegroundColor DarkCyan
        } catch {
            $frontierResult = "ask_codex failed: $($_.Exception.Message)"
            Write-Host "[$frontierResult]" -ForegroundColor Yellow
        }

        if ($frontierResult -like 'ask_codex failed:*') {
            $finalContent = $frontierResult
        } else {
            $r = Invoke-QwenSynthesis $Prompt $frontierResult
            Show-QwenThinking $r
            $candidate = Get-CleanQwenContent $r

            if (Test-UnfinishedSynthesis $r $candidate) {
                Write-Host "`n[Qwen synthesis did not complete; showing the frontier result directly.]" -ForegroundColor Yellow
                $finalContent = $frontierResult
            } else {
                $finalContent = $candidate
            }
        }
    }

    $sw.Stop()

    if ([string]::IsNullOrWhiteSpace($finalContent)) {
        Write-Host "`n[The model did not produce final content within the token limit.]" -ForegroundColor Yellow
    } else {
        Write-Host "`n$finalContent"
        # Keep the routing protocol visible in internal conversation history.
        # The marker is hidden from the user-facing output above, but storing it
        # prevents previous assistant turns from becoming counterexamples to the
        # system instruction that every normal turn must start with ROUTE: ...
        $historyContent = "ROUTE: $route`n$finalContent"
        $script:Messages += @{ role = 'assistant'; content = $historyContent }
        Trim-Messages
    }

    if ($null -ne $r) {
        $tokps = $null
        if ($r.eval_duration -gt 0 -and $r.eval_count) {
            $tokps = [Math]::Round(($r.eval_count * 1e9) / $r.eval_duration, 2)
        }

        Write-Host ("`n[{0:n2}s; prompt {1} tok; generated {2} tok; {3} tok/s; think={4}; route={5}]" -f `
            $sw.Elapsed.TotalSeconds, $r.prompt_eval_count, $r.eval_count, $tokps, $script:ThinkEnabled, $route) `
            -ForegroundColor DarkGray
    } else {
        Write-Host ("`n[{0:n2}s; think={1}; route={2}]" -f `
            $sw.Elapsed.TotalSeconds, $script:ThinkEnabled, $route) -ForegroundColor DarkGray
    }

    if (-not [string]::IsNullOrWhiteSpace($finalContent)) {
        Persist-TurnAndMemory `
            -Prompt $Prompt `
            -FinalContent $finalContent `
            -Route $route `
            -PolicyReason $policyReason `
            -LocalRaw $localRaw `
            -FrontierResult $frontierResult `
            -Response $r `
            -AnswerSeconds $sw.Elapsed.TotalSeconds
    }
}


Test-Ollama
Write-Host ""
Write-Host "Qwen local chat v8 (external policy/config). Commands: /exit, /clear, /paste, /think on, /think off"
Write-Host "Frontier action: ask_codex (read-only, max 1 call per user turn)"
Write-Host "Routing: hard freshness/web gate + Qwen ROUTE: LOCAL/FRONTIER (no Ollama tools)"
Write-Host ("Thinking is now: {0} (controlled by the Ollama API think parameter)" -f $ThinkEnabled)
Write-Host ""

while ($true) {
    $prompt = Read-Host "Qwen>"
    if ($null -eq $prompt) { continue }

    switch -Regex ($prompt.Trim()) {
        '^/exit$' {
            exit 0
        }
        '^/clear$' {
            Reset-Messages
            Write-Host "Conversation history cleared."
            continue
        }
        '^/paste$' {
            $clip = Get-Clipboard -Raw
            if ([string]::IsNullOrWhiteSpace($clip)) {
                Write-Host "Clipboard is empty." -ForegroundColor Yellow
                continue
            }
            Write-Host ("[Sending clipboard: {0} characters]" -f $clip.Length) -ForegroundColor DarkGray
            Invoke-Qwen $clip
            continue
        }
        '^/think\s+on$' {
            $ThinkEnabled = $true
            Write-Host "Thinking enabled."
            continue
        }
        '^/think\s+off$' {
            $ThinkEnabled = $false
            Write-Host "Thinking disabled."
            continue
        }
        '^\s*$' {
            continue
        }
        default {
            Invoke-Qwen $prompt
        }
    }
}