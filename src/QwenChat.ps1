param(
    [string]$Model,
    [switch]$Think,
    [Nullable[int]]$CodexTimeoutSec,
    [string]$ConfigPath,
    [Nullable[int]]$ContextLengthHint,
    [Nullable[int]]$MemoryRecentTurns,
    [Nullable[int]]$MemoryContextMaxChars,
    [Nullable[int]]$MemoryRecentContextMaxChars,
    [Nullable[int]]$MemoryRetrievalMaxChars,
    [Nullable[int]]$MemoryRetrievalMaxItems
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

$memoryModule = Join-Path $PSScriptRoot 'QwenMemory.ps1'
if (-not (Test-Path -LiteralPath $memoryModule)) {
    throw "Qwen memory module not found: $memoryModule"
}
. $memoryModule

$ThinkEnabled = [bool]$Think
Initialize-QwenMemoryConfiguration `
    $ContextLengthHint `
    $MemoryRecentTurns `
    $MemoryContextMaxChars `
    $MemoryRecentContextMaxChars `
    $MemoryRetrievalMaxChars `
    $MemoryRetrievalMaxItems

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
    $memoryBlock = Get-MemoryContextBlock $OriginalPrompt
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
    $inlineMemoryNote = $null

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
        $parsedCandidate = Split-InlineMemoryNote $candidate
        $visibleCandidate = [string]$parsedCandidate.VisibleText
        $route = Get-QwenRoute $visibleCandidate

        if ($route -eq 'FRONTIER') {
            Write-Host "`n[Qwen route -> FRONTIER]" -ForegroundColor DarkCyan
        } elseif ($route -eq 'LOCAL') {
            Write-Host "`n[Qwen route -> LOCAL]" -ForegroundColor DarkGray
            $inlineMemoryNote = $parsedCandidate
            $finalContent = Remove-QwenRouteMarker $visibleCandidate
        } else {
            # Fail closed on cost/escalation: malformed routing never triggers
            # frontier automatically. Treat the generation as a local answer.
            Write-Host "`n[Qwen route marker missing; fail-closed -> LOCAL]" -ForegroundColor Yellow
            $route = 'LOCAL'
            $inlineMemoryNote = $parsedCandidate
            $finalContent = Remove-QwenRouteMarker $visibleCandidate
        }
    }

    if ($route -eq 'FRONTIER') {
        $memoryBlock = Get-MemoryContextBlock $Prompt
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
            $parsedSynthesis = Split-InlineMemoryNote $candidate
            $visibleSynthesis = [string]$parsedSynthesis.VisibleText

            if (Test-UnfinishedSynthesis $r $visibleSynthesis) {
                Write-Host "`n[Qwen synthesis did not complete; showing the frontier result directly.]" -ForegroundColor Yellow
                $finalContent = $frontierResult
                $inlineMemoryNote = $null
            } else {
                $finalContent = $visibleSynthesis
                $inlineMemoryNote = $parsedSynthesis
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
            -AnswerSeconds $sw.Elapsed.TotalSeconds `
            -InlineMemoryNote $inlineMemoryNote
    }
}


Initialize-PersistentMemory
$script:PolicyFingerprint = Get-PolicyFingerprint

Test-Ollama
Write-Host ""
Write-Host "Qwen local chat v9.2-dev1 (single-pass micro-note shadow mode; v9.1.3 memory persistence). Commands: /exit, /clear, /paste, /think on, /think off"
Write-Host "Frontier action: ask_codex (read-only, max 1 call per user turn)"
Write-Host "Routing: hard freshness/web gate + Qwen ROUTE: LOCAL/FRONTIER (no Ollama tools)"
Write-Host ("Thinking is now: {0} (controlled by the Ollama API think parameter)" -f $ThinkEnabled)
if ($script:MemoryEnabled) {
    Write-Host ("Persistent memory: ON; recent turns={0}; compact every={1}; note<={2} chars; state<={3} chars" -f `
        $script:MemoryRecentTurns, $script:MemoryCompactionEvery, $script:MemoryNoteMaxChars, $script:MemoryStateMaxChars)
    Write-Host ("Exact-data retrieval: max {0} items / {1} chars" -f `
        $script:MemoryRetrievalMaxItems, $script:MemoryRetrievalMaxChars)
    Write-Host ("Memory/log path: {0}" -f $script:DataRoot)
}
Write-Host ""

while ($true) {
    $prompt = Read-Host "Qwen>"
    if ($null -eq $prompt) { continue }

    switch -Regex ($prompt.Trim()) {
        '^/exit$' {
            exit 0
        }
        '^/clear$' {
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
}