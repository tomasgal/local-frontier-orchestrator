# TEMP-only LOCAL model L2 authorization boundary, including the misrouted read pilot.
# No Ollama calls, no production data, no branch changes.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
foreach($name in @('src\QwenMemory.ps1','src\LfoStructuredMemory.ps1','src\LfoMemoryStore.ps1')){
    $tok=$null;$err=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $name),[ref]$tok,[ref]$err)
    if(@($err).Count -gt 0){throw "Parser failed $name : $($err | Out-String)"}
}
. (Join-Path $repo 'src\LfoStructuredMemory.ps1')
. (Join-Path $repo 'src\LfoMemoryStore.ps1')
. (Join-Path $repo 'src\LfoStructuredRetrieval.ps1')
. (Join-Path $repo 'src\LfoMixedTurnEvidence.ps1')
. (Join-Path $repo 'src\LfoTurnTelemetry.ps1')
. (Join-Path $repo 'src\QwenMemory.ps1')
function New-TestOp([string]$Type,[string]$Subject,[string]$Predicate,[string]$Target){
    return [pscustomobject]@{op=$Type;subject=$Subject;subject_type='server';predicate=$Predicate;target=$Target;target_entity_type=''}
}
$rawDense=@(
    (New-TestOp SET_TEXT ORION os 'Ubuntu 24.04'),
    (New-TestOp SET_TEXT ORION db_version 'PostgreSQL 16'),
    (New-TestOp SET_INTEGER ORION ram_gb '64'),
    (New-TestOp SET_BOOLEAN ORION nightly_backups_enabled 'true')
)
$dense=ConvertFrom-LfoStructuredMemoryOps -RawOps $rawDense -MaxOps 6
$rawPilot=@(
    (New-TestOp SET_TEXT BENCH_SERVER operating_system 'Synthetic OS 13'),
    (New-TestOp SET_INTEGER BENCH_SERVER ram_gb '96'),
    (New-TestOp SET_INTEGER BENCH_SERVER disk_gb '512'),
    (New-TestOp SET_INTEGER BENCH_SERVER cpu_count '8')
)
$pilotOps=ConvertFrom-LfoStructuredMemoryOps -RawOps $rawPilot -MaxOps 6
$correction=ConvertFrom-LfoStructuredMemoryOps -RawOps @((New-TestOp SET_TEXT ORION os 'Debian 13')) -MaxOps 6
$relation=ConvertFrom-LfoStructuredMemoryOps -RawOps @((New-TestOp ADD_RELATION Core has_gpu GTX1050),(New-TestOp SET_INTEGER Core ram_gb '32')) -MaxOps 6
foreach($p in @($dense,$pilotOps,$correction,$relation)){
    if(@($p.Rejected).Count -ne 0 -or @($p.Valid).Count -eq 0){throw 'Invalid test-only L2 operations'}
}
$cases=@(
    [pscustomobject]@{Name='misrouted-read-original';Prompt='State BENCH_SERVER operating system, RAM in GB, disk in GB and CPU count. Reply in one short sentence.';Ops=$pilotOps;Allowed=$false},
    [pscustomobject]@{Name='imperative-with-values';Prompt='State BENCH_SERVER runs Synthetic OS 13 and has 96 GB RAM.';Ops=$pilotOps;Allowed=$false},
    [pscustomobject]@{Name='pure-read-question';Prompt='What is ORION OS?';Ops=$dense;Allowed=$false},
    [pscustomobject]@{Name='positive-dense-declaration';Prompt='ORION runs Ubuntu 24.04, uses PostgreSQL 16, has 64 GB RAM, and nightly backups are enabled.';Ops=$dense;Allowed=$true},
    [pscustomobject]@{Name='explicit-correction';Prompt='Correction: ORION now runs Debian 13 instead of Ubuntu 24.04.';Ops=$correction;Allowed=$true},
    [pscustomobject]@{Name='direct-correction';Prompt='Correction: ORION runs Debian 13 instead of Ubuntu 24.04.';Ops=$correction;Allowed=$true},
    # Build real Unicode scalars without depending on WinPS 5.1's ANSI .ps1 reader.
    [pscustomobject]@{Name='remember-declaration';Prompt=('Zapam'+[char]0x00E4+'taj si: ORION be'+[char]0x017E+[char]0x00ED+' na Debian 13.');Ops=$correction;Allowed=$true},
    [pscustomobject]@{Name='remember-ascii';Prompt='Zapamataj si: ORION bezi na Debian 13.';Ops=$correction;Allowed=$true},
    [pscustomobject]@{Name='direct-relation';Prompt='Core has a GTX1050 graphics card. Core has 32 GB RAM.';Ops=$relation;Allowed=$true},
    [pscustomobject]@{Name='model-hallucinated-target';Prompt='ORION runs Ubuntu 24.04, uses PostgreSQL 16, has 64 GB RAM, and nightly backups are enabled.';Ops=$pilotOps;Allowed=$false},
    [pscustomobject]@{Name='mixed-read-question';Prompt='What OS does ORION run? Also, ORION RAM is now 96 GB.';Ops=$pilotOps;Allowed=$false}
)
foreach($c in $cases){
    $r=Get-LfoLocalModelWriteAuthorization -Prompt $c.Prompt -Route LOCAL -ParsedOps $c.Ops
    if([bool]$r.Allowed -ne [bool]$c.Allowed){throw "Authorization case failed: $($c.Name), reason=$($r.Reason)"}
}
$frontier=Get-LfoLocalModelWriteAuthorization -Prompt 'What is ORION OS?' -Route FRONTIER -ParsedOps $dense
if(-not $frontier.Allowed){throw 'Separate FRONTIER synthesis contract changed'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('LFO-dev5-write-authority-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$script:Config=Import-PowerShellDataFile -LiteralPath (Join-Path $repo 'config\QwenChat.config.psd1')
$script:Config.LocalGeneration.MixedUserEvidenceWriteEnabled=$false
$script:Config.Memory.StructuredReadEnabled=$false
$results=@()
foreach($scenario in @('misrouted-read','positive-declaration')){
    $data=Join-Path $root $scenario
    [void](New-Item -ItemType Directory -Path $data -Force)
    $script:Config.Memory.DataDirectory=$data
    Initialize-QwenMemoryConfiguration -ContextLengthHint 5120
    if(-not $script:MemoryEnabled -or -not $script:StructuredMemoryEnabled){throw 'Isolated L2 storage disabled'}
    [void](New-Item -ItemType Directory -Path $script:StateDir -Force)
    [void](New-Item -ItemType Directory -Path $script:LogDir -Force)
    [IO.File]::WriteAllText($script:WorkingMemoryPath,'')
    [IO.File]::WriteAllText($script:PendingNotesPath,'')
    $script:RuntimeState=[ordered]@{version=2;memory_schema=2;epoch=1;next_turn_id=3;completed_since_compaction=0}
    Save-RuntimeState
    $store=Open-LfoMemoryStore $script:StructuredMemoryPath
    try {
        [void](Set-LfoMemoryAttribute $store 'BENCH_SERVER' 'os' 'Synthetic OS 13' 1 'server' 'conversation:1')
        [void](Set-LfoMemoryAttribute $store 'BENCH_SERVER' 'ram_gb' ([int64]96) 1 'server' 'conversation:1')
        [void](Set-LfoMemoryAttribute $store 'BENCH_SERVER' 'disk_gb' ([int64]512) 1 'server' 'conversation:1')
        [void](Set-LfoMemoryAttribute $store 'BENCH_SERVER' 'cpu_count' ([int64]8) 1 'server' 'conversation:1')
    } finally {Close-LfoSqliteDatabase $store}
    $isWrite=$scenario -eq 'positive-declaration'
    $prompt=if($isWrite){'ORION runs Ubuntu 24.04, uses PostgreSQL 16, has 64 GB RAM, and nightly backups are enabled.'}else{'State BENCH_SERVER operating system, RAM in GB, disk in GB and CPU count. Reply in one short sentence.'}
    $ops=if($isWrite){$dense}else{$pilotOps}
    $script:LfoTurnContext=$null
    $script:Messages=@(@{role='system';content='TEST'},@{role='user';content=$prompt})
    Start-LfoTurnTelemetry
    Persist-TurnAndMemory -Prompt $prompt -FinalContent 'offline result' -Route 'LOCAL' -PolicyReason 'offline' -LocalRaw '{}' -FrontierResult '' -Response $null -AnswerSeconds 0 -InlineMemoryNote $null -InlineMemoryOps $ops
    $read=Open-LfoMemoryReadOnly $script:StructuredMemoryPath
    try {
        $rows=@(Invoke-LfoSqliteQuery $read 'SELECT predicate,source_turn,scope_id FROM facts ORDER BY id;')
        $new=@($rows|Where-Object{[int]$_.source_turn -eq 3})
        if($rows.Count -ne $(if($isWrite){8}else{4}) -or $new.Count -ne $(if($isWrite){4}else{0})){
            throw "Unexpected SQLite mutation: $scenario"
        }
    } finally {Close-LfoSqliteDatabase $read}
    $traces=@(Get-ChildItem -LiteralPath $script:LogDir -Filter 'trace-*.jsonl' -File)
    $trace=@(foreach($file in $traces){foreach($line in (Get-Content -LiteralPath $file.FullName -Encoding UTF8)){if($line.Trim()){$line|ConvertFrom-Json}}})
    if($trace.Count -ne 1 -or
       [bool]$trace[0].l2_model_write_authorized -ne $isWrite -or
       [int]$trace[0].l2_model_ops_unauthorized_count -ne $(if($isWrite){0}else{4}) -or
       [int]$trace[0].l2_applied_count -ne $(if($isWrite){4}else{0}) -or
       [bool]$trace[0].l2_read_write_guard_active){
        throw "Authorization audit failed: $scenario"
    }
    $results+=[pscustomobject]@{Scenario=$scenario;ActualSqliteWrites=$new.Count;Authorization=[string]$trace[0].l2_model_write_authorization_reason}
}
$results|Format-Table -AutoSize
[pscustomobject]@{PASS=$true;Cases=$cases.Count;ActualPersistScenarios=2;MisroutedReadWrites=0;DeclarativeWrites=4;FrontierPolicyUnchanged=$true;ModelCalls=0;ProductionMemoryTouched=$false;TempRoot=$root}|Format-List
