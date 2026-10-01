# Persistent conversation memory, exact-data retrieval, and research logging for QwenChat.
# Dot-sourced by src/QwenChat.ps1. Qwen receives no filesystem tool.

function Initialize-QwenMemoryConfiguration(
    [Nullable[int]]$ContextLengthHint,
    [Nullable[int]]$MemoryRecentTurns,
    [Nullable[int]]$MemoryContextMaxChars,
    [Nullable[int]]$MemoryRecentContextMaxChars,
    [Nullable[int]]$MemoryRetrievalMaxChars,
    [Nullable[int]]$MemoryRetrievalMaxItems
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
    $script:MemoryRetrievalMaxChars = if ($null -ne $MemoryRetrievalMaxChars) {
        [int]$MemoryRetrievalMaxChars
    } else {
        [int]$script:Config.Memory.RetrievalMaxChars
    }
    $script:MemoryRetrievalMaxItems = if ($null -ne $MemoryRetrievalMaxItems) {
        [int]$MemoryRetrievalMaxItems
    } else {
        [int]$script:Config.Memory.RetrievalMaxItems
    }

    $script:MemoryCompactionEvery = [int]$script:Config.Memory.CompactionEvery
    $script:MemoryNoteMaxChars = [int]$script:Config.Memory.NoteMaxChars
    $script:MemoryStateMaxChars = [int]$script:Config.Memory.StateMaxChars
    $script:MemoryRetrievalScanMaxTurns = [int]$script:Config.Memory.RetrievalScanMaxTurns
    $script:ContextLengthHint = if ($null -ne $ContextLengthHint) { [int]$ContextLengthHint } else { 0 }

    $dataTemplate = [string]$script:Config.Memory.DataDirectory
    if ([string]::IsNullOrWhiteSpace($dataTemplate)) {
        $dataTemplate = '%LOCALAPPDATA%\LocalFrontierOrchestrator'
    }

    $script:DataRoot = [Environment]::ExpandEnvironmentVariables($dataTemplate)
    $script:StateDir = Join-Path $script:DataRoot 'state'
    $script:LogDir = Join-Path $script:DataRoot 'logs'
    $script:WorkingMemoryPath = Join-Path $script:StateDir 'working_memory.txt'
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

function New-DefaultRuntimeState {
    return [ordered]@{
        version = 2
        memory_schema = 2
        epoch = 1
        next_turn_id = 1
        completed_since_compaction = 0
    }
}

function Get-BoundedText([string]$Text, [int]$MaxChars) {
    if ([string]::IsNullOrWhiteSpace($Text) -or $MaxChars -le 0) { return '' }

    $clean = [regex]::Replace($Text.Trim(), '\s+', ' ')
    if ($clean.Length -le $MaxChars) { return $clean }
    if ($MaxChars -lt 16) { return $clean.Substring(0, $MaxChars) }

    $marker = ' ... '
    $head = [Math]::Max(1, [int](($MaxChars - $marker.Length) * 0.62))
    $tail = $MaxChars - $marker.Length - $head
    return $clean.Substring(0, $head) + $marker + $clean.Substring($clean.Length - $tail)
}

function Clean-MicroText([string]$Text, [int]$MaxChars) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $clean = $Text.Trim()
    $clean = [regex]::Replace($clean, '(?is)^\s*```(?:text)?\s*', '')
    $clean = [regex]::Replace($clean, '(?is)\s*```\s*$', '')
    $clean = [regex]::Replace($clean, '(?i)^\s*(MEM|NOTE|STATE)\s*:\s*', '')
    $clean = [regex]::Replace($clean, '[\r\n]+', ' ')
    $trimChars = [char[]]@(' ', '"', [char]39)
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim($trimChars)

    if ($clean -match '^(?i:none|null|empty|-)$') { return '' }
    if ($clean.Length -gt $MaxChars) {
        $clean = $clean.Substring(0, $MaxChars).Trim()
    }
    return $clean
}

function Test-ExplicitCorrectionPrompt([string]$Prompt) {
    if ([string]::IsNullOrWhiteSpace($Prompt)) { return $false }

    $patterns = @(
        '(?i)\b(oprava|opravujem|opravme|correction|correcting)\b',
        '(?i)\b(namiesto|instead\s+of|rather\s+than)\b',
        '(?i)\b(už\s+nie|uz\s+nie|no\s+longer)\b',
        '(?i)\b(nie|not)\b.{0,80}\b(ale|but)\b',
        '(?i)\b(zmen\p{L}*|switch(?:ed)?|replac\p{L}*)\b.{0,80}\b(na|to|with)\b'
    )

    foreach ($pattern in $patterns) {
        if ($Prompt -match $pattern) { return $true }
    }
    return $false
}

function Normalize-MemoryNoteForPrompt([string]$Note, [string]$Prompt) {
    if ([string]::IsNullOrWhiteSpace($Note)) { return '' }

    $clean = Clean-MicroText $Note $script:MemoryNoteMaxChars
    if ($clean -match '(?i)^\s*CORR\s+' -and
        -not (Test-ExplicitCorrectionPrompt $Prompt)) {
        $clean = [regex]::Replace($clean, '(?i)^\s*CORR\s+', '').Trim()
    }
    return $clean
}

function Get-WorkingMemoryRaw {
    if (-not (Test-Path -LiteralPath $script:WorkingMemoryPath)) { return '' }
    $raw = Get-Content -LiteralPath $script:WorkingMemoryPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace([string]$raw)) { return '' }
    return Clean-MicroText ([string]$raw) $script:MemoryStateMaxChars
}

function Get-PendingNoteRecords {
    if (-not (Test-Path -LiteralPath $script:PendingNotesPath)) { return @() }

    $result = @()
    foreach ($line in (Get-Content -LiteralPath $script:PendingNotesPath -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            $note = Clean-MicroText ([string]$row.note) $script:MemoryNoteMaxChars
            if (-not [string]::IsNullOrWhiteSpace($note)) {
                $result += [pscustomobject]@{
                    turn_id = [int]$row.turn_id
                    timestamp = [string]$row.timestamp
                    note = $note
                }
            }
        } catch {
        }
    }
    return @($result)
}

function Get-PendingNotesText {
    $pending = @(Get-PendingNoteRecords)
    if ($pending.Count -eq 0) { return '' }

    $parts = @()
    foreach ($row in $pending) {
        # Preserve note order but keep internal turn IDs out of the semantic
        # compaction input. turn_id remains available in pending JSONL/logs.
        $parts += [string]$row.note
    }
    return ($parts -join ' | ')
}

function Clear-PendingNotes {
    Write-TextUtf8NoBom $script:PendingNotesPath ''
}

function Get-ConversationRows {
    if (-not (Test-Path -LiteralPath $script:LogDir)) { return @() }

    $rows = @()
    $files = @(
        Get-ChildItem -LiteralPath $script:LogDir -Filter 'conversation-*.jsonl' -File -ErrorAction SilentlyContinue |
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
                $rows += $row
            }
        }
    }

    if ($script:MemoryRetrievalScanMaxTurns -gt 0 -and
        $rows.Count -gt $script:MemoryRetrievalScanMaxTurns) {
        $rows = @($rows | Select-Object -Last $script:MemoryRetrievalScanMaxTurns)
    }
    return @($rows)
}

function ConvertTo-SearchText([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }

    $formD = $Text.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $formD.ToCharArray()) {
        $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function Get-SearchTermsFromText([string]$Text) {
    $source = ConvertTo-SearchText $Text

    $stop = @(
        'ako','aky','aka','ake','a','aj','ale','alebo','by','co','je','som','sa','si','sme','ste',
        'ten','ta','to','tie','tento','tato','toto','tam','tu','na','do','od','po','pre','pri','s',
        'so','z','zo','v','vo','k','ku','u','o','uz','este','mi','ma','mu','ho','ich','ktory',
        'ktora','ktore','kolko','what','which','that','this','the','and','or','is','are','was',
        'were','to','of','in','on','for','with','about','it','we','you','i','our','my'
    )

    $seen = @{}
    $terms = @()
    foreach ($token in ($source -split '[^\p{L}\p{N}._+-]+')) {
        if ([string]::IsNullOrWhiteSpace($token)) { continue }
        if ($token.Length -lt 3 -and $token -notmatch '^\d+$') { continue }
        if ($stop -contains $token) { continue }
        if (-not $seen.ContainsKey($token)) {
            $seen[$token] = $true
            $terms += $token
        }
    }
    return @($terms)
}

function Get-RetrievalQueryTerms([string]$Query) {
    $direct = @(Get-SearchTermsFromText $Query)
    if ($direct.Count -ge 2) {
        return @($direct | Select-Object -First 24)
    }

    $state = Get-WorkingMemoryRaw
    $pending = Get-PendingNotesText
    $augmented = @(Get-SearchTermsFromText ("$Query $state $pending"))

    return @($augmented | Select-Object -First 24)
}

function Get-RelevantDataContext([string]$Query) {
    if (-not $script:MemoryEnabled -or
        [string]::IsNullOrWhiteSpace($Query) -or
        $script:MemoryRetrievalMaxChars -le 0 -or
        $script:MemoryRetrievalMaxItems -le 0) {
        return ''
    }

    $rows = @(Get-ConversationRows)
    if ($rows.Count -le $script:MemoryRecentTurns) { return '' }

    $olderCount = $rows.Count - $script:MemoryRecentTurns
    $older = @($rows | Select-Object -First $olderCount)
    $terms = @(Get-RetrievalQueryTerms $Query)
    if ($terms.Count -eq 0) { return '' }

    $scored = @()
    foreach ($row in $older) {
        $u = ConvertTo-SearchText ([string]$row.user)
        $a = ConvertTo-SearchText ([string]$row.assistant)
        $score = 0

        foreach ($term in $terms) {
            $escaped = [regex]::Escape($term)
            if ($u -match $escaped) { $score += 3 }
            if ($a -match $escaped) { $score += 1 }
        }

        if ($score -gt 0) {
            $scored += [pscustomobject]@{
                score = $score
                turn_id = [int]$row.turn_id
                row = $row
            }
        }
    }

    if ($scored.Count -eq 0) { return '' }

    $best = @(
        $scored |
        Sort-Object @{Expression='score';Descending=$true}, @{Expression='turn_id';Descending=$true} |
        Select-Object -First $script:MemoryRetrievalMaxItems
    )

    $budget = $script:MemoryRetrievalMaxChars
    $perItem = [Math]::Max(220, [int]($budget / [Math]::Max(1, $best.Count)))
    $parts = @()
    $used = 0

    foreach ($hit in $best) {
        $row = $hit.row
        $uBudget = [Math]::Max(120, [int]($perItem * 0.62))
        $aBudget = [Math]::Max(80, $perItem - $uBudget - 30)
        $uText = Get-BoundedText ([string]$row.user) $uBudget
        $aText = Get-BoundedText ([string]$row.assistant) $aBudget
        $snippet = "T$($hit.turn_id) U:$uText A:$aText"

        if (($used + $snippet.Length) -gt $budget) {
            $remaining = $budget - $used
            if ($remaining -ge 120) {
                $parts += (Get-BoundedText $snippet $remaining)
            }
            break
        }

        $parts += $snippet
        $used += $snippet.Length + 1
    }

    return ($parts -join "`n")
}

function Get-MemoryContextBlock([string]$Query = '') {
    if (-not $script:MemoryEnabled) { return '' }

    $state = Get-WorkingMemoryRaw
    $pending = Get-PendingNotesText
    $core = "STATE:$state`nPENDING:$pending"

    if ($script:MemoryContextMaxChars -gt 0 -and
        $core.Length -gt $script:MemoryContextMaxChars) {
        $core = Get-BoundedText $core $script:MemoryContextMaxChars
    }

    $retrieved = Get-RelevantDataContext $Query
    if (-not [string]::IsNullOrWhiteSpace($retrieved)) {
        return "$core`nRELEVANT OLD DATA:`n$retrieved"
    }

    return $core
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

function Get-CurrentUserPrompt {
    $last = @(
        $script:Messages |
        Where-Object { $_.role -eq 'user' } |
        Select-Object -Last 1
    )
    if ($last.Count -eq 0) { return '' }
    return [string]$last[0].content
}

function Get-QwenConversationMessages {
    $query = Get-CurrentUserPrompt
    $systemText = Get-OrchestratorSystemPrompt
    $memoryBlock = Get-MemoryContextBlock $query

    if (-not [string]::IsNullOrWhiteSpace($memoryBlock)) {
        $systemText += @"

PERSISTENT CONVERSATION CONTEXT:
$memoryBlock

STATE and PENDING are lossy orientation memory. RELEVANT OLD DATA contains verbatim historical snippets.
Use them to resolve references and preserve continuity. Repetition increases relevance, never factual certainty.
When historical values conflict, prefer explicit later corrections and state uncertainty if needed.
"@
    }

    $systemText += @"

STRUCTURED OUTPUT — FINAL RULES:
Treat answer and memory_note as independent fields.

For route LOCAL:
- answer must fully answer the CURRENT USER REQUEST in the normal way.
- memory_note must capture only the NEW durable delta introduced by the CURRENT USER TURN, even when that delta is unrelated to the requested answer.
- Do not shorten, redirect, or reshape answer merely to make memory_note easier.
- Use "-" when the current user turn adds no durable user state.
- Ignore old STATE, PENDING, RELEVANT OLD DATA, and older turns when deciding memory_note.
- If the current user turn explicitly corrects or replaces an earlier value, prefix memory_note with "CORR " and include enough target/key identity plus the new/current value to make the replacement unambiguous.

For route FRONTIER, answer must be empty and memory_note must be "-".
"@

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
    [string]$Route
) {
    $userText = Get-BoundedText $Prompt ([int]$script:Config.Memory.NoteInputUserMaxChars)
    $answerText = Get-BoundedText $FinalContent ([int]$script:Config.Memory.NoteInputAssistantMaxChars)

    $memoryInput = @"
ROUTE:$Route
NEW USER TURN:
$userText

ASSISTANT OUTCOME (secondary evidence only):
$answerText
"@

    $r = Invoke-QwenMemoryCall `
        (Expand-RuntimePolicy $script:MemoryNoteTemplate) `
        $memoryInput `
        ([int]$script:Config.Memory.NoteNumPredict)

    $raw = [string]$r.message.content
    $note = Clean-MicroText $raw $script:MemoryNoteMaxChars

    return [pscustomobject]@{
        Raw = $raw
        Text = $note
        EvalCount = $r.eval_count
        EvalDuration = $r.eval_duration
    }
}

function Invoke-MemoryCompaction {
    $pending = @(Get-PendingNoteRecords)
    if ($pending.Count -eq 0) { return $true }

    $state = Get-WorkingMemoryRaw
    $notes = Get-PendingNotesText

    $memoryInput = @"
STATE:$state
NOTES:$notes
"@

    $r = Invoke-QwenMemoryCall `
        (Expand-RuntimePolicy $script:MemoryCompactionTemplate) `
        $memoryInput `
        ([int]$script:Config.Memory.CompactionNumPredict)

    $raw = [string]$r.message.content
    $newState = Clean-MicroText $raw $script:MemoryStateMaxChars
    Write-TextUtf8NoBom $script:WorkingMemoryPath $newState
    Clear-PendingNotes
    return $true
}

function Get-PolicyFingerprint {
    $parts = @()
    foreach ($name in @(
        'orchestrator-system.txt',
        'synthesis-system.txt',
        'frontier-subagent.txt',
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

    $turns = @(Get-ConversationRows | Select-Object -Last $script:MemoryRecentTurns)

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
        Write-TextUtf8NoBom $script:WorkingMemoryPath ''
    }

    if (-not (Test-Path -LiteralPath $script:RuntimeStatePath)) {
        $script:RuntimeState = [pscustomobject](New-DefaultRuntimeState)
        Write-JsonAtomic $script:RuntimeStatePath $script:RuntimeState
    } else {
        try {
            $script:RuntimeState = Get-Content `
                -LiteralPath $script:RuntimeStatePath `
                -Raw `
                -Encoding UTF8 |
                ConvertFrom-Json
        } catch {
            $script:RuntimeState = [pscustomobject](New-DefaultRuntimeState)
        }
    }

    $needsMigration = $true
    if ($script:RuntimeState.PSObject.Properties.Name -contains 'memory_schema') {
        $needsMigration = ([int]$script:RuntimeState.memory_schema -lt 2)
    }

    if ($needsMigration) {
        if ($script:RuntimeState.PSObject.Properties.Name -contains 'memory_schema') {
            $script:RuntimeState.memory_schema = 2
        } else {
            $script:RuntimeState | Add-Member -NotePropertyName memory_schema -NotePropertyValue 2
        }
        $script:RuntimeState.completed_since_compaction = 0
        Write-TextUtf8NoBom $script:WorkingMemoryPath ''
        Clear-PendingNotes
        Write-JsonAtomic $script:RuntimeStatePath $script:RuntimeState
    } elseif (-not (Test-Path -LiteralPath $script:PendingNotesPath)) {
        Clear-PendingNotes
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

    Write-TextUtf8NoBom $script:WorkingMemoryPath ''
    Clear-PendingNotes
    Save-RuntimeState

    if ([bool]$script:Config.ResearchLogging.Enabled) {
        Append-JsonLine (Get-MonthlyLogPath 'trace') ([ordered]@{
            event = 'clear'
            timestamp = (Get-Date).ToString('o')
            epoch = [int]$script:RuntimeState.epoch
            note = 'Active memory/context cleared; historical logs retained.'
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
    [double]$AnswerSeconds,
    $InlineMemoryNote
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
        Get-MemoryContextBlock $Prompt
    } else {
        ''
    }
    $retrievedBefore = if ($script:MemoryEnabled) {
        Get-RelevantDataContext $Prompt
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

    $memoryNote = $InlineMemoryNote
    $memoryError = $null
    $compacted = $false
    $memorySw = [System.Diagnostics.Stopwatch]::StartNew()

    if ($script:MemoryEnabled) {
        try {
            $modelNoteText = if ($null -ne $memoryNote) {
                [string]$memoryNote.Text
            } else {
                ''
            }
            $noteText = Normalize-MemoryNoteForPrompt $modelNoteText $Prompt

            if (-not [string]::IsNullOrWhiteSpace($noteText)) {
                Append-JsonLine $script:PendingNotesPath ([ordered]@{
                    turn_id = $turnId
                    timestamp = (Get-Date).ToString('o')
                    note = $noteText
                })
            }

            # Preserve v9.1.3 cadence: every persisted turn advances the
            # compaction counter, even when the current micro-note is empty.
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
            $memoryError = "single-pass memory persistence failed: $($_.Exception.Message)"
        }
    }

    $memorySw.Stop()

    $memoryAfter = if ($script:MemoryEnabled) {
        Get-MemoryContextBlock $Prompt
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
            retrieved_old_data = $retrievedBefore
            bias_signals = @()
        }

        $trace['memory_note_source'] = 'single-pass'
        if ($null -ne $memoryNote) {
            $trace['memory_note'] = $noteText
            $trace['memory_note_model'] = [string]$memoryNote.Text
            $trace['memory_note_parse_status'] = [string]$memoryNote.ParseStatus
        }

        if ([bool]$script:Config.ResearchLogging.IncludeRawText) {
            $trace['user'] = $Prompt
            $trace['local_raw'] = $LocalRaw
            $trace['frontier_raw'] = $FrontierResult
            $trace['final_answer'] = $FinalContent
            $trace['memory_note_raw'] = if ($null -ne $memoryNote) {
                [string]$memoryNote.Raw
            } else {
                $null
            }
        }

        if ([bool]$script:Config.ResearchLogging.IncludeMemorySnapshots) {
            $trace['memory_before'] = $memoryBefore
            $trace['memory_after'] = $memoryAfter
        }

        Append-JsonLine (Get-MonthlyLogPath 'trace') $trace
    }

    if ($script:MemoryEnabled) {
        if ($compacted) {
            $state = 'micro-note saved + compacted'
        } elseif ($memoryError) {
            $state = $memoryError
        } else {
            $state = 'micro-note saved'
        }

        Write-Host (
            "[memory: {0}; {1:n2}s]" -f $state, $memorySw.Elapsed.TotalSeconds
        ) -ForegroundColor DarkGray
    }
}
