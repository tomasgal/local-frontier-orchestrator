# Validate isolated read-enabled ORION fixture after a Qwen LOCAL turn.
# Read-only; no production paths; always checks SQLite separately from trace.
[CmdletBinding()]
param([string]$Root = $global:dev4L2Root)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw 'Isolated dev4 live fixture root is missing; launch tests/Start-Dev4L2LiveFixture.ps1 first.'
}
$dbPath = Join-Path $Root 'state\l2-memory.db'
$traceDir = Join-Path $Root 'logs'
$configPath = Join-Path $Root 'QwenChat-isolated.config.psd1'
if (-not (Test-Path -LiteralPath $dbPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $configPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $traceDir -PathType Container)) {
    throw 'Incomplete isolated fixture. Refusing to check a different database.'
}
$cfg = Import-PowerShellDataFile -LiteralPath $configPath
if ($cfg.Memory.DataDirectory -ne $Root -or -not $cfg.Memory.StructuredReadEnabled -or
    -not $cfg.Memory.StructuredEnabled) { throw 'Fixture configuration is not isolated/read enabled.' }

$traceFiles = @(Get-ChildItem -LiteralPath $traceDir -File -Filter 'trace-*.jsonl')
$turns = @(foreach ($file in $traceFiles) {
    foreach ($line in (Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $obj = $line | ConvertFrom-Json
            if ($obj.event -eq 'turn_trace') { $obj }
        }
    }
})
if ($turns.Count -ne 1) { throw "Expected exactly one isolated Qwen turn trace, found $($turns.Count)." }
$t = $turns[0]
Write-Host '===== MODEL ANSWER (semantic review) ====='
Write-Host ([string]$t.final_answer)
Write-Host '===== TURN AND GUARD ====='
$t | Select-Object turn_id,route,answer_seconds,l2_status,l2_applied_count,l2_rejected_count,l2_ops_model_valid_count,l2_ops_model_rejected_count,l2_ops_suppressed_valid_count,l2_ops_suppressed_rejected_count,l2_read_write_guard_active,l2_read_write_guard_reason,l1_model_note_suppressed,memory_note_appended | Format-List
Write-Host '===== CONTEXT ====='
$t.dev4_context | Format-List
Write-Host '===== MODEL PHASES ====='
$t.dev4_phases | Select-Object phase,kind,wall_seconds,prompt_eval_count,eval_count,prompt_eval_seconds,decode_seconds,other_seconds | Format-Table -AutoSize

if ($t.turn_id -ne 3 -or $t.route -ne 'LOCAL' -or
    $t.dev4_context.l2_read_items -ne 4 -or
    $t.dev4_context.l2_read_chars -gt 800 -or
    $t.dev4_context.l0_old_data_items -ne 0 -or
    $t.dev4_context.l2_read_status -ne 'ok' -or
    -not $t.l2_read_write_guard_active -or
    $t.l2_read_write_guard_reason -ne 'local-l2-retrieval-is-not-new-evidence' -or
    $t.l2_applied_count -ne 0 -or $t.l2_rejected_count -ne 0 -or
    $t.l2_status -ne 'empty' -or
    @($t.l2_ops_valid).Count -ne 0 -or
    @($t.l2_ops_rejected).Count -ne 0 -or
    $t.memory_note_appended) {
    throw 'Read-side trace or persistence guard acceptance FAILED'
}
$phaseReads = @($t.dev4_phases | Where-Object { $_.phase -eq 'l2_retrieval' })
if ($phaseReads.Count -ne 1) { throw 'Expected exactly one measured L2 retrieval' }

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\LfoMemoryStore.ps1')
# Original store API opens read-write by default: use the dedicated read-only wrapper.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\LfoStructuredRetrieval.ps1')
$reader = Open-LfoMemoryReadOnly $dbPath
try {
    $sql = @'
SELECT f.scope_id,f.source_turn,f.valid_from_turn,f.valid_to_turn,f.predicate,
       f.literal_type,f.value_text,f.value_integer,
       (SELECT n.name FROM entity_names n WHERE n.entity_id=f.subject_entity_id ORDER BY n.id LIMIT 1) AS subject
FROM facts f
ORDER BY f.id;
'@
    $rows = @(Invoke-LfoSqliteQuery $reader $sql)
    $orion = @($rows | Where-Object { $_.subject -eq 'ORION' -and $_.scope_id -eq 'conversation:1' })
    $current = @($orion | Where-Object { $null -eq $_.valid_to_turn })
    $historical = @($orion | Where-Object { $null -ne $_.valid_to_turn })
    $unexpected = @($rows | Where-Object { $_.source_turn -eq 3 -or $_.valid_from_turn -eq 3 })
    if ($rows.Count -ne 7 -or $orion.Count -ne 5 -or $current.Count -ne 4 -or
        $historical.Count -ne 1 -or $unexpected.Count -ne 0 -or
        @($current | Where-Object { $_.predicate -eq 'os' -and $_.value_text -eq 'Debian 13' }).Count -ne 1 -or
        @($historical | Where-Object { $_.predicate -eq 'os' -and $_.value_text -eq 'Ubuntu 24.04' -and $_.valid_to_turn -eq 2 }).Count -ne 1) {
        throw 'SQLite changed or source-turn provenance deviated from the seeded test fixture'
    }
} finally { Close-LfoSqliteDatabase $reader }
$pendingPath = Join-Path $Root 'state\pending_notes.jsonl'
$pending = if (Test-Path -LiteralPath $pendingPath) { [string](Get-Content -LiteralPath $pendingPath -Raw -Encoding UTF8) } else { '' }
if (-not [string]::IsNullOrWhiteSpace($pending)) { throw 'L1 micro-note was persisted from L2 read-side evidence' }
Write-Host 'DEV4 STAGE2 LIVE READ-SIDE GUARD + SQLITE + L1 PARITY: PASS'
Write-Host 'Review the printed model answer separately for factual correctness.'
