# TEMP-only integration of actual dev5 mixed-turn persistence. NO Ollama.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
foreach($name in @('src\QwenMemory.ps1','src\QwenChat.ps1','src\LfoMixedTurnEvidence.ps1','src\LfoMemoryStore.ps1')){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $name),[ref]$tokens,[ref]$errors)
    if(@($errors).Count -gt 0){throw "Parser FAILED $name : $($errors|Out-String)"}
}
. (Join-Path $repo 'src\LfoStructuredMemory.ps1')
. (Join-Path $repo 'src\LfoMixedTurnEvidence.ps1')
. (Join-Path $repo 'src\LfoMemoryStore.ps1')
. (Join-Path $repo 'src\LfoStructuredRetrieval.ps1')
. (Join-Path $repo 'src\LfoTurnTelemetry.ps1')
. (Join-Path $repo 'src\QwenMemory.ps1')
$script:Config=Import-PowerShellDataFile -LiteralPath (Join-Path $repo 'config\QwenChat.config.psd1')
$script:Config.LocalGeneration.CompactReadSchemaEnabled=$true
$script:Config.LocalGeneration.LeanReadPolicyEnabled=$true
# L2 retrieval is opt-in by default: an A+B config alone cannot enable reads.
# This test exercises mixed READ+write, so explicitly enable L2 in the
# isolated test configuration (production defaults remain unchanged).
$script:Config.Memory.StructuredReadEnabled=$true
$script:Model='offline'
$script:PolicyFingerprint='mixed-integration'
$results=@()
function Test-MixedPersist{
    param([string]$Name,[string]$Prompt,[bool]$Enable,
          [bool]$Ambiguous=$false,[bool]$Write=$false,[string]$Status='disabled')
    $root=Join-Path $env:TEMP ('LFO-dev5-mixed-integrated-'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $root -Force)
    $script:Config.Memory.DataDirectory=$root
    $script:Config.LocalGeneration.MixedUserEvidenceWriteEnabled=$Enable
    Initialize-QwenMemoryConfiguration -ContextLengthHint 5120
    if (-not $script:MemoryEnabled -or -not $script:StructuredMemoryEnabled -or
        -not $script:L2ReadEnabled) {
        throw "Isolated mixed fixture must enable Memory, StructuredMemory and L2Read: $Name"
    }
    [void](New-Item -ItemType Directory -Path $script:StateDir -Force)
    [void](New-Item -ItemType Directory -Path $script:LogDir -Force)
    [IO.File]::WriteAllText($script:WorkingMemoryPath,'')
    [IO.File]::WriteAllText($script:PendingNotesPath,'')
    $script:RuntimeState=[ordered]@{version=2;memory_schema=2;epoch=1;next_turn_id=3;completed_since_compaction=0}
    Save-RuntimeState
    $db=Open-LfoMemoryStore $script:StructuredMemoryPath
    try{
        [void](Set-LfoMemoryAttribute $db 'ORION' 'os' 'Debian 13' 1 'server' 'conversation:1')
        [void](Set-LfoMemoryAttribute $db 'ORION' 'ram_gb' ([int64]64) 1 'server' 'conversation:1')
        [void](Set-LfoMemoryAttribute $db 'ORION' 'ram_gb' ([int64]128) 1 'server' 'conversation:2')
        [void](Set-LfoMemoryAttribute $db 'ORION' 'operator_note' 'ORION RAM is now 256 GB.' 2 'server' 'conversation:1')
    }finally{Close-LfoSqliteDatabase $db}
    $script:Messages=@(@{role='system';content='TEST'},@{role='user';content=$Prompt})
    Start-LfoTurnTelemetry
    $script:LfoTurnContext=$null
    Start-LfoTurnContext $Prompt
    $contextStats=Get-LfoTurnContextStats
    if ([int]$contextStats.l2_read_items -ne 3 -or
        [string]$contextStats.l2_read_status -ne 'ok') {
        throw ("Expected 3 scoped L2 facts: {0}, got items={1}, status={2}, error={3}" -f
            $Name,$contextStats.l2_read_items,$contextStats.l2_read_status,$contextStats.l2_read_error)
    }
    if($Ambiguous){
        $db=Open-LfoMemoryStore $script:StructuredMemoryPath
        try{
            Invoke-LfoSqliteNonQuery $db 'INSERT INTO entities(entity_type,created_turn) VALUES (?1,?2);' @('server',2)
            $newId=@(Invoke-LfoSqliteQuery $db 'SELECT last_insert_rowid() AS id;')
            Invoke-LfoSqliteNonQuery $db 'INSERT INTO entity_names(entity_id,name,normalized_name,source_turn) VALUES (?1,?2,?3,?4);' @([int64]$newId[0].id,'ORION','orion',2)
        }finally{Close-LfoSqliteDatabase $db}
    }
    $raw=[pscustomobject]@{op='SET_INTEGER';subject='ORION';subject_type='server';predicate='ram_gb';target='256';target_entity_type=''}
    $echo=ConvertFrom-LfoStructuredMemoryOps -RawOps @($raw) -MaxOps 1
    $note=[pscustomobject]@{Text='ORION RAM is now 256 GB';Raw='untrusted model echo'}
    Persist-TurnAndMemory -Prompt $Prompt -FinalContent 'Debian 13' -Route 'LOCAL' -PolicyReason 'offline' -LocalRaw '{}' -FrontierResult '' -Response $null -AnswerSeconds 0 -InlineMemoryNote $note -InlineMemoryOps $echo
    $reader=Open-LfoMemoryReadOnly $script:StructuredMemoryPath
    try{
        $facts=@(Invoke-LfoSqliteQuery $reader 'SELECT id,predicate,value_integer,source_turn,scope_id,valid_to_turn FROM facts ORDER BY id;')
        $ram=@(Invoke-LfoSqliteQuery $reader @'
SELECT f.value_integer,f.source_turn,f.valid_to_turn
FROM facts f JOIN entity_names n ON n.entity_id=f.subject_entity_id
WHERE n.normalized_name='orion' AND f.predicate='ram_gb' AND f.scope_id='conversation:1'
ORDER BY f.id;
'@)
        $other=@(Invoke-LfoSqliteQuery $reader @'
SELECT f.value_integer FROM current_facts f JOIN entity_names n ON n.entity_id=f.subject_entity_id
WHERE n.normalized_name='orion' AND f.predicate='ram_gb' AND f.scope_id='conversation:2';
'@)
        if($Write){
            if($facts.Count -ne 5 -or $ram.Count -ne 2 -or [int64]$ram[0].value_integer -ne 64 -or
               [int]$ram[0].valid_to_turn -ne 3 -or [int64]$ram[1].value_integer -ne 96 -or
               [int]$ram[1].source_turn -ne 3 -or $null -ne $ram[1].valid_to_turn){
                throw "Validated user write lost scoped source-turn history: $Name"
            }
        }elseif($facts.Count -ne 4 -or $ram.Count -ne 1 -or [int64]$ram[0].value_integer -ne 64 -or $null -ne $ram[0].valid_to_turn){
            throw "No-write case mutated SQLite: $Name"
        }
        if($other.Count -ne 1 -or [int64]$other[0].value_integer -ne 128 -or
           @($facts|Where-Object{$_.predicate -eq 'ram_gb' -and [int64]$_.value_integer -eq 256}).Count -ne 0){
            throw "Model echo/other scope leaked: $Name"
        }
    }finally{Close-LfoSqliteDatabase $reader}
    $traceFiles=@(Get-ChildItem -LiteralPath $script:LogDir -Filter 'trace-*.jsonl' -File)
    $trace=@(foreach($file in $traceFiles){
        foreach($line in (Get-Content -LiteralPath $file.FullName -Encoding UTF8)){
            if(-not [string]::IsNullOrWhiteSpace($line)){$line|ConvertFrom-Json}
        }
    })
    if($trace.Count -ne 1 -or [string]$trace[0].mixed_user_evidence_status -ne $Status -or
       [int]$trace[0].mixed_user_write_applied_count -ne $(if($Write){1}else{0}) -or
       -not [bool]$trace[0].l2_read_write_guard_active -or
       [int]$trace[0].l2_ops_model_valid_count -ne 1 -or
       [int]$trace[0].l2_ops_suppressed_valid_count -ne 1 -or
       [bool]$trace[0].memory_note_appended -or [int]$trace[0].turn_id -ne 3){
        throw "Mixed audit/read guard trace incorrect: $Name"
    }
    if($Write -and ([string]$trace[0].l2_write_source -ne 'validated-current-user' -or
        [int]$trace[0].l2_applied_count -ne 1 -or [int]$trace[0].mixed_user_evidence_start -lt 0)){
        throw "Validated user provenance not audited: $Name"
    }
    if(-not $Write -and ([string]$trace[0].l2_write_source -ne 'read-guard-no-model-writes' -or
        [int]$trace[0].l2_applied_count -ne 0)){
        throw "Read guard accounting regressed: $Name"
    }
    if(-not [string]::IsNullOrWhiteSpace((Get-Content -LiteralPath $script:PendingNotesPath -Raw))){throw "L1 note leaked: $Name"}
    [pscustomobject]@{Scenario=$Name;Enabled=$Enable;UserWrite=$Write;TraceStatus=$Status;ModelEchoBlocked=$true}
}
$p='What OS does ORION run? Also, ORION RAM is now 96 GB.'
$results+=Test-MixedPersist -Name 'opted-in-user-write' -Prompt $p -Enable $true -Write $true -Status 'applied-current-user'
$results+=Test-MixedPersist -Name 'disabled-preserves-guard' -Prompt $p -Enable $false -Status 'disabled'
$results+=Test-MixedPersist -Name 'alias-collision-rejected' -Prompt $p -Enable $true -Ambiguous $true -Status 'rejected-entity-or-scope'
$results+=Test-MixedPersist -Name 'unsupported-claim-rejected' -Prompt 'What OS does ORION run? Also, ORION RAM might be 96 GB.' -Enable $true -Status 'no-verified-user-assertion'
$results|Format-Table -AutoSize
[pscustomobject]@{PASS=$true;Cases=$results.Count;RuntimeUserWriteVerified=$true;DefaultOffPreserved=$true;AmbiguityFailClosed=$true;UnverifiedClaimFailClosed=$true;ModelOpsAndL1Suppressed=$true;OllamaCalled=$false;ProductionMemoryTouched=$false}|Format-List
