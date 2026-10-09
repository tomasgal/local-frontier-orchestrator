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
$script:L2StructuredMemoryTemplate   = Read-PolicyTemplate 'l2-structured-memory.txt'

$structuredMemoryModule = Join-Path $PSScriptRoot 'LfoStructuredMemory.ps1'
if (-not (Test-Path -LiteralPath $structuredMemoryModule)) {
    throw "L2 structured memory module not found: $structuredMemoryModule"
}
. $structuredMemoryModule

$memoryStoreModule = Join-Path $PSScriptRoot 'LfoMemoryStore.ps1'
if (-not (Test-Path -LiteralPath $memoryStoreModule)) {
    throw "L2 memory store module not found: $memoryStoreModule"
}
. $memoryStoreModule

$l2ReadModule = Join-Path $PSScriptRoot 'LfoStructuredRetrieval.ps1'
if (-not (Test-Path -LiteralPath $l2ReadModule)) {
    throw "L2 read module not found: $l2ReadModule"
}
. $l2ReadModule

$telemetryModule = Join-Path $PSScriptRoot 'LfoTurnTelemetry.ps1'
if (-not (Test-Path -LiteralPath $telemetryModule)) { throw "Dev4 telemetry module not found: $telemetryModule" }
. $telemetryModule

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

function Get-QwenLocalOutputFormat {
    if (Test-LfoDev5CompactReadEligible) {
        # Dev4 already makes this exact LOCAL read mode non-persistent.
        # Drop redundant model-generated side-channels, keeping Qwen routing.
        return @{
            type = 'object'
            properties = @{
                route = @{ type = 'string'; enum = @('LOCAL', 'FRONTIER') }
                answer = @{
                    type = 'string'
                    description = 'For LOCAL: complete natural response. For FRONTIER: empty.'
                }
            }
            required = @('route', 'answer')
            additionalProperties = $false
        }
    }
    return @{
        type = 'object'
        properties = @{
            route = @{
                type = 'string'
                enum = @('LOCAL', 'FRONTIER')
            }
            answer = @{
                type = 'string'
                description = 'For LOCAL: complete natural user-facing response; never use the - sentinel. For a declarative user fact, acknowledge naturally. For FRONTIER: empty.'
            }
            memory_note = @{
                type = 'string'
                maxLength = $script:MemoryNoteMaxChars
                description = 'New durable delta from the current user turn only; max 40 chars; use - when empty. Use CORR only for an explicit correction/replacement of an earlier value, never for a first mention; include target/key plus the new value.'
            }
            memory_ops = Get-LfoStructuredMemoryOperationSchema 6
        }
        required = @('route', 'answer', 'memory_note', 'memory_ops')
        additionalProperties = $false
    }
}

function Get-QwenSynthesisOutputFormat {
    return @{
        type = 'object'
        properties = @{
            answer = @{
                type = 'string'
                description = 'Complete natural final user-facing answer; never use the - sentinel.'
            }
            memory_note = @{
                type = 'string'
                maxLength = $script:MemoryNoteMaxChars
                description = 'New durable conversational delta; max 40 chars; use - when empty. L1 remains primarily about the user request; L2 memory_ops separately captures durable factual state accepted during synthesis.'
            }
            memory_ops = Get-LfoStructuredMemoryOperationSchema 6
        }
        required = @('answer', 'memory_note', 'memory_ops')
        additionalProperties = $false
    }
}

function Test-QwenInvalidFinalAnswer([AllowNull()][string]$Answer) {
    return ([string]::IsNullOrWhiteSpace($Answer) -or $Answer.Trim() -eq '-')
}

function Get-QwenAnswerRecoveryOutputFormat {
    return @{
        type = 'object'
        properties = @{
            answer = @{
                type = 'string'
                description = 'Complete natural user-facing answer.'
            }
        }
        required = @('answer')
        additionalProperties = $false
    }
}

function Get-QwenRecoveredAnswer([string]$Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return '' }
    try {
        $obj = $Content | ConvertFrom-Json -ErrorAction Stop
        $names = @($obj.PSObject.Properties.Name)
        if ($names.Count -ne 1 -or $names[0] -ne 'answer' -or
            $obj.answer -isnot [string]) {
            return ''
        }
        $answer = [string]$obj.answer
        if (Test-QwenInvalidFinalAnswer $answer) { return '' }
        return $answer.Trim()
    } catch {
        return ''
    }
}

function ConvertFrom-QwenStructuredContent(
    [string]$Content,
    [switch]$ExpectRoute
) {
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return [pscustomobject]@{
            Success = $false
            Route = 'UNKNOWN'
            Answer = ''
            MemoryNote = [pscustomobject]@{
                Raw = ''
                Text = ''
                ParseStatus = 'structured-missing'
            }
            MemoryOps = [pscustomobject]@{
                Valid = @()
                Rejected = @()
            }
        }
    }

    try {
        $obj = $Content | ConvertFrom-Json -ErrorAction Stop
        $answer = [string]$obj.answer
        $rawNote = [string]$obj.memory_note
        $note = Clean-MicroText $rawNote $script:MemoryNoteMaxChars
        $ops = ConvertFrom-LfoStructuredMemoryOps $obj.memory_ops 6

        $route = if ($ExpectRoute) { ([string]$obj.route).ToUpperInvariant() } else { 'LOCAL' }
        if ($ExpectRoute -and $route -notin @('LOCAL', 'FRONTIER')) {
            throw "Invalid structured route '$route'."
        }

        if ($route -eq 'FRONTIER') {
            # The routing pass must not create conversational memory; the final
            # post-frontier synthesis owns the note for this user turn.
            $note = ''
            $ops = [pscustomobject]@{
                Valid = @()
                Rejected = @()
            }
        }

        return [pscustomobject]@{
            Success = $true
            Route = $route
            Answer = $answer.Trim()
            MemoryNote = [pscustomobject]@{
                Raw = $rawNote
                Text = $note
                ParseStatus = $(if ([string]::IsNullOrWhiteSpace($note)) {
                    'structured-empty'
                } else {
                    'structured-complete'
                })
            }
            MemoryOps = $ops
        }
    } catch {
        return [pscustomobject]@{
            Success = $false
            Route = 'UNKNOWN'
            Answer = ''
            MemoryNote = [pscustomobject]@{
                Raw = $Content
                Text = ''
                ParseStatus = 'structured-malformed'
            }
            MemoryOps = [pscustomobject]@{
                Valid = @()
                Rejected = @()
            }
        }
    }
}

# Measure the existing request, never add a second model call.
function Invoke-LfoChatApi([string]$Phase, [string]$Body) {
    $phaseSw = [Diagnostics.Stopwatch]::StartNew()
    $response = $null
    $success = $false
    try {
        $response = Invoke-RestMethod -Uri "$BaseUri/api/chat" -Method Post `
            -ContentType 'application/json; charset=utf-8' -Body $Body -TimeoutSec 600
        $success = $true
        return $response
    } finally {
        $phaseSw.Stop()
        Add-LfoTurnPhase -Phase $Phase -WallSeconds $phaseSw.Elapsed.TotalSeconds `
            -Response $response -Success $success -InputChars $Body.Length
    }
}

function Invoke-QwenLocalApi {
    $bodyObj = @{
        model      = $Model
        messages   = @(Get-QwenConversationMessages)
        think      = $script:ThinkEnabled
        stream     = $false
        keep_alive = '5m'
        format     = (Get-QwenLocalOutputFormat)
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
    return Invoke-LfoChatApi -Phase 'local_generation' -Body $body
}

function Invoke-QwenAnswerRecovery([string]$Prompt) {
    # A rare answer-only retry. The first pass remains the sole source of
    # memory_note, and this call cannot route or invoke Codex.
    $systemText = 'Provide a complete user-facing answer to the most recent user message. Return only the answer field. If uncertain, say so plainly.'
    $memoryBlock = Get-LfoTurnMemoryBlock $Prompt
    if (-not [string]::IsNullOrWhiteSpace($memoryBlock)) {
        $systemText += [Environment]::NewLine + [Environment]::NewLine +
            'PERSISTENT CONVERSATION CONTEXT:' + [Environment]::NewLine + $memoryBlock
    }
    $recentMessages = @(Get-LfoTurnRecentMessages)
    if ($recentMessages.Count -eq 0 -or [string]$recentMessages[-1].role -ne 'user') {
        $recentMessages += @{ role = 'user'; content = $Prompt }
    }
    $messages = @(@{ role = 'system'; content = $systemText }) + $recentMessages
    $bodyObj = @{
        model      = $Model
        messages   = $messages
        think      = $script:ThinkEnabled
        stream     = $false
        keep_alive = '5m'
        format     = (Get-QwenAnswerRecoveryOutputFormat)
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
    return Invoke-LfoChatApi -Phase 'answer_recovery' -Body $body
}

function Invoke-QwenSynthesis([string]$OriginalPrompt, [string]$FrontierResult) {
    $synthesisSystem = Expand-RuntimePolicy $script:SynthesisSystemTemplate
    $l2EvidenceScope = @'
The evidence for L2 is the ORIGINAL USER REQUEST plus the FRONTIER RESULT supplied to this synthesis pass.
Treat the frontier as an external brain/input: interpret it, reconcile it with the request, and emit only durable factual state that you accept after synthesis.
Do not behave as a passive pipe and do not mechanically store every frontier detail.
'@
    $synthesisSystem += [Environment]::NewLine + [Environment]::NewLine +
        $script:L2StructuredMemoryTemplate.Replace('{{L2_EVIDENCE_SCOPE}}', $l2EvidenceScope.Trim())
    $memoryBlock = Get-LfoTurnMemoryBlock $OriginalPrompt
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
        format     = (Get-QwenSynthesisOutputFormat)
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
    return Invoke-LfoChatApi -Phase 'frontier_synthesis' -Body $body
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
    Start-LfoTurnTelemetry
    $script:LfoTurnContext = $null
    Start-LfoTurnContext $Prompt
    $policyReason = Get-FrontierPolicyReason $Prompt
    $route = $null
    $r = $null
    $frontierResult = $null
    $finalContent = $null
    $localRaw = $null
    $inlineMemoryNote = $null
    $inlineMemoryOps = [pscustomobject]@{
        Valid = @()
        Rejected = @()
    }
    $answerRecoveryUsed = $false
    $answerRecoveryReason = $null
    $answerRecoverySuccess = $null
    $explicitMemoryIntent = Test-ExplicitMemoryIntentPrompt $Prompt
    $memoryRecoveryUsed = $false
    $memoryRecoveryReason = $null
    $memoryRecoverySuccess = $null
    $memoryNoteSource = 'single-pass'

    if (-not [string]::IsNullOrWhiteSpace($policyReason)) {
        $route = 'FRONTIER'
        Write-Host ("`n[policy -> FRONTIER; reason={0}]" -f $policyReason) -ForegroundColor DarkCyan
    } else {
        # Qwen routes and answers in one schema-constrained generation. On
        # LOCAL the same generation also carries the bounded memory micro-note.
        $r = Invoke-QwenLocalApi
        Show-QwenThinking $r
        $candidate = Get-CleanQwenContent $r
        $localRaw = $candidate
        $structured = ConvertFrom-QwenStructuredContent $candidate -ExpectRoute

        if ($structured.Success) {
            $route = [string]$structured.Route
            if ($route -eq 'FRONTIER') {
                Write-Host "`n[Qwen route -> FRONTIER]" -ForegroundColor DarkCyan
            } else {
                Write-Host "`n[Qwen route -> LOCAL]" -ForegroundColor DarkGray
                $finalContent = [string]$structured.Answer
                $inlineMemoryNote = $structured.MemoryNote
                $inlineMemoryOps = $structured.MemoryOps
                if (Test-QwenInvalidFinalAnswer $finalContent) {
                    $cleanDeclarativeL2 = (Test-DeclarativeStateUpdatePrompt $Prompt) -and
                        @($inlineMemoryOps.Valid).Count -gt 0 -and
                        @($inlineMemoryOps.Rejected).Count -eq 0

                    $answerRecoveryUsed = $true
                    if ($cleanDeclarativeL2) {
                        $answerRecoveryReason = 'local-declarative-ack'
                        $answerRecoverySuccess = $true
                        $finalContent = 'OK.'
                        Write-Host "[Qwen answer invalid; using deterministic declarative acknowledgement.]" -ForegroundColor DarkGray
                    } else {
                        $answerRecoveryReason = if ($finalContent -eq '-') {
                            'local-sentinel'
                        } else {
                            'local-empty'
                        }
                        $answerRecoverySuccess = $false
                        Write-Host "[Qwen answer invalid; trying one LOCAL answer-only recovery.]" -ForegroundColor Yellow
                        try {
                            $recoveryResponse = Invoke-QwenAnswerRecovery $Prompt
                            Show-QwenThinking $recoveryResponse
                            $recoveredAnswer = Get-QwenRecoveredAnswer (Get-CleanQwenContent $recoveryResponse)
                            if ([string]$recoveryResponse.done_reason -ne 'length' -and
                                -not (Test-QwenInvalidFinalAnswer $recoveredAnswer)) {
                                $finalContent = $recoveredAnswer
                                $answerRecoverySuccess = $true
                            }
                        } catch {
                            Write-Host "[Qwen answer recovery failed.]" -ForegroundColor Yellow
                        }
                        if (-not $answerRecoverySuccess) {
                            $finalContent = 'The local model could not produce a usable answer. Please try again.'
                        }
                    }
                }
            }
        } else {
            # Structured output failure must never trigger a frontier call.
            Write-Host "`n[Qwen structured output malformed; fail-closed -> LOCAL]" -ForegroundColor Yellow
            $route = 'LOCAL'
            $finalContent = $candidate
            $inlineMemoryNote = $structured.MemoryNote
        }
    }

    if ($route -eq 'FRONTIER') {
        $memoryBlock = Get-LfoTurnMemoryBlock $Prompt
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
        $frontierSw = [Diagnostics.Stopwatch]::StartNew()
        $frontierSuccess = $false
        try {
            $frontierResult = Invoke-CodexReadOnly $codexPrompt
            $frontierSuccess = $true
            Write-Host ("[ask_codex -> Qwen; {0} characters]" -f $frontierResult.Length) -ForegroundColor DarkCyan
        } catch {
            $frontierResult = "ask_codex failed: $($_.Exception.Message)"
            Write-Host "[$frontierResult]" -ForegroundColor Yellow
        } finally {
            $frontierSw.Stop()
            Add-LfoTurnPhase -Phase 'frontier_handoff' -Kind 'frontier' `
                -WallSeconds $frontierSw.Elapsed.TotalSeconds `
                -Success $frontierSuccess -InputChars $codexPrompt.Length
        }

        if ($frontierResult -like 'ask_codex failed:*') {
            $finalContent = $frontierResult
        } else {
            $r = Invoke-QwenSynthesis $Prompt $frontierResult
            Show-QwenThinking $r
            $candidate = Get-CleanQwenContent $r
            $structuredSynthesis = ConvertFrom-QwenStructuredContent $candidate

            $invalidSynthesisAnswer = $structuredSynthesis.Success -and
                (Test-QwenInvalidFinalAnswer ([string]$structuredSynthesis.Answer))
            if (-not $structuredSynthesis.Success -or
                [string]$r.done_reason -eq 'length' -or
                (-not $invalidSynthesisAnswer -and
                    (Test-UnfinishedSynthesis $r ([string]$structuredSynthesis.Answer)))) {
                Write-Host "`n[Qwen synthesis did not complete cleanly; showing the frontier result directly.]" -ForegroundColor Yellow
                $finalContent = $frontierResult
                $inlineMemoryNote = $null
                $inlineMemoryOps = [pscustomobject]@{
                    Valid = @()
                    Rejected = @()
                }
            } elseif ($invalidSynthesisAnswer) {
                Write-Host "`n[Qwen synthesis answer invalid; showing the frontier result directly.]" -ForegroundColor Yellow
                $finalContent = $frontierResult
                $inlineMemoryNote = $structuredSynthesis.MemoryNote
                $inlineMemoryOps = $structuredSynthesis.MemoryOps
                $answerRecoveryUsed = $true
                $answerRecoveryReason = if ([string]$structuredSynthesis.Answer -eq '-') {
                    'synthesis-sentinel'
                } else {
                    'synthesis-empty'
                }
                $answerRecoverySuccess = $true
            } else {
                $finalContent = [string]$structuredSynthesis.Answer
                $inlineMemoryNote = $structuredSynthesis.MemoryNote
                $inlineMemoryOps = $structuredSynthesis.MemoryOps
            }
        }
    }

    # Explicit storage requests are a wrapper-level invariant. Normal implicit
    # memory remains single-pass; only an explicit request with an empty note
    # gets one bounded memory-only extraction retry.
    if ($script:MemoryEnabled -and $explicitMemoryIntent -and
        ($null -eq $inlineMemoryNote -or
            [string]::IsNullOrWhiteSpace([string]$inlineMemoryNote.Text))) {
        $memoryRecoveryUsed = $true
        $memoryRecoveryReason = 'explicit-intent-empty'
        $memoryRecoverySuccess = $false
        Write-Host "[Explicit memory intent; trying one memory-only recovery.]" -ForegroundColor Yellow

        try {
            $recoveredMemoryNote = Invoke-QwenMemoryNote `
                -TurnId 0 `
                -Prompt $Prompt `
                -FinalContent ([string]$finalContent) `
                -Route ([string]$route)

            $inlineMemoryNote = $recoveredMemoryNote
            $memoryNoteSource = 'explicit-intent-recovery'
            if (-not [string]::IsNullOrWhiteSpace([string]$recoveredMemoryNote.Text)) {
                $memoryRecoverySuccess = $true
            }
        } catch {
            Write-Host "[Qwen memory recovery failed.]" -ForegroundColor Yellow
        }

        if (-not $memoryRecoverySuccess) {
            $finalContent = 'The explicit memory request could not be persisted reliably. Please try again.'
        }
    }

    # The malformed-output fallback can also be a raw "-". Never expose or
    # persist it as an assistant answer.
    if (-not [string]::IsNullOrWhiteSpace($finalContent) -and
        $finalContent.Trim() -eq '-') {
        $answerRecoveryUsed = $true
        $answerRecoveryReason = 'raw-sentinel'
        $answerRecoverySuccess = $false
        $finalContent = 'The model did not produce a usable answer. Please try again.'
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
            -InlineMemoryNote $inlineMemoryNote `
            -InlineMemoryOps $inlineMemoryOps `
            -AnswerRecoveryUsed $answerRecoveryUsed `
            -AnswerRecoveryReason $answerRecoveryReason `
            -AnswerRecoverySuccess $answerRecoverySuccess `
            -ExplicitMemoryIntent $explicitMemoryIntent `
            -MemoryRecoveryUsed $memoryRecoveryUsed `
            -MemoryRecoveryReason $memoryRecoveryReason `
            -MemoryRecoverySuccess $memoryRecoverySuccess `
            -MemoryNoteSource $memoryNoteSource
    }
}


Initialize-PersistentMemory
$script:PolicyFingerprint = Get-PolicyFingerprint

Test-Ollama
Write-Host ""
Write-Host "Qwen local chat v9.4-dev4 (observable context assembly; optional L2 retrieval). Commands: /exit, /clear, /paste, /think on, /think off"
Write-Host "Frontier action: ask_codex (read-only, max 1 call per user turn)"
Write-Host "Routing: hard freshness/web gate + Qwen ROUTE: LOCAL/FRONTIER (no Ollama tools)"
Write-Host ("Thinking is now: {0} (controlled by the Ollama API think parameter)" -f $ThinkEnabled)
if ($script:MemoryEnabled) {
    Write-Host ("Persistent memory: ON; recent turns={0}; compact at pending>={1} notes or >={2} chars; note<={3} chars; state<={4} chars" -f `
        $script:MemoryRecentTurns, $script:MemoryCompactionMaxPendingNotes, $script:MemoryCompactionMaxPendingChars, $script:MemoryNoteMaxChars, $script:MemoryStateMaxChars)
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