# Dev5 candidate A: read-only per-trial comparison of identical isolated ORION fixtures.
# Call after each independent strict Test-Dev4L2LiveTrace.ps1 passed.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$FullRoot,
    [Parameter(Mandatory=$true)][string]$CompactRoot
)
$ErrorActionPreference = 'Stop'

function Read-Dev5IsolatedTrial([string]$Root, [string]$ExpectedMode) {
    $folder = [IO.Path]::GetFullPath($Root)
    $cfgFile = Join-Path $folder 'QwenChat-isolated.config.psd1'
    $traceDir = Join-Path $folder 'logs'
    if (-not (Test-Path -LiteralPath $cfgFile -PathType Leaf) -or
        -not (Test-Path -LiteralPath $traceDir -PathType Container)) {
        throw "Incomplete synthetic fixture: $folder"
    }
    $cfg = Import-PowerShellDataFile -LiteralPath $cfgFile
    if ([IO.Path]::GetFullPath([string]$cfg.Memory.DataDirectory) -ine $folder -or
        -not [bool]$cfg.Memory.StructuredReadEnabled) {
        throw "Nonisolated/read-disabled fixture rejected: $folder"
    }
    $mode = if ([bool]$cfg.LocalGeneration.CompactReadSchemaEnabled) { 'compact-read' } else { 'full' }
    if ($mode -ne $ExpectedMode) { throw "Expected $ExpectedMode config but got $mode" }
    $turns = @(foreach ($file in @(Get-ChildItem -LiteralPath $traceDir -Filter 'trace-*.jsonl' -File)) {
        foreach ($line in @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $record = $line | ConvertFrom-Json
                if ($record.event -eq 'turn_trace') { $record }
            }
        }
    })
    $question = 'What are the stored OS, RAM, database and nightly backup facts for ORION?'
    $selected = @($turns | Where-Object {
        [int]$_.turn_id -eq 3 -and [int]$_.epoch -eq 1 -and
        [string]$_.user -ceq $question
    })
    if ($selected.Count -ne 1) {
        throw "Expected exactly one ORION trial at turn 3; got $($selected.Count) in $folder"
    }
    $t = $selected[0]
    $phases = @($t.dev4_phases | Where-Object { $_.phase -eq 'local_generation' })
    if ($phases.Count -ne 1) { throw "Missing/ambiguous LOCAL generation phase: $folder" }
    $p = $phases[0]
    $ans = [string]$t.final_answer
    if ($t.route -ne 'LOCAL' -or [string]$t.dev5_local_output_mode -ne $mode -or
        [int]$t.dev4_context.l2_read_items -ne 4 -or [int]$t.dev4_context.l2_read_chars -ne 336 -or
        [int]$t.l2_applied_count -ne 0 -or [int]$t.l2_rejected_count -ne 0 -or
        -not [bool]$t.l2_read_write_guard_active -or [bool]$t.memory_note_appended -or
        $ans -notmatch '(?i)Debian\s+13' -or $ans -notmatch '(?i)64\s*GB' -or
        $ans -notmatch '(?i)PostgreSQL\s+16' -or
        $ans -notmatch '(?i)nightly\s+backups?\s+(?:are\s+)?enabled' -or
        $ans -match '(?i)Ubuntu\s+24\.04|FreeBSD\s+14|VEGA') {
        throw "Trial semantics/guard are not equivalent: $folder"
    }
    if ($null -eq $p.eval_count -or $null -eq $p.prompt_eval_count -or
        $null -eq $p.decode_seconds -or $null -eq $p.prompt_eval_seconds -or
        $null -eq $p.wall_seconds) { throw "Missing Ollama phase counters in $folder" }
    return [pscustomobject][ordered]@{
        Mode = $mode
        Model = [string]$t.model
        ContextHint = [int]$t.context_length_hint
        PromptTokens = [int]$p.prompt_eval_count
        OutputTokens = [int]$p.eval_count
        PrefillS = [Math]::Round([double]$p.prompt_eval_seconds,3)
        DecodeS = [Math]::Round([double]$p.decode_seconds,3)
        ModelWallS = [Math]::Round([double]$p.wall_seconds,3)
        AnswerWallS = [Math]::Round([double]$t.answer_seconds,3)
        L2ReadS = [Math]::Round([double]$t.dev4_context.l2_read_seconds,3)
        ContextAssemblyS = [Math]::Round([double]$t.dev4_context.assembly_seconds,3)
        Root = $folder
    }
}

$full = Read-Dev5IsolatedTrial $FullRoot 'full'
$compact = Read-Dev5IsolatedTrial $CompactRoot 'compact-read'
if ($full.Model -cne $compact.Model -or $full.ContextHint -ne $compact.ContextHint) {
    throw 'Different model or context-length settings; cannot compare conditions.'
}

Write-Host '=== Matched isolated trials (one per mode) ==='
@($full,$compact) |
    Select-Object Mode,Model,ContextHint,PromptTokens,OutputTokens,PrefillS,DecodeS,ModelWallS,AnswerWallS,L2ReadS,ContextAssemblyS |
    Format-Table -AutoSize
Write-Host '=== COMPACT relative to FULL ==='
$fields = @('PromptTokens','OutputTokens','PrefillS','DecodeS','ModelWallS','AnswerWallS','L2ReadS','ContextAssemblyS')
$diff = @(foreach ($field in $fields) {
    $a = [double]$full.$field
    $b = [double]$compact.$field
    [pscustomobject]@{
        Metric = $field
        Full = $a
        Compact = $b
        Delta = [Math]::Round($b-$a,3)
        DeltaPct = if ($a -ne 0) { [Math]::Round(100*($b-$a)/$a,1) } else { $null }
    }
})
$diff | Format-Table -AutoSize
Write-Host 'Both conditions passed LOCAL answer, L2 retrieval and persistence trace screening.'
Write-Host 'CAUTION: one A/B pair is exploratory; cold/warm and background-load variance remain uncontrolled.'
