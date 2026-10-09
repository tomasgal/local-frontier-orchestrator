# Isolated interactive test for v9.4-dev4 selective L2 read-side.
# Never opens or modifies the production LFO data directory.
[CmdletBinding()]
param(
    [string]$Model = 'qwen3.5:4b-q4_K_M',
    [int]$ContextLengthHint = 5120,
    [switch]$CompactReadSchema,
    [switch]$SetupOnly
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$baseConfig = Join-Path $repoRoot 'config\QwenChat.config.psd1'
$template = Get-Content -LiteralPath $baseConfig -Raw -Encoding UTF8
$anchorData = "DataDirectory = '%LOCALAPPDATA%\LocalFrontierOrchestrator'"
$anchorRead = 'StructuredReadEnabled = $false'
$anchorCompact = 'CompactReadSchemaEnabled = $false'
if ($template.Split([string[]]@($anchorData),[StringSplitOptions]::None).Count -ne 2 -or
    $template.Split([string[]]@($anchorRead),[StringSplitOptions]::None).Count -ne 2) {
    throw 'Expected isolated config anchors are missing or ambiguous.'
}
if ($CompactReadSchema -and
    $template.Split([string[]]@($anchorCompact),[StringSplitOptions]::None).Count -ne 2) {
    throw 'Dev5 compact-read schema config anchor missing or ambiguous.'
}
$root = Join-Path $env:TEMP ('LFO-dev4-live-read-' + [guid]::NewGuid().ToString('N'))
$state = Join-Path $root 'state'
New-Item -ItemType Directory -Force -Path $state | Out-Null
$testConfig = Join-Path $root 'QwenChat-isolated.config.psd1'
$isolatedConfig = $template.Replace($anchorData,"DataDirectory = '$root'").Replace(
    $anchorRead,'StructuredReadEnabled = $true')
if ($CompactReadSchema) {
    $isolatedConfig = $isolatedConfig.Replace($anchorCompact,'CompactReadSchemaEnabled = $true')
}
[IO.File]::WriteAllText($testConfig,$isolatedConfig,(New-Object Text.UTF8Encoding($false)))
$configData = Import-PowerShellDataFile -LiteralPath $testConfig
if ($configData.Memory.DataDirectory -ne $root -or
    -not $configData.Memory.Enabled -or
    -not $configData.Memory.StructuredEnabled -or
    -not $configData.Memory.StructuredReadEnabled -or
    [bool]$configData.LocalGeneration.CompactReadSchemaEnabled -ne [bool]$CompactReadSchema -or
    -not $configData.ResearchLogging.Enabled) {
    throw 'Isolated L2-read config validation FAILED'
}

# Synthetic provenance: two prior turn IDs, with no raw L0 or semantic L1
# content deliberately supplied. This fixture is NOT a recovered conversation.
$runtimeState = [ordered]@{
    version = 2
    memory_schema = 2
    epoch = 1
    next_turn_id = 3
    completed_since_compaction = 0
}
[IO.File]::WriteAllText((Join-Path $state 'runtime_state.json'),
    ($runtimeState | ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $state 'working_memory.txt'),'',
    (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $state 'pending_notes.jsonl'),'',
    (New-Object Text.UTF8Encoding($false)))

. (Join-Path $repoRoot 'src\LfoMemoryStore.ps1')
. (Join-Path $repoRoot 'src\LfoStructuredRetrieval.ps1')
$dbPath = Join-Path $state 'l2-memory.db'
$db = Open-LfoMemoryStore $dbPath
try {
    [void](Set-LfoMemoryAttribute $db 'ORION' 'os' 'Ubuntu 24.04' 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $db 'ORION' 'ram_gb' ([int64]64) 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $db 'ORION' 'db_version' 'PostgreSQL 16' 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $db 'ORION' 'nightly_backups_enabled' $true 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $db 'ORION' 'os' 'Debian 13' 2 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $db 'ORION' 'os' 'FreeBSD 14' 1 'server' 'conversation:2')
    [void](Set-LfoMemoryAttribute $db 'VEGA' 'ram_gb' ([int64]128) 1 'server' 'conversation:1')
} finally {
    Close-LfoSqliteDatabase $db
}

$reader = Open-LfoMemoryReadOnly $dbPath
try {
    $facts = Get-LfoMemoryRelevantCurrentFacts $reader @('orion') 'conversation:1' 6 720
    if ($facts.Count -ne 4 -or $facts.Text -notmatch 'ORION.os = Debian 13' -or
        $facts.Text -notmatch 'ORION.ram_gb = 64' -or
        $facts.Text -notmatch 'ORION.db_version = PostgreSQL 16' -or
        $facts.Text -notmatch 'ORION.nightly_backups_enabled = true' -or
        $facts.Text -match 'Ubuntu 24.04|FreeBSD 14|VEGA') {
        throw 'Synthetic L2 fixture semantic verification FAILED'
    }
} finally {
    Close-LfoSqliteDatabase $reader
}
$global:dev4L2Root = $root
Write-Host "DEV4 READ TEST DATA: $root"
Write-Host "Isolated config: enabled; L0/L1 empty; 4 current ORION facts: PASS"
Write-Host ("Dev5 compact read schema: {0}" -f [bool]$CompactReadSchema)
Write-Host "Test prompt: What are the stored OS, RAM, database and nightly backup facts for ORION?"
Write-Host "After the answer, enter /exit; inspect logs and database independently."
if (-not $SetupOnly) {
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'src\QwenChat.ps1') -ConfigPath $testConfig -Model $Model -ContextLengthHint $ContextLengthHint
    if ($LASTEXITCODE -ne 0) { throw "QwenChat exited with code $LASTEXITCODE" }
}
