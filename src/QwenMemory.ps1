# Persistent conversation memory and research logging for QwenChat.
# Dot-sourced by src/QwenChat.ps1. Qwen receives no filesystem tool.

function Initialize-QwenMemoryConfiguration(
    [Nullable[int]]$ContextLengthHint,
    [Nullable[int]]$MemoryRecentTurns,
    [Nullable[int]]$MemoryContextMaxChars,
    [Nullable[int]]$MemoryRecentContextMaxChars
) {
    $script:MemoryEnabled = [bool]$script:Config.Memory.Enabled
    $script:MemoryRecentTurns = if ($null -ne $MemoryRecentTurns) {
        [int]$MemoryRecentTurns
    } else {
        [int]$script:Config.Memory.RecentTurns
    }
    $script:MemoryContextMaxChars = if ($null -ne $MemoryContextMaxChars) {
        [int]$MemoryContextMaxChars
    } else {
        [int]$script:Config.Memory.ContextMaxChars
    }
    $script:MemoryRecentContextMaxChars = if ($null -ne $MemoryRecentContextMaxChars) {
        [int]$MemoryRecentContextMaxChars
    } else {
        [int]$script:Config.Memory.RecentContextMaxChars
    }
    $script:MemoryCompactionEvery = [int]$script:Config.Memory.CompactionEvery
    $script:ContextLengthHint = if ($null -ne $ContextLengthHint) { [int]$ContextLengthHint } else { 0 }

    $dataTemplate = [string]$script:Config.Memory.DataDirectory
    if ([string]::IsNullOrWhiteSpace($dataTemplate)) {
        $dataTemplate = '%LOCALAPPDATA%\LocalFrontierOrchestrator'
    }

    $script:DataRoot = [Environment]::ExpandEnvironmentVariables($dataTemplate)
    $script:StateDir = Join-Path $script:DataRoot 'state'
    $script:LogDir = Join-Path $script:DataRoot 'logs'
    $script:WorkingMemoryPath = Join-Path $script:StateDir 'working_memory.json'
    $script:PendingNotesPath = Join-Path $script:StateDir 'pending_notes.jsonl'
    $script:RuntimeStatePath = Join-Path $script:StateDir 'runtime_state.json'
    $script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
}

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
    $pendingBudget = [Math]::Max(
        400,
        $maxChars - $workingBudget - $header1.Length - $header2.Length - 40
    )

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

Use this memory to resolve references and preserve continuity. It is context, not proof.
Frequency or repetition increases conversational relevance, never factual certainty.
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
    $clean = [regex]::Replace($clean, '(?is)\s*```\s*$', '')

    $start = $clean.IndexOf('{')
    $end = $clean.LastIndexOf('}')
    if ($start -ge 0 -and $end -gt $start) {
        $clean = $clean.Substring($start, $end - $start + 1)
    }

    return ($clean | ConvertFrom-Json)
}

function Invoke-QwenMemoryCall(
    [string]$SystemPrompt,
    [string]$UserPrompt,
    [int]$NumPredict
) {
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
        -ContentType 'application/json; charset=utf-8' `
        -Body $body `
        -TimeoutSec 600
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

    if (-not [string]::IsNullOrWhiteSpace($frontierForNote) -and
        $frontierForNote.Length -gt $frontierLimit) {
        $frontierForNote = $frontierForNote.Substring(0, $frontierLimit) + ' ...[truncated]'
    }
    if ([string]::IsNullOrWhiteSpace($frontierForNote)) {
        $frontierForNote = '(none)'
    }

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
        $parsed | Add-Member `
            -NotePropertyName updated_at `
            -NotePropertyValue ((Get-Date).ToString('o'))
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
    $files = @(
        Get-ChildItem -LiteralPath $script:LogDir `
            -Filter 'conversation-*.jsonl' `
            -File `
            -ErrorAction SilentlyContinue |
        Sort-Object Name
    )

    foreach ($f in $files) {
        foreach ($line in (Get-Content -LiteralPath $f.FullName -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
            } catch {
                continue
            }

            if ([string]$row.event -eq 'turn' -and
                [int]$row.epoch -eq [int]$script:RuntimeState.epoch) {
                $turns += $row
            }
        }
    }

    $turns = @($turns | Select-Object -Last $script:MemoryRecentTurns)

    foreach ($t in $turns) {
        $script:Messages += @{
            role = 'user'
            content = [string]$t.user
        }

        $assistantStored = "ROUTE: $([string]$t.route)`n$([string]$t.assistant)"
        $script:Messages += @{
            role = 'assistant'
            content = $assistantStored
        }
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
        $script:RuntimeState = Get-Content `
            -LiteralPath $script:RuntimeStatePath `
            -Raw `
            -Encoding UTF8 |
            ConvertFrom-Json
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
    if (-not $script:MemoryEnabled -and
        -not [bool]$script:Config.ResearchLogging.Enabled) {
        return
    }

    if ($script:MemoryEnabled) {
        $turnId = [int]$script:RuntimeState.next_turn_id
        $epoch = [int]$script:RuntimeState.epoch
    } else {
        $turnId = 0
        $epoch = 0
    }

    $timestamp = (Get-Date).ToString('o')
    $memoryBefore = if ($script:MemoryEnabled) {
        Get-MemoryContextBlock
    } else {
        ''
    }

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
            $memoryNote = Invoke-QwenMemoryNote `
                $turnId `
                $Prompt `
                $FinalContent `
                $Route `
                $FrontierResult

            Append-JsonLine $script:PendingNotesPath ([ordered]@{
                turn_id = $turnId
                timestamp = (Get-Date).ToString('o')
                note = $memoryNote.Parsed
            })

            $script:RuntimeState.completed_since_compaction =
                [int]$script:RuntimeState.completed_since_compaction + 1

            if ([int]$script:RuntimeState.completed_since_compaction -ge
                $script:MemoryCompactionEvery) {
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

    $memoryAfter = if ($script:MemoryEnabled) {
        Get-MemoryContextBlock
    } else {
        ''
    }

    if ([bool]$script:Config.ResearchLogging.Enabled) {
        $performance = $null
        if ($null -ne $Response) {
            $performance = [ordered]@{
                prompt_eval_count = $Response.prompt_eval_count
                prompt_eval_duration = $Response.prompt_eval_duration
                eval_count = $Response.eval_count
                eval_duration = $Response.eval_duration
                done_reason = [string]$Response.done_reason
            }
        }

        $biasSignals = @()
        if ($null -ne $memoryNote -and
            $null -ne $memoryNote.Parsed.bias_signals) {
            $biasSignals = $memoryNote.Parsed.bias_signals
        }

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
            performance = $performance
            bias_signals = $biasSignals
        }

        if ([bool]$script:Config.ResearchLogging.IncludeRawText) {
            $trace.user = $Prompt
            $trace.local_raw = $LocalRaw
            $trace.frontier_raw = $FrontierResult
            $trace.final_answer = $FinalContent
            $trace.memory_note_raw = if ($null -ne $memoryNote) {
                $memoryNote.Raw
            } else {
                $null
            }
        }

        if ([bool]$script:Config.ResearchLogging.IncludeMemorySnapshots) {
            $trace.memory_before = $memoryBefore
            $trace.memory_after = $memoryAfter
        }

        Append-JsonLine (Get-MonthlyLogPath 'trace') $trace
    }

    if ($script:MemoryEnabled) {
        if ($compacted) {
            $state = 'note saved + compacted'
        } elseif ($memoryError) {
            $state = $memoryError
        } else {
            $state = 'note saved'
        }

        Write-Host (
            "[memory: {0}; {1:n2}s]" -f $state, $memorySw.Elapsed.TotalSeconds
        ) -ForegroundColor DarkGray
    }
}
