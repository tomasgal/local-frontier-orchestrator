# Read-only dev5 candidate B comparison: A-only versus A+B lean read policy.
# Each TEMP fixture must first independently PASS Test-Dev4L2LiveTrace.ps1.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AOnlyRoot,
    [Parameter(Mandatory=$true)][string]$LeanRoot
)
$ErrorActionPreference = 'Stop'

function Read-LfoPolicyTrial([string]$Root,[bool]$ExpectLean) {
    $path = [IO.Path]::GetFullPath($Root)
    $configPath = Join-Path $path 'QwenChat-isolated.config.psd1'
    $logPath = Join-Path $path 'logs'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $logPath -PathType Container)) {
        throw "Incomplete TEMP-only read trial: $path"
    }
    $cfg = Import-PowerShellDataFile -LiteralPath $configPath
    if ([IO.Path]::GetFullPath([string]$cfg.Memory.DataDirectory) -ine $path -or
        -not [bool]$cfg.Memory.StructuredReadEnabled -or
        -not [bool]$cfg.LocalGeneration.CompactReadSchemaEnabled -or
        [bool]$cfg.LocalGeneration.LeanReadPolicyEnabled -ne $ExpectLean) {
        throw "Read-mode/profile mismatch: $path"
    }
    $records = @(foreach ($file in @(Get-ChildItem -LiteralPath $logPath -Filter 'trace-*.jsonl' -File)) {
        foreach ($line in @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $r = $line | ConvertFrom-Json
                if ($r.event -eq 'turn_trace') { $r }
            }
        }
    })
    $question = 'What are the stored OS, RAM, database and nightly backup facts for ORION?'
    $hits = @($records | Where-Object {
        [int]$_.turn_id -eq 3 -and [int]$_.epoch -eq 1 -and
        [string]$_.user -ceq $question
    })
    if ($hits.Count -ne 1) { throw "Expected one synthetic ORION query, got $($hits.Count): $path" }
    $t = $hits[0]
    $policy = if ($null -ne $t.PSObject.Properties['dev5_read_policy_mode']) {
        [string]$t.dev5_read_policy_mode
    } else {
        'full'
    }
    $expectedPolicy = if ($ExpectLean) { 'lean-read' } else { 'full' }
    $answer = [string]$t.final_answer
    if ($t.route -ne 'LOCAL' -or $t.dev5_local_output_mode -ne 'compact-read' -or
        $policy -ne $expectedPolicy -or
        [int]$t.dev4_context.l2_read_items -ne 4 -or
        [int]$t.dev4_context.l2_read_chars -ne 336 -or
        [int]$t.dev4_context.l0_old_data_items -ne 0 -or
        -not [bool]$t.l2_read_write_guard_active -or
        [int]$t.l2_applied_count -ne 0 -or [int]$t.l2_rejected_count -ne 0 -or
        [int]$t.l2_ops_model_valid_count -ne 0 -or [bool]$t.memory_note_appended -or
        $answer -notmatch '(?i)Debian\s+13' -or $answer -notmatch '(?i)64\s*GB' -or
        $answer -notmatch '(?i)PostgreSQL\s+16' -or
        $answer -notmatch '(?i)nightly\s+backups?\s+(?:are\s+)?enabled' -or
        $answer -match '(?i)Ubuntu\s+24\.04|FreeBSD\s+14|VEGA') {
        throw "Semantic/read-write acceptance failed: $path"
    }
    $p = @($t.dev4_phases | Where-Object { $_.phase -eq 'local_generation' })
    if ($p.Count -ne 1 -or
        $null -eq $p[0].prompt_eval_count -or
        $null -eq $p[0].eval_count -or
        $null -eq $p[0].prompt_eval_seconds -or
        $null -eq $p[0].decode_seconds -or
        $null -eq $p[0].wall_seconds) {
        throw "Missing model metrics: $path"
    }
    return [pscustomobject][ordered]@{
        Policy = $policy
        Model = [string]$t.model
        Context = [int]$t.context_length_hint
        PromptTokens = [int]$p[0].prompt_eval_count
        OutputTokens = [int]$p[0].eval_count
        PrefillSeconds = [Math]::Round([double]$p[0].prompt_eval_seconds,3)
        DecodeSeconds = [Math]::Round([double]$p[0].decode_seconds,3)
        OllamaWallSeconds = [Math]::Round([double]$p[0].wall_seconds,3)
        AnswerWallSeconds = [Math]::Round([double]$t.answer_seconds,3)
        Root = $path
    }
}

$a = Read-LfoPolicyTrial $AOnlyRoot $false
$b = Read-LfoPolicyTrial $LeanRoot $true
if ($a.Root -ieq $b.Root) { throw 'Both conditions use the same fixture root' }
if ($a.Model -cne $b.Model -or $a.Context -ne $b.Context) {
    throw 'Model/context differs between A-only and A+B; not comparable'
}
Write-Host '=== Dev5 compact A versus compact A+B lean policy ==='
@($a,$b) | Select-Object Policy,Model,Context,PromptTokens,OutputTokens,PrefillSeconds,DecodeSeconds,OllamaWallSeconds,AnswerWallSeconds | Format-Table -AutoSize
Write-Host '=== A+B minus A-only ==='
@('PromptTokens','OutputTokens','PrefillSeconds','DecodeSeconds','OllamaWallSeconds','AnswerWallSeconds') | ForEach-Object {
    $n = $_
    $old = [double]$a.$n
    $new = [double]$b.$n
    [pscustomobject]@{
        Metric = $n
        AOnly = $old
        APlusB = $new
        Delta = [Math]::Round($new-$old,3)
        DeltaPct = if ($old -ne 0) { [Math]::Round(100*($new-$old)/$old,1) } else { $null }
    }
} | Format-Table -AutoSize
Write-Host 'Read-only semantic trace checks passed for both opt-in configurations.'
Write-Host 'CAUTION: Compare only independently checked SQLite fixtures, and treat a single sample as exploratory.'
