param(
    [string]$Model = 'qwen3.5:4b-q4_K_M',
    [switch]$Think,
    [int]$CodexTimeoutSec = 300
)

$ErrorActionPreference = 'Stop'
$BaseUri = 'http://127.0.0.1:11434'
$ThinkEnabled = [bool]$Think

function Get-OrchestratorSystemPrompt {
    $currentLocalDate = (Get-Date).ToString('yyyy-MM-dd')
    return @"
You are Qwen, the local first-line assistant and routing model. Answer in the user's language.
Language policy:
- Answer in the language used by the user unless the user explicitly requests another language.
- Preserve the user's language across frontier synthesis instead of switching to a statistically similar language.

Authoritative runtime date: $currentLocalDate.
Treat this date as ground truth. Do not infer today's date from model memory.

For every normal user turn that reaches you, begin the final response with exactly one routing marker:

ROUTE: LOCAL
Use LOCAL when stable local knowledge and reasoning are sufficient. Ordinary explanations, mathematics, stable technical knowledge, writing, translation, summarization of supplied text, and general factual knowledge are LOCAL. Do not choose FRONTIER merely because a question is factual.

ROUTE: FRONTIER
Use FRONTIER when the task materially requires current/recent/changing real-world information, live web research, information unavailable from the supplied context, specialist knowledge you are not confident about, substantially stronger reasoning, independent external verification, or exact specifications of a named external product that are not supplied in the conversation. If you choose FRONTIER, output only the line "ROUTE: FRONTIER" and nothing else.

If you choose LOCAL, put the answer immediately after the marker. Do not mention routing or tools in the answer itself.

When answering LOCAL, be epistemically conservative. Do not invent real-world facts to satisfy a premise. If the subject is fictional, mythical, ambiguous, underspecified, or depends on a particular fictional canon, say so explicitly and answer conditionally where useful. Do not invent a taxonomic or semantic distinction between word forms without evidence.

"@
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
    # The system routing prompt must survive trimming; keep the last 11 non-system messages.
    if ($script:Messages.Count -gt 12) {
        $system = @($script:Messages | Where-Object { $_.role -eq 'system' } | Select-Object -First 1)
        $tail = @($script:Messages | Where-Object { $_.role -ne 'system' } | Select-Object -Last 11)
        $script:Messages = @($system + $tail)
    }
}


function Get-FrontierPolicyReason([string]$Prompt) {
    if ([string]::IsNullOrWhiteSpace($Prompt)) { return $null }

    # Exact model-specific product specs are an external-source capability.
    # Keep this intentionally narrow: a spec request plus a product/model signal.
    $productSpecPattern = '(?i)(\bpresn\p{L}*\b|\bexact(?:ly)?\b|\bšpecifikáci\p{L}*\b|\bspecification\p{L}*\b|\bspecs?\b|\brozmer\p{L}*\b|\bdimensions?\b|\bpríkon\p{L}*\b|\bpower\s+(?:draw|consumption|limit)\b|\bTBP\b|\bTDP\b|\bnapájac\p{L}*\s+konektor\p{L}*\b|\bpower\s+connector\p{L}*\b|\bhmotnos\p{L}*\b|\bweight\b)'
    $productIdentityPattern = '(?i)(\b(?:ASRock|NVIDIA|AMD|Intel|ASUS|MSI|Gigabyte|Lenovo|Dell|HP|Acer|Apple|Samsung|Sony|Canon|Nikon|Corsair|Crucial|Kingston|Western\s+Digital|WD|Seagate|Sapphire|PowerColor|XFX|PNY|Zotac|Palit|Gainward)\b|\b(?:RTX|GTX|RX|Arc|Ryzen|Core|GeForce|Radeon|iPhone|Galaxy|ThinkPad)\b|\b[A-Z]{1,6}\d{2,5}[A-Z0-9._+-]*\b)'
    if ($Prompt -match $productSpecPattern -and $Prompt -match $productIdentityPattern) {
        return 'named-product-specification'
    }

    # Hard capability gate: only strong, low-ambiguity signals.
    # Ambiguous cases remain Qwen's own route-marker decision.
    $rules = @(
        @{
            Reason = 'explicit-frontier-or-web'
            Pattern = '(?i)(\bask[_ -]?codex\b|\bdopyt\p{L}*\s+na\s+frontier\b|\bpouži\p{L}*[^.!?]{0,60}\bfrontier\b|\bopýtaj\p{L}*[^.!?]{0,40}\bcodex\b|\buse\s+(?:the\s+)?(?:frontier|codex)\b|\bask\s+(?:the\s+)?(?:frontier|codex)\b|\bsearch the web\b|\bbrowse the web\b|\blook it up online\b|\bna webe\b|\bcez web\b|\bna internete\b|\bonline zdroj\p{L}*\b|\bvyhľadaj\p{L}*\s+(?:na\s+)?webe\b|\bzisti\p{L}*\s+(?:na\s+)?webe\b)'
        },
        @{
            Reason = 'explicit-freshness'
            Pattern = '(?i)(\bdnes\b|\bvčera\b|\bzajtra\b|\bpráve teraz\b|\btento týždeň\b|\btento mesiac\b|\bnajnovš\p{L}*\b|\bnajčerstv\p{L}*\b|\blatest\b|\bnewest\b|\btoday\b|\byesterday\b|\btomorrow\b|\bthis week\b|\bthis month\b|\bas of\b|\bup[- ]to[- ]date\b)'
        },
        @{
            Reason = 'live-state'
            Pattern = '(?i)(\bčo sa (?:práve |teraz |aktuálne )?deje\b|\bwhat(?:''s| is) happening\b|\bpočasie\b|\bpredpoveď počasia\b|\bweather\b|\bforecast\b|\blive score\b|\bvýsledok zápasu\b|\bexchange rate\b)'
        },
        @{
            Reason = 'current-version-or-release'
            Pattern = '(?i)(\baktuáln\p{L}*\s+(?:stabiln\p{L}*\s+)?verzi\p{L}*\b|\baktuáln\p{L}*\s+release\b|\bcurrent\s+(?:stable\s+)?version\b|\bcurrent\s+release\b|\bnovš\p{L}*\s+verzi\p{L}*\b)'
        },
        @{
            Reason = 'url-needs-fetch'
            Pattern = '(?i)https?://'
        }
    )

    foreach ($rule in $rules) {
        if ($Prompt -match $rule.Pattern) {
            return [string]$rule.Reason
        }
    }
    return $null
}

function Get-HardGateContext([string]$Prompt) {
    # For a self-contained freshness/web request, send only the current request to Codex.
    # Add prior context only for short, clearly anaphoric follow-ups.
    if ([string]::IsNullOrWhiteSpace($Prompt) -or $Prompt.Length -gt 220) {
        return ''
    }

    $followUpPattern = '(?i)^\s*(a\s+)?(čo|co|ako|a\s+čo|a\s+co|toto|to|tam|ten|tá|ta|tú|tu|tie|rovnako|oproti tomu|what about|and what|this|that|it|same|there)\b'
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
    if ($text.Length -gt 1800) {
        $text = $text.Substring($text.Length - 1800)
    }
    return $text.Trim()
}

function Get-CodexProcessSpec {
    $cmd = Get-Command codex -ErrorAction Stop | Select-Object -First 1
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
    if ($Prompt.Length -gt 12000) {
        throw 'ask_codex prompt is too long (MVP maximum: 12000 characters).'
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

        $currentLocalDate = (Get-Date).ToString('yyyy-MM-dd')
        $delegatedPrompt = @"
You are being called as a read-only frontier subagent by a local Qwen orchestrator.
Authoritative local date supplied by the wrapper: $currentLocalDate.
Live web search is enabled. If the task asks about current, recent, time-sensitive, or changing real-world information, use live web search instead of relying on model memory. Prefer current authoritative sources and make relevant dates explicit when freshness matters. For non-current tasks, use web search only when it materially improves the answer.

Answer the task directly and concisely with enough factual/source context for Qwen to synthesize the final response. Do not modify files. Do not commit, push, or otherwise change git state. Do not ask for permission to make changes.

TASK:
$Prompt
"@
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
            num_predict = $(if ($script:ThinkEnabled) { 2048 } else { 1024 })
            temperature = 0.2
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 12 -Compress
    return Invoke-RestMethod -Uri "$BaseUri/api/chat" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
}

function Invoke-QwenSynthesis([string]$OriginalPrompt, [string]$FrontierResult) {
    $currentLocalDate = (Get-Date).ToString('yyyy-MM-dd')
    $synthesisSystem = @"
You are Qwen performing the final user-facing synthesis after an external frontier subagent has already researched the task.

Authoritative runtime date: $currentLocalDate.
Answer the ORIGINAL USER REQUEST in the user's language.
Language policy:
- Answer in the language used by the user unless the user explicitly requests another language.
- Preserve the user's language across frontier synthesis instead of switching to a statistically similar language.

Treat FRONTIER RESULT as the primary factual substrate for externally researched or current information. Be a useful editor and explainer, not a passive pipe, but preserve its factual payload carefully.

Rules:
- Preserve concrete researched facts such as names, model identifiers, numbers, dimensions, dates, prices, capacities, interfaces, quotations, caveats, uncertainty, and source links unless the FRONTIER RESULT itself clearly marks them as uncertain.
- Do not silently replace a concrete fact from FRONTIER RESULT with a conflicting fact from your own model memory.
- If you notice a plausible conflict or suspect an error, preserve the distinction and state the uncertainty instead of silently "correcting" it.
- You may reorganize, summarize, clarify, connect ideas, and add concise explanatory context where useful.
- You may add stable background knowledge, reasoning, or interpretation when it genuinely helps, but do not present such additions as if they came from FRONTIER RESULT or its cited sources.
- Do not strengthen tentative claims into certainty and do not invent missing product specifications.
- Preserve useful source links and keep them attached to the claims they support.
- Do not plan, discuss routing, request another tool, or second-guess the runtime date because it is newer than your training data.
- Return only the final user-facing answer.

"@

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
            num_predict      = $(if ($script:ThinkEnabled) { 3072 } else { 1536 })
            temperature      = 0.25
            presence_penalty = 0.15
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

    if ($Response.eval_count -ge 1500 -and
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
}


Test-Ollama
Write-Host ""
Write-Host "Qwen local chat. Commands: /exit, /clear, /paste, /think on, /think off"
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