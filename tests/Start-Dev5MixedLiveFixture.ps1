# Dev5 mixed-turn live fixture: TEMP-only RAM64 -> user RAM96, A+B read with mixed write opt-in.
[CmdletBinding()]
param(
    [switch]$SetupOnly,
    [string]$Model='qwen3.5:4b-q4_K_M',
    [int]$ContextLengthHint=5120
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$defaultConfig=Join-Path $repo 'config\QwenChat.config.psd1'
$template=Get-Content -LiteralPath $defaultConfig -Raw -Encoding UTF8
$root=Join-Path $env:TEMP ('LFO-dev5-mixed-live-'+[guid]::NewGuid().ToString('N'))
$state=Join-Path $root 'state'
[void](New-Item -ItemType Directory -Path $state -Force)
$replacements=[ordered]@{
    "DataDirectory = '%LOCALAPPDATA%\LocalFrontierOrchestrator'" = "DataDirectory = '$root'"
    'StructuredReadEnabled = $false' = 'StructuredReadEnabled = $true'
    'CompactReadSchemaEnabled = $false' = 'CompactReadSchemaEnabled = $true'
    'LeanReadPolicyEnabled = $false' = 'LeanReadPolicyEnabled = $true'
    'MixedUserEvidenceWriteEnabled = $false' = 'MixedUserEvidenceWriteEnabled = $true'
}
foreach($anchor in @($replacements.Keys)){
    if($template.Split([string[]]@($anchor),[StringSplitOptions]::None).Count -ne 2){
        throw "Missing/ambiguous isolated config anchor: $anchor"
    }
    $template=$template.Replace([string]$anchor,[string]$replacements[$anchor])
}
$configPath=Join-Path $root 'QwenChat-isolated.config.psd1'
[IO.File]::WriteAllText($configPath,$template,(New-Object Text.UTF8Encoding($false)))
$cfg=Import-PowerShellDataFile -LiteralPath $configPath
if([IO.Path]::GetFullPath([string]$cfg.Memory.DataDirectory) -ine [IO.Path]::GetFullPath($root) -or
    -not [bool]$cfg.Memory.Enabled -or
    -not [bool]$cfg.Memory.StructuredEnabled -or
    -not [bool]$cfg.Memory.StructuredReadEnabled -or
    -not [bool]$cfg.LocalGeneration.CompactReadSchemaEnabled -or
    -not [bool]$cfg.LocalGeneration.LeanReadPolicyEnabled -or
    [bool]$cfg.LocalGeneration.LowerTrustL2EvidenceEnabled -or
    -not [bool]$cfg.LocalGeneration.MixedUserEvidenceWriteEnabled -or
    -not [bool]$cfg.ResearchLogging.Enabled -or
    -not [bool]$cfg.ResearchLogging.IncludeRawText){
    throw 'Isolated A+B+mixed write config mismatch'
}
$runtimeState=[ordered]@{
    version=2;memory_schema=2;epoch=1;next_turn_id=3;completed_since_compaction=0
}
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $state 'runtime_state.json'),($runtimeState|ConvertTo-Json -Depth 5),$utf8)
[IO.File]::WriteAllText((Join-Path $state 'working_memory.txt'),'',$utf8)
[IO.File]::WriteAllText((Join-Path $state 'pending_notes.jsonl'),'',$utf8)
. (Join-Path $repo 'src\LfoMemoryStore.ps1')
. (Join-Path $repo 'src\LfoStructuredRetrieval.ps1')
$dbPath=Join-Path $state 'l2-memory.db'
$db=Open-LfoMemoryStore $dbPath
try{
    [void](Set-LfoMemoryAttribute $db 'ORION' 'os' 'Debian 13' 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $db 'ORION' 'ram_gb' ([int64]64) 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $db 'ORION' 'ram_gb' ([int64]128) 1 'server' 'conversation:2')
    [void](Set-LfoMemoryAttribute $db 'ORION' 'operator_note' 'ORION RAM is now 256 GB.' 2 'server' 'conversation:1')
}finally{Close-LfoSqliteDatabase $db}
$reader=Open-LfoMemoryReadOnly $dbPath
try{
    $e=Get-LfoMemoryRelevantCurrentFacts $reader @('orion') 'conversation:1' 6 720
    $rows=@(Invoke-LfoSqliteQuery $reader 'SELECT id FROM facts ORDER BY id;')
    if($rows.Count -ne 4 -or [int]$e.Count -ne 3 -or
        $e.Text -notmatch 'ORION.os = Debian 13' -or
        $e.Text -notmatch 'ORION.ram_gb = 64' -or
        $e.Text -notmatch 'ORION.operator_note = ORION RAM is now 256 GB' -or
        $e.Text -match '128' ){
        throw 'Mixed fixture preflight failed: current scoped records must be OS Debian13, RAM64 and note RAM256 only'
    }
}finally{Close-LfoSqliteDatabase $reader}
$global:dev5MixedLiveRoot=$root
Write-Host "DEV5 MIXED LIVE TEMP ROOT: $root"
Write-Host 'Isolated flags: StructuredRead=true, A=true, B=true, C=false, MixedUserEvidenceWrite=true'
Write-Host 'Preflight scoped L2 facts: ORION.os=Debian 13, ORION.ram_gb=64, ORION.operator_note RAM256 (UNTRUSTED decoy)'
Write-Host 'Other conversation RAM128 excluded. Expected after one turn: RAM64 historical, RAM96 current at source_turn3.'
Write-Host 'At Qwen>, type EXACTLY: What OS does ORION run? Also, ORION RAM is now 96 GB.'
Write-Host 'Then type /exit. Parent shell should invoke Test-Dev5MixedLiveTrace.ps1 afterwards.'
if(-not $SetupOnly){
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'src\QwenChat.ps1') -ConfigPath $configPath -Model $Model -ContextLengthHint $ContextLengthHint
    if($LASTEXITCODE -ne 0){throw "Qwen mixed live session exited $LASTEXITCODE"}
}
