# Independent TEMP-only read-only proof for a single dev5 A+B mixed user RAM update.
[CmdletBinding()]
param([string]$Root=$global:dev5MixedLiveRoot)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root -PathType Container)){
    throw 'Missing preflighted mixed live TEMP fixture'
}
$path=[IO.Path]::GetFullPath($Root)
$temp=[IO.Path]::GetFullPath($env:TEMP).TrimEnd([char[]]@('\','/'))+[IO.Path]::DirectorySeparatorChar
if(-not $path.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
    -not ([IO.Path]::GetFileName($path) -like 'LFO-dev5-mixed-live-*')){
    throw 'Refusing to inspect non-TEMP or non-mixed-live state'
}
$configPath=Join-Path $path 'QwenChat-isolated.config.psd1'
$dbPath=Join-Path $path 'state\l2-memory.db'
$logs=Join-Path $path 'logs'
foreach($p in @($configPath,$dbPath)){
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing fixture: $p"}
}
if(-not (Test-Path -LiteralPath $logs -PathType Container)){throw 'No trace directory'}
$cfg=Import-PowerShellDataFile -LiteralPath $configPath
if([IO.Path]::GetFullPath([string]$cfg.Memory.DataDirectory) -ine $path -or
    -not [bool]$cfg.Memory.StructuredEnabled -or
    -not [bool]$cfg.Memory.StructuredReadEnabled -or
    -not [bool]$cfg.LocalGeneration.CompactReadSchemaEnabled -or
    -not [bool]$cfg.LocalGeneration.LeanReadPolicyEnabled -or
    [bool]$cfg.LocalGeneration.LowerTrustL2EvidenceEnabled -or
    -not [bool]$cfg.LocalGeneration.MixedUserEvidenceWriteEnabled){
    throw 'Mixed fixture configuration or memory directory mismatch'
}
$traces=@(foreach($file in @(Get-ChildItem -LiteralPath $logs -Filter 'trace-*.jsonl' -File)){
    foreach($line in @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)){
        if(-not [string]::IsNullOrWhiteSpace($line)){
            $t=$line|ConvertFrom-Json
            if($t.event -eq 'turn_trace'){$t}
        }
    }
})
$question='What OS does ORION run? Also, ORION RAM is now 96 GB.'
$matched=@($traces|Where-Object{[int]$_.turn_id -eq 3 -and
    [int]$_.epoch -eq 1 -and [string]$_.user -ceq $question})
if($traces.Count -ne 1 -or $matched.Count -ne 1){
    throw "Need exactly one mixed user turn3; total=$($traces.Count), matches=$($matched.Count)"
}
$t=$matched[0]
Write-Host '=== MIXED LIVE ANSWER ==='
Write-Host ([string]$t.final_answer)
Write-Host '=== SOURCE / GUARD / WRITE ==='
$t|Select-Object turn_id,route,l2_scope,answer_seconds,dev5_local_output_mode,dev5_read_policy_mode,dev5_l2_evidence_role,mixed_user_evidence_status,mixed_user_evidence_start,mixed_user_evidence_length,mixed_user_write_applied_count,l2_write_source,l2_status,l2_applied_count,l2_rejected_count,l2_ops_model_valid_count,l2_ops_model_rejected_count,l2_ops_suppressed_valid_count,l2_read_write_guard_active,memory_note_appended|Format-List
Write-Host '=== PHASES ==='
$t.dev4_context|Format-List
$t.dev4_phases|Select-Object phase,kind,wall_seconds,prompt_eval_count,eval_count,prompt_eval_seconds,decode_seconds,other_seconds|Format-Table -AutoSize
$answer=[string]$t.final_answer
$span='ORION RAM is now 96 GB.'
if($t.route -ne 'LOCAL' -or
    $t.l2_scope -ne 'conversation:1' -or
    $t.dev5_local_output_mode -ne 'compact-read' -or
    $t.dev5_read_policy_mode -ne 'lean-read' -or
    $t.dev5_l2_evidence_role -ne 'system-context' -or
    $t.dev4_context.l2_read_status -ne 'ok' -or
    [int]$t.dev4_context.l2_read_items -ne 3 -or
    [int]$t.dev4_context.l0_old_data_items -ne 0 -or
    [string]$t.mixed_user_evidence_status -ne 'applied-current-user' -or
    [int]$t.mixed_user_write_applied_count -ne 1 -or
    [string]$t.l2_write_source -ne 'validated-current-user' -or
    [int]$t.l2_applied_count -ne 1 -or
    [int]$t.l2_rejected_count -ne 0 -or
    -not [bool]$t.l2_read_write_guard_active -or
    [string]$t.l2_read_write_guard_reason -ne 'local-l2-retrieval-is-not-new-evidence' -or
    [int]$t.l2_ops_model_valid_count -ne 0 -or
    [int]$t.l2_ops_model_rejected_count -ne 0 -or
    [bool]$t.memory_note_appended -or
    [bool]$t.memory_compacted -or
    $answer -notmatch '(?i)\bDebian\s+13\b' -or
    $answer -match '(?i)\b256\s*GB\b|FreeBSD|Ubuntu'){
    throw 'Mixed answer, source authorization, guard or scope FAILED'
}
if([int]$t.mixed_user_evidence_start -lt 0 -or
    [int]$t.mixed_user_evidence_length -ne $span.Length -or
    $question.Substring([int]$t.mixed_user_evidence_start,[int]$t.mixed_user_evidence_length) -cne $span){
    throw 'Current-user exact source-span trace FAILED'
}
$ph=@($t.dev4_phases|Where-Object{$_.phase -eq 'local_generation'})
if($ph.Count -ne 1 -or $null -eq $ph[0].prompt_eval_count -or
    $null -eq $ph[0].eval_count -or $null -eq $ph[0].decode_seconds){
    throw 'Missing model timing/token metrics'
}
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\LfoMemoryStore.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\LfoStructuredRetrieval.ps1')
$reader=Open-LfoMemoryReadOnly $dbPath
try{
    $all=@(Invoke-LfoSqliteQuery $reader @'
SELECT f.id, f.source_turn, f.valid_from_turn, f.valid_to_turn,
 f.scope_id, f.predicate, f.value_text, f.value_integer, f.literal_type,
 (SELECT n.name FROM entity_names n WHERE n.entity_id=f.subject_entity_id ORDER BY n.id LIMIT 1) AS subject
FROM facts f ORDER BY f.id;
'@)
    $ram1=@($all|Where-Object{$_.subject -eq 'ORION' -and $_.scope_id -eq 'conversation:1' -and $_.predicate -eq 'ram_gb'})
    $os=@($all|Where-Object{$_.subject -eq 'ORION' -and $_.scope_id -eq 'conversation:1' -and $_.predicate -eq 'os'})
    $note=@($all|Where-Object{$_.subject -eq 'ORION' -and $_.scope_id -eq 'conversation:1' -and $_.predicate -eq 'operator_note'})
    $other=@($all|Where-Object{$_.subject -eq 'ORION' -and $_.scope_id -eq 'conversation:2' -and $_.predicate -eq 'ram_gb'})
    $old=@($ram1|Where-Object{[int64]$_.value_integer -eq 64 -and [int]$_.source_turn -eq 1 -and [int]$_.valid_to_turn -eq 3})
    $new=@($ram1|Where-Object{[int64]$_.value_integer -eq 96 -and [int]$_.source_turn -eq 3 -and [int]$_.valid_from_turn -eq 3 -and $null -eq $_.valid_to_turn})
    if($all.Count -ne 5 -or $ram1.Count -ne 2 -or
        $old.Count -ne 1 -or $new.Count -ne 1 -or
        $os.Count -ne 1 -or $os[0].value_text -cne 'Debian 13' -or
        $null -ne $os[0].valid_to_turn -or
        $note.Count -ne 1 -or $note[0].value_text -cne 'ORION RAM is now 256 GB.' -or
        $null -ne $note[0].valid_to_turn -or
        $other.Count -ne 1 -or [int64]$other[0].value_integer -ne 128 -or
        $null -ne $other[0].valid_to_turn -or
        @($all|Where-Object{$_.source_turn -eq 3}).Count -ne 1){
        throw 'Independent SQLite RAM64 historical -> RAM96 current, provenance or scope check FAILED'
    }
}finally{Close-LfoSqliteDatabase $reader}
$pending=Join-Path $path 'state\pending_notes.jsonl'
if((Test-Path -LiteralPath $pending) -and
    -not [string]::IsNullOrWhiteSpace([string](Get-Content -LiteralPath $pending -Raw -Encoding UTF8))){
    throw 'L1 note unexpectedly persisted'
}
Write-Host ("DEV5 MIXED LIVE: PASS; source=current-user turn3; RAM64 historical, RAM96 current; prompt={0}; generated={1}" -f [int]$ph[0].prompt_eval_count,[int]$ph[0].eval_count) -ForegroundColor Green
Write-Host 'CAUTION: exact English grammar and one sample only. No full-language or workload proof.'
