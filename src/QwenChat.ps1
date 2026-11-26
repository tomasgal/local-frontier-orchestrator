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

# Parse only the current explicit user sentence, never the retrieved evidence.
# This module is intentionally pure and has no side effects on import.
$mixedEvidenceModule = Join-Path $PSScriptRoot 'LfoMixedTurnEvidence.ps1'
if (-not (Test-Path -LiteralPath $mixedEvidenceModule)) {
    throw "Mixed-turn evidence validator missing: $mixedEvidenceModule"
}
. $mixedEvidenceModule

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

# L3 modules are loaded unconditionally but remain inert unless Memory.L3ReadEnabled is true.
foreach ($l3ModuleName in @('LfoL3Store.ps1','LfoL3Planner.ps1','LfoL3Runtime.ps1','LfoL3Indexer.ps1')) {
    $l3Module = Join-Path $PSScriptRoot $l3ModuleName
    if (-not (Test-Path -LiteralPath $l3Module)) { throw "L3 module not found: $l3Module" }
    . $l3Module
}

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

# UMA-only mitigation for premature closure of JSON answer strings.
# It is not a completeness detector and must not alter verbatim user data.
function Add-LfoStructuredAnswerPolicy([string]$SystemText,[string]$Device){
    if($Device -ne 'UMA'){return $SystemText}
    return $SystemText+[Environment]::NewLine+[Environment]::NewLine+@'
Structured answer writing:
- Finish every requested section and complete the final sentence before closing the JSON answer string.
- Avoid decorative quotation marks around ordinary terms in explanatory prose; write the term directly instead.
- When quotation marks are necessary (verbatim quotations, source text, code or requested formatting), preserve the exact intended content. Inside the JSON answer string, encode literal ASCII double quotes as \" and backslashes as \\. Do not replace punctuation in verbatim material.
- Closing the JSON answer string is the end of the user-facing response. Do not close it merely because a quoted phrase or example ends.
'@
}
function Get-OrchestratorSystemPrompt {
    return Add-LfoStructuredAnswerPolicy (Expand-RuntimePolicy $script:OrchestratorSystemTemplate) $env:LFO_RUNTIME_DEVICE
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

    # Intentional v9.6.4 research boundary: FRONTIER is read-only and bounded,
    # but the delegated prompt may leave the machine for cloud processing.
    # The existing LOCAL -> FRONTIER policy is preserved without an added consent gate.
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

# Console presentation only; raw model text remains unchanged for logs and export.
function ConvertTo-LfoSafeConsoleText([string]$Text) {
    return [regex]::Replace($Text, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]', '')
}
function Get-LfoMarkdownInlineSpans([string]$Text,[ConsoleColor]$DefaultColor='Gray'){
    $pattern='(?<code>\x60+[^\x60\r\n]+\x60+)|(?<link>!?\[[^\]]*\]\([^)]+\))|(?<bold>\*\*[^*\r\n]+\*\*|__[^_\r\n]+__)|(?<strike>~~[^~\r\n]+~~)|(?<italic>(?<!\w)\*[^*\r\n]+\*|(?<!\w)_[^_\r\n]+_(?!\w))|(?<url>https?://[^\s<>]+)'
    $offset=0
    foreach($m in [regex]::Matches($Text,$pattern)){
        if($m.Index -gt $offset){[pscustomobject]@{Text=$Text.Substring($offset,$m.Index-$offset);Color=$DefaultColor}}
        $value=$m.Value;$color=$DefaultColor
        if($m.Groups['code'].Success){$value=$value.Trim([char]96);$color='Cyan'}
        elseif($m.Groups['link'].Success){$parts=[regex]::Match($value,'^!?\[([^\]]*)\]\(([^)]+)\)$');$value=$parts.Groups[1].Value+' ('+$parts.Groups[2].Value+')';$color='Blue'}
        elseif($m.Groups['bold'].Success){$value=$value.Substring(2,$value.Length-4);$color='White'}
        elseif($m.Groups['italic'].Success){$value=$value.Substring(1,$value.Length-2);$color='Yellow'}
        elseif($m.Groups['strike'].Success){$value=$value.Substring(2,$value.Length-4);$color='DarkGray'}
        elseif($m.Groups['url'].Success){$color='Blue'}
        [pscustomobject]@{Text=$value;Color=$color}
        $offset=$m.Index+$m.Length
    }
    if($offset -lt $Text.Length){[pscustomobject]@{Text=$Text.Substring($offset);Color=$DefaultColor}}
}
function Write-LfoMarkdownInline([string]$Text,[ConsoleColor]$Color='Gray'){
    foreach($span in @(Get-LfoMarkdownInlineSpans $Text $Color)){Write-Host $span.Text -ForegroundColor $span.Color -NoNewline}
    Write-Host ''
}
# Table layout uses visible text, not Markdown delimiters.
function Get-LfoTableCells([string]$Line){
    $s=$Line.Trim()
    if($s.StartsWith('|')){$s=$s.Substring(1)}
    if($s.EndsWith('|') -and -not $s.EndsWith('\|')){$s=$s.Substring(0,$s.Length-1)}
    foreach($part in [regex]::Split($s,'(?<!\\)\|')){$part.Trim().Replace('\|','|')}
}
function Get-LfoVisibleWidth([string]$Text){
    $width=0
    $e=[Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while($e.MoveNext()){
        $g=$e.GetTextElement()
        $cp=[char]::ConvertToUtf32($g,0)
        $cat=[Globalization.CharUnicodeInfo]::GetUnicodeCategory($g,0)
        if($cat -in @([Globalization.UnicodeCategory]::NonSpacingMark,[Globalization.UnicodeCategory]::EnclosingMark,[Globalization.UnicodeCategory]::Format)){continue}
        if(($cp -ge 0x1100 -and $cp -le 0x115F) -or ($cp -ge 0x2E80 -and $cp -le 0xA4CF) -or ($cp -ge 0xAC00 -and $cp -le 0xD7A3) -or ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or ($cp -ge 0xFE10 -and $cp -le 0xFE6F) -or ($cp -ge 0xFF01 -and $cp -le 0xFF60) -or ($cp -ge 0x1F300 -and $cp -le 0x1FAFF) -or ($cp -ge 0x20000 -and $cp -le 0x3FFFD)){$width+=2}else{$width++}
    }
    return $width
}
function Split-LfoTableCell([string]$Text,[int]$Width){
    if(-not $Text){'';return}
    $line=''
    foreach($word in ($Text -split '\s+')){
        if(-not $word){continue}
        $candidate=if($line){$line+' '+$word}else{$word}
        if((Get-LfoVisibleWidth $candidate) -le $Width){$line=$candidate;continue}
        if($line){$line;$line=''}
        $e=[Globalization.StringInfo]::GetTextElementEnumerator($word)
        while($e.MoveNext()){
            $g=$e.GetTextElement()
            if($line -and (Get-LfoVisibleWidth ($line+$g)) -gt $Width){$line;$line=''}
            $line+=$g
        }
    }
    if($line){$line}
}
function Get-LfoTableLayout([string[]]$Lines,[int]$Width){
    if($Lines.Count -lt 2){return $null}
    $header=@(Get-LfoTableCells $Lines[0]);$sep=@(Get-LfoTableCells $Lines[1])
    if($header.Count -lt 2 -or $sep.Count -ne $header.Count){return $null}
    foreach($c in $sep){if($c -notmatch '^:?-{3,}:?$'){return $null}}
    $n=$header.Count;$rows=New-Object 'System.Collections.Generic.List[object]'
    $widths=New-Object 'int[]' $n
    $align=New-Object 'string[]' $n
    for($i=0;$i -lt $n;$i++){$align[$i]=if($sep[$i] -match '^:.*:$'){'center'}elseif($sep[$i].EndsWith(':')){'right'}else{'left'}}
    for($r=0;$r -lt $Lines.Count;$r++){
        if($r -eq 1){continue}
        $cells=@(Get-LfoTableCells $Lines[$r])
        if($cells.Count -ne $n){return $null}
        $plain=New-Object 'string[]' $n
        for($i=0;$i -lt $n;$i++){
            $plain[$i]=(@(Get-LfoMarkdownInlineSpans $cells[$i] | ForEach-Object {$_.Text}) -join '') -replace '\s+',' '
            $widths[$i]=[Math]::Max($widths[$i],(Get-LfoVisibleWidth $plain[$i]))
        }
        $rows.Add($plain)
    }
    $available=$Width-1-3*$n
    if($available -lt 4*$n){return $null}
    for($i=0;$i -lt $n;$i++){$widths[$i]=[Math]::Max(4,$widths[$i])}
    $total=($widths|Measure-Object -Sum).Sum
    while($total -gt $available){
        $largest=0
        for($i=1;$i -lt $n;$i++){if($widths[$i] -gt $widths[$largest]){$largest=$i}}
        $widths[$largest]--;$total--
    }
    return [pscustomobject]@{Rows=$rows;Widths=$widths;Align=$align}
}
# Outer pipe delimiters are optional. Require a real header separator before
# consuming adjacent rows; leave unrelated or irregular lines to the normal renderer.
function Get-LfoMarkdownTableBlock([string[]]$Lines,[int]$Start,[int]$Width){
    if(($Start+1) -ge $Lines.Count -or $Lines[$Start] -notmatch '(?<!\\)\|'){return $null}
    $header=@(Get-LfoTableCells $Lines[$Start])
    $separator=@(Get-LfoTableCells $Lines[$Start+1])
    if($header.Count -lt 2 -or $separator.Count -ne $header.Count){return $null}
    foreach($cell in $separator){if($cell -notmatch '^:?-{3,}:?$'){return $null}}
    $end=$Start+2
    while($end -lt $Lines.Count -and $Lines[$end] -match '(?<!\\)\|'){
        $cells=@(Get-LfoTableCells $Lines[$end])
        if($cells.Count -ne $header.Count){break}
        if($Lines[$end] -match '^\s*(?:\x60{3,}|~{3,}|#{1,6}\s|>)'){break}
        $end++
    }
    $layout=Get-LfoTableLayout $Lines[$Start..($end-1)] $Width
    if($null -eq $layout){return $null}
    return [pscustomobject]@{Layout=$layout;EndIndex=($end-1)}
}

function Write-LfoTableBorder($Widths,[int]$Left,[int]$Middle,[int]$Right){
    $parts=@(foreach($w in $Widths){([string][char]0x2500)*($w+2)})
    Write-Host (([string][char]$Left)+($parts -join ([string][char]$Middle))+([string][char]$Right)) -ForegroundColor DarkCyan
}
function Write-LfoMarkdownTable($Layout){
    $bar=[string][char]0x2502
    Write-LfoTableBorder $Layout.Widths 0x250C 0x252C 0x2510
    for($r=0;$r -lt $Layout.Rows.Count;$r++){
        $wrapped=New-Object 'System.Collections.Generic.List[object]';$height=1
        for($i=0;$i -lt $Layout.Widths.Count;$i++){
            $pieces=@(Split-LfoTableCell $Layout.Rows[$r][$i] $Layout.Widths[$i])
            $wrapped.Add($pieces);$height=[Math]::Max($height,$pieces.Count)
        }
        $color=if($r -eq 0){'Cyan'}else{'Gray'}
        for($j=0;$j -lt $height;$j++){
            Write-Host $bar -ForegroundColor DarkCyan -NoNewline
            for($i=0;$i -lt $Layout.Widths.Count;$i++){
                $value=if($j -lt $wrapped[$i].Count){[string]$wrapped[$i][$j]}else{''}
                $pad=[Math]::Max(0,$Layout.Widths[$i]-(Get-LfoVisibleWidth $value))
                $left=if($Layout.Align[$i] -eq 'right'){$pad}elseif($Layout.Align[$i] -eq 'center'){[int][Math]::Floor($pad/2)}else{0}
                Write-Host (' '+(' '*$left)+$value+(' '*($pad-$left))+' ') -ForegroundColor $color -NoNewline
                Write-Host $bar -ForegroundColor DarkCyan -NoNewline
            }
            Write-Host ''
        }
        if($r -eq 0){Write-LfoTableBorder $Layout.Widths 0x251C 0x253C 0x2524}
    }
    Write-LfoTableBorder $Layout.Widths 0x2514 0x2534 0x2518
}
function Split-LfoImportPrompts([string]$Text){
    foreach($part in [regex]::Split($Text,'(?m)^[ \t]*\|\|\|[ \t]*\r?$')){
        if([string]::IsNullOrWhiteSpace($part)){continue}
        $part=$part.Trim([char[]]@([char]13,[char]10))
        if([Text.Encoding]::UTF8.GetByteCount($part) -gt 32768){throw 'An import entry exceeds 32 KiB; split it into smaller prompts.'}
        $part
    }
}

function Write-LfoMarkdown([AllowEmptyString()][string]$Text){
    $safe=ConvertTo-LfoSafeConsoleText $Text
    if((Test-Path Env:NO_COLOR) -or $env:LFO_MARKDOWN_PLAIN -eq '1'){Write-Host $safe;return}
    $fence='';$fenceLength=0
    $lines=@($safe -split '\r?\n')
    $terminalWidth=100
    try{if($Host.UI.RawUI.WindowSize.Width -gt 0){$terminalWidth=[Math]::Max(1,$Host.UI.RawUI.WindowSize.Width-1)}}catch{}
    for($rowIndex=0;$rowIndex -lt $lines.Count;$rowIndex++){
        $line=$lines[$rowIndex]
        if($line -match '^\s*(\x60{3,}|~{3,})(.*)$'){
            $marker=$Matches[1];$rest=$Matches[2].Trim()
            if(-not $fence){$fence=$marker.Substring(0,1);$fenceLength=$marker.Length;Write-Host ('  +--- code'+$(if($rest){': '+$rest})+' ---') -ForegroundColor DarkCyan;continue}
            if($marker.Substring(0,1) -eq $fence -and $marker.Length -ge $fenceLength -and -not $rest){$fence='';$fenceLength=0;Write-Host '  +--- end code ---' -ForegroundColor DarkCyan;continue}
        }
        if($fence){Write-Host ('  | '+$line) -ForegroundColor Cyan;continue}
        if($line -match '^\s{0,3}(#{1,6})\s+(.+?)\s*#*\s*$'){$level=$Matches[1].Length;$heading=$Matches[2];$color=if($level -le 2){'Cyan'}else{'Green'};Write-LfoMarkdownInline $heading $color;continue}
        if($line -match '^\s{0,3}(?:-{3,}|\*{3,}|_{3,})\s*$'){Write-Host ('-'*48) -ForegroundColor DarkGray;continue}
        if($line -match '^\s*>\s?(.*)$'){$body=$Matches[1];Write-Host '  | ' -ForegroundColor DarkCyan -NoNewline;Write-LfoMarkdownInline $body 'DarkCyan';continue}
        if($line -match '^(\s*)([-+*]|\d+[.)])\s+(.+)$'){
            $indent=$Matches[1];$bullet=$Matches[2];$body=$Matches[3]
            if($bullet -in @('-','+','*')){$bullet=[string][char]0x2022}
            if($body -match '^\[([ xX])\]\s+(.*)$'){$bullet=if($Matches[1] -eq ' '){'[ ]'}else{'[x]'};$body=$Matches[2]}
            Write-Host ($indent+$bullet+' ') -ForegroundColor Green -NoNewline;Write-LfoMarkdownInline $body;continue
        }
        $table=Get-LfoMarkdownTableBlock $lines $rowIndex $terminalWidth
        if($null -ne $table){Write-LfoMarkdownTable $table.Layout;$rowIndex=$table.EndIndex;continue}
        Write-LfoMarkdownInline $line
    }
}
function Get-LfoTransferFile([string]$Directory,[string]$Name){
    $Name=$Name.Trim().Trim([char]34)
    if(-not $Name -or $Name -ne [IO.Path]::GetFileName($Name) -or $Name -match '[<>:"/\\|?*\x00-\x1F]' -or $Name -match '\.$| $|^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)' -or $Name -in @('.','..')){throw 'Use a single ordinary file name, not a path.'}
    return Join-Path $Directory $Name
}
function Write-LfoTransferExport([string]$Path,[string]$Content){
    $bytes=[Text.Encoding]::UTF8.GetBytes($Content)
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
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

# Preserve CPU/GPU defaults; UMA context headroom is a heuristic.
function Get-LfoGenerationBudget($Generation,[bool]$Thinking,[string]$Device,[int]$Context,[object[]]$Messages,$Format){
    $legacy=if($Thinking){[int]$Generation.NumPredictThink}else{[int]$Generation.NumPredictNormal}
    if($Device -ne 'UMA' -or $Context -le 0){return $legacy}
    $target=if($Thinking){[int]$Generation.UmaNumPredictThink}else{[int]$Generation.UmaNumPredictNormal}
    if($target -le 0){$target=$legacy}
    $chars=0
    foreach($message in $Messages){$chars+=([string]$message.content).Length+48}
    if($null -ne $Format){$chars+=($Format|ConvertTo-Json -Depth 12 -Compress).Length}
    $estimatedInput=[int][Math]::Ceiling($chars/3.0)+512
    $remaining=[Math]::Max(128,$Context-$estimatedInput)
    return [int][Math]::Min($target,[Math]::Min([Math]::Max(128,[Math]::Floor($Context/2)),$remaining))
}
# Extract only the top-level answer string; drop incomplete trailing escapes.
function Get-LfoPartialJsonAnswer([string]$Content){
    if([string]::IsNullOrWhiteSpace($Content)){return ''}
    $s=$Content.TrimStart()
    if(-not $s.StartsWith('{')){return ''}
    $depth=1;$i=1
    $stringToken=[regex]'(?s)\G"(?<body>(?:[^"\\\x00-\x1F]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*)(?<close>")?'
    while($i -lt $s.Length){
        $ch=$s[$i]
        if($ch -eq '"'){
            $token=$stringToken.Match($s,$i)
            if(-not $token.Success -or -not $token.Groups['close'].Success){return ''}
            $i+=$token.Length
            if($depth -eq 1 -and $token.Groups['body'].Value -ceq 'answer'){
                $colon=[regex]::Match($s.Substring($i),'^\s*:\s*')
                if($colon.Success){
                    $valueStart=$i+$colon.Length
                    if($valueStart -ge $s.Length){return ''}
                    $value=$stringToken.Match($s,$valueStart)
                    if(-not $value.Success){return ''}
                    try{
                        $decoded=('{"answer":"'+$value.Groups['body'].Value+'"}'|ConvertFrom-Json -ErrorAction Stop).answer
                        return ([string]$decoded).Trim()
                    }catch{return ''}
                }
            }
            continue
        }
        if($ch -eq '{' -or $ch -eq '['){$depth++}
        elseif($ch -eq '}' -or $ch -eq ']'){$depth--;if($depth -le 0){return ''}}
        $i++
    }
    return ''
}

function Invoke-QwenLocalApi {
    # Distinguish PowerShell prompt/schema construction from the HTTP model
    # request. Both FULL and COMPACT share identical instrumentation.
    $prepareSw = [Diagnostics.Stopwatch]::StartNew()
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
            num_predict = 1 # resolved after request construction
            temperature = [double]$script:Config.LocalGeneration.Temperature
        }
    }

    $bodyObj.options.num_predict = Get-LfoGenerationBudget $script:Config.LocalGeneration $script:ThinkEnabled $env:LFO_RUNTIME_DEVICE $script:ContextLengthHint $bodyObj.messages $bodyObj.format
    $body = $bodyObj | ConvertTo-Json -Depth 12 -Compress
    $prepareSw.Stop()
    Add-LfoTurnPhase -Phase 'local_request_build' -Kind 'prepare' `
        -WallSeconds $prepareSw.Elapsed.TotalSeconds -InputChars $body.Length
    return Invoke-LfoChatApi -Phase 'local_generation' -Body $body
}

function Invoke-QwenAnswerRecovery([string]$Prompt) {
    # A rare answer-only retry. The first pass remains the sole source of
    # memory_note, and this call cannot route or invoke Codex.
    $systemText = Add-LfoStructuredAnswerPolicy 'Provide a complete user-facing answer to the most recent user message. Return only the answer field. If uncertain, say so plainly.' $env:LFO_RUNTIME_DEVICE
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
            num_predict = 1 # resolved after request construction
            temperature = [double]$script:Config.LocalGeneration.Temperature
        }
    }
    $bodyObj.options.num_predict = Get-LfoGenerationBudget $script:Config.LocalGeneration $script:ThinkEnabled $env:LFO_RUNTIME_DEVICE $script:ContextLengthHint $bodyObj.messages $bodyObj.format
    $body = $bodyObj | ConvertTo-Json -Depth 12 -Compress
    return Invoke-LfoChatApi -Phase 'answer_recovery' -Body $body
}

function Invoke-QwenSynthesis([string]$OriginalPrompt, [string]$FrontierResult) {
    $synthesisSystem = Add-LfoStructuredAnswerPolicy (Expand-RuntimePolicy $script:SynthesisSystemTemplate) $env:LFO_RUNTIME_DEVICE
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
            num_predict = 1 # resolved after request construction
            temperature      = [double]$script:Config.SynthesisGeneration.Temperature
            presence_penalty = [double]$script:Config.SynthesisGeneration.PresencePenalty
        }
    }

    $bodyObj.options.num_predict = Get-LfoGenerationBudget $script:Config.SynthesisGeneration $script:ThinkEnabled $env:LFO_RUNTIME_DEVICE $script:ContextLengthHint $bodyObj.messages $bodyObj.format
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
    $stageSources = New-Object 'System.Collections.Generic.List[object]'
    $finalProducer = 'WRAPPER'
    $finalPhase = 'wrapper'
    Add-LfoL0StageSource $stageSources 'USER' 'INPUT' 'input' 'USER' $Prompt 'received' 'user'

    if (-not [string]::IsNullOrWhiteSpace($policyReason)) {
        $route = 'FRONTIER'
        Write-Host ("`n[policy -> FRONTIER; reason={0}]" -f $policyReason) -ForegroundColor DarkCyan
    } else {
        # Qwen routes and answers in one schema-constrained generation. On
        # LOCAL the same generation also carries the bounded memory micro-note.
        $r = Invoke-QwenLocalApi
        $localPostSw = [Diagnostics.Stopwatch]::StartNew()
        Show-QwenThinking $r
        $candidate = Get-CleanQwenContent $r
        $localRaw = $candidate
        Add-LfoL0StageSource $stageSources 'LOCAL' 'LOCAL_RESPONSE' 'initial' 'LOCAL' $candidate
        $structured = ConvertFrom-QwenStructuredContent $candidate -ExpectRoute

        if ([string]$r.done_reason -eq 'length') {
            # No frontier routing or model-generated memory from a capped envelope.
            $route = 'LOCAL'
            $finalContent = if($structured.Success -and $structured.Route -eq 'LOCAL'){[string]$structured.Answer}else{Get-LfoPartialJsonAnswer $candidate}
            if($structured.Success -and $structured.Route -eq 'FRONTIER'){$finalContent=''}
            $finalProducer = 'LOCAL'
            $finalPhase = 'generation_limit'
            $inlineMemoryNote = $null
            $inlineMemoryOps = [pscustomobject]@{Valid=@();Rejected=@()}
            $answerRecoveryReason = 'generation-limit'
            Write-Host "[Qwen reached the generation limit; answer may be incomplete.]" -ForegroundColor Yellow
            if(Test-QwenInvalidFinalAnswer $finalContent){
                $finalContent='[Generation limit reached before a usable answer was produced.]'
                $finalProducer='WRAPPER'
            }else{
                $finalContent += [Environment]::NewLine+[Environment]::NewLine+'[Incomplete response: generation limit reached.]'
            }
        } elseif ($structured.Success) {
            $route = [string]$structured.Route
            if ($route -eq 'FRONTIER') {
                Write-Host "`n[Qwen route -> FRONTIER]" -ForegroundColor DarkCyan
            } else {
                Write-Host "`n[Qwen route -> LOCAL]" -ForegroundColor DarkGray
                $finalContent = [string]$structured.Answer
                $finalProducer = 'LOCAL'
                $finalPhase = 'initial'
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
                        $finalProducer = 'WRAPPER'
                        $finalPhase = 'declarative_ack'
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
                            $recoveryContent = Get-CleanQwenContent $recoveryResponse
                            Add-LfoL0StageSource $stageSources 'LOCAL' 'LOCAL_RESPONSE' 'answer_recovery' 'LOCAL' $recoveryContent
                            $recoveredAnswer = Get-QwenRecoveredAnswer $recoveryContent
                            if ([string]$recoveryResponse.done_reason -ne 'length' -and
                                -not (Test-QwenInvalidFinalAnswer $recoveredAnswer)) {
                                $finalContent = $recoveredAnswer
                                $finalProducer = 'LOCAL'
                                $finalPhase = 'answer_recovery'
                                $answerRecoverySuccess = $true
                            }
                        } catch {
                            Write-Host "[Qwen answer recovery failed.]" -ForegroundColor Yellow
                        }
                        if (-not $answerRecoverySuccess) {
                            $finalContent = 'The local model could not produce a usable answer. Please try again.'
                            $finalProducer = 'WRAPPER'
                            $finalPhase = 'recovery_failed'
                        }
                    }
                }
            }
        } else {
            # Structured output failure must never trigger a frontier call.
            Write-Host "`n[Qwen structured output malformed; fail-closed -> LOCAL]" -ForegroundColor Yellow
            $route = 'LOCAL'
            $finalContent = '[The model returned invalid structured output. Please retry.]'
            $finalProducer = 'WRAPPER'
            $finalPhase = 'malformed_output'
            $inlineMemoryNote = $null
        }
        $localPostSw.Stop()
        Add-LfoTurnPhase -Phase 'local_response_processing' -Kind 'prepare' `
            -WallSeconds $localPostSw.Elapsed.TotalSeconds
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
            Add-LfoL0StageSource $stageSources 'FRONTIER' 'FRONTIER_RESPONSE' 'handoff' 'WRAPPER' $frontierResult 'failed'
            $finalContent = $frontierResult
            $finalPhase = 'frontier_failed'
        } else {
            Add-LfoL0StageSource $stageSources 'FRONTIER' 'FRONTIER_RESPONSE' 'handoff' 'FRONTIER' $frontierResult
            $r = Invoke-QwenSynthesis $Prompt $frontierResult
            Show-QwenThinking $r
            $candidate = Get-CleanQwenContent $r
            Add-LfoL0StageSource $stageSources 'LOCAL' 'LOCAL_RESPONSE' 'synthesis' 'LOCAL' $candidate
            $structuredSynthesis = ConvertFrom-QwenStructuredContent $candidate

            $invalidSynthesisAnswer = $structuredSynthesis.Success -and
                (Test-QwenInvalidFinalAnswer ([string]$structuredSynthesis.Answer))
            if (-not $structuredSynthesis.Success -or
                [string]$r.done_reason -eq 'length' -or
                (-not $invalidSynthesisAnswer -and
                    (Test-UnfinishedSynthesis $r ([string]$structuredSynthesis.Answer)))) {
                Write-Host "`n[Qwen synthesis did not complete cleanly; showing the frontier result directly.]" -ForegroundColor Yellow
                $finalContent = $frontierResult
                $finalProducer = 'FRONTIER'
                $finalPhase = 'synthesis_fallback'
                $inlineMemoryNote = $null
                $inlineMemoryOps = [pscustomobject]@{
                    Valid = @()
                    Rejected = @()
                }
            } elseif ($invalidSynthesisAnswer) {
                Write-Host "`n[Qwen synthesis answer invalid; showing the frontier result directly.]" -ForegroundColor Yellow
                $finalContent = $frontierResult
                $finalProducer = 'FRONTIER'
                $finalPhase = 'synthesis_fallback'
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
                $finalProducer = 'LOCAL'
                $finalPhase = 'synthesis'
                $inlineMemoryNote = $structuredSynthesis.MemoryNote
                $inlineMemoryOps = $structuredSynthesis.MemoryOps
            }
        }
    }

    # Explicit storage requests are a wrapper-level invariant. Normal implicit
    # memory remains single-pass; only an explicit request with an empty note
    # gets one bounded memory-only extraction retry.
    if ($finalPhase -notin @('generation_limit','malformed_output') -and $script:MemoryEnabled -and $explicitMemoryIntent -and
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
            $finalProducer = 'WRAPPER'
            $finalPhase = 'memory_recovery_failed'
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
        $finalProducer = 'WRAPPER'
        $finalPhase = 'raw_sentinel'
    }

    $sw.Stop()

    if ([string]::IsNullOrWhiteSpace($finalContent)) {
        Write-Host "`n[The model did not produce final content within the token limit.]" -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-LfoMarkdown $finalContent
        $script:LfoLastExportAnswer=$finalContent
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
        Add-LfoL0StageSource $stageSources 'FINAL' 'FINAL_RESPONSE' $finalPhase $finalProducer $finalContent 'delivered' 'assistant'
        Persist-TurnAndMemory `
            -PostL0 $script:LfoL4PostL0 `
            -StageSources $stageSources.ToArray() `
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
$script:LfoL4PostL0=$null
$script:LfoL4Loaded=$false
try {
    . (Join-Path $PSScriptRoot 'LfoL4Runtime.ps1')
    $l4Settings=@{}
    if($script:Config.ContainsKey('L4')){$l4Settings=$script:Config.L4}
    $l4State=Initialize-LfoL4Recording -LogDirectory $script:LogDir -ProvenanceEnabled $script:L0StageSourcesEnabled -Settings $l4Settings
    $script:LfoL4Loaded=$true
    Write-Host ('[L4 recording: '+$l4State.Status+'; analysis: /analyze; P2 OFF]')
    if($l4State.Status -ceq 'CONFIGURED'){
        $script:LfoL4PostL0={
            param($Row,$SourceFile)
            $result=Invoke-LfoL4RecordTurn -Row $Row -SourceFile $SourceFile
            Write-Host ("[L4 turn={0}: {1}]" -f $Row.turn_id,$result.Status) -ForegroundColor DarkGray
        }
    }
} catch { Write-Host '[L4 unavailable; chat continues.]' -ForegroundColor Yellow }
$script:PolicyFingerprint = Get-PolicyFingerprint

Test-Ollama
Write-Host ""
Write-Host "Qwen local chat v9.6.6-dev. Commands: /exit, /clear, /paste, /think on, /think off, /analyze, /files, /import, /export, /export-log"
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

$transferRoot=if($env:LFO_INSTALL_ROOT){$env:LFO_INSTALL_ROOT}else{Join-Path $env:LOCALAPPDATA 'LFO'}
$script:LfoImportDir=if($env:LFO_IMPORT_DIR){$env:LFO_IMPORT_DIR}else{Join-Path $transferRoot 'import'}
$script:LfoExportDir=if($env:LFO_EXPORT_DIR){$env:LFO_EXPORT_DIR}else{Join-Path $transferRoot 'export'}
$script:LfoLastExportAnswer=''
$script:LfoImportQueue=$null
while ($true) {
    if($script:LfoImportQueue -and $script:LfoImportQueue.Count -gt 0){
        $prompt=$script:LfoImportQueue.Dequeue()
        $script:LfoImportIndex++
        Write-Host ("[import {0}/{1}]" -f $script:LfoImportIndex,$script:LfoImportTotal) -ForegroundColor Cyan
        Write-Host ('Qwen>: '+(ConvertTo-LfoSafeConsoleText $prompt)) -ForegroundColor DarkGray
    }else{
        $script:LfoImportQueue=$null
        $prompt = Read-Host "Qwen>"
    }
    if ($null -eq $prompt) { continue }

    switch -Regex ($prompt.Trim()) {
        '^/analyze(?:\s|$)' {
            if($script:LfoL4Loaded){
                Invoke-LfoL4AnalyzeCommand -Command $prompt -Epoch ([int]$script:RuntimeState.epoch) -LastTurn ([int]$script:RuntimeState.next_turn_id-1)
            } else { Write-Host '[L4 analysis unavailable.]' }
            continue
        }
        '^/files$' {
            Write-Host ("Import: {0}" -f $script:LfoImportDir) -ForegroundColor Cyan
            Write-Host ("Export: {0}" -f $script:LfoExportDir) -ForegroundColor Cyan
            Get-ChildItem -LiteralPath $script:LfoImportDir -File -ErrorAction SilentlyContinue | Select-Object Name,Length | Format-Table -AutoSize | Out-Host
            continue
        }
        '^/import\s+(.+)$' {
            $name=$Matches[1]
            try {
                $path=Get-LfoTransferFile $script:LfoImportDir $name
                $item=Get-Item -LiteralPath $path -ErrorAction Stop
                if($null -ne $script:LfoImportQueue){throw 'Nested /import is not supported.'}
                if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 67108864 -or $item.Extension -notin @('.txt','.md','.json','.csv','.ps1','.py','.log','.xml','.yaml','.yml')){throw 'Import requires a regular UTF-8 text file of at most 64 MiB.'}
                $text=[IO.File]::ReadAllText($path,(New-Object Text.UTF8Encoding($false,$true)))
                $entries=@(Split-LfoImportPrompts $text)
                if($entries.Count -eq 0){throw 'Import file is empty.'}
                $script:LfoImportQueue=New-Object 'System.Collections.Generic.Queue[string]'
                foreach($entry in $entries){$script:LfoImportQueue.Enqueue($entry)}
                $script:LfoImportIndex=0;$script:LfoImportTotal=$entries.Count
                Write-Host ("[Importing {0}: {1} entries; normal routing and logging apply]" -f $item.Name,$entries.Count) -ForegroundColor Cyan
            } catch {Write-Host ("Import failed: "+$_.Exception.Message) -ForegroundColor Yellow}
            continue
        }
        '^/export(?:\s+(.+))?$' {
            $name=$Matches[1]
            try {
                if(-not $script:LfoLastExportAnswer){throw 'No answer in this session to export.'}
                if(-not $name){$name='answer-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.md'}
                $path=Get-LfoTransferFile $script:LfoExportDir $name
                Write-LfoTransferExport $path $script:LfoLastExportAnswer
                Write-Host ("Exported: "+$path) -ForegroundColor Green
            } catch {Write-Host ("Export failed: "+$_.Exception.Message) -ForegroundColor Yellow}
            continue
        }
        '^/export-log$' {
            try {
                $source=Get-MonthlyLogPath 'conversation'
                $name='conversation-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.jsonl'
                $path=Get-LfoTransferFile $script:LfoExportDir $name
                [IO.File]::Copy($source,$path,$false)
                Write-Host ("Exported current monthly conversation log: "+$path) -ForegroundColor Green
            } catch {Write-Host ("Export failed: "+$_.Exception.Message) -ForegroundColor Yellow}
            continue
        }
        '^/exit$' {
            exit 0
        }
        '^/clear$' {
            Clear-PersistentConversationMemory
            $script:LfoLastExportAnswer=''
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
