# TEMP-only orchestration + real JSONL persistence; all model transports stubbed.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'src/QwenChat.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
# Load functions without running the interactive application/bootstrap.
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}
. (Join-Path $repo 'src/LfoStructuredMemory.ps1')
. (Join-Path $repo 'src/LfoTurnTelemetry.ps1')
. (Join-Path $repo 'src/QwenMemory.ps1')
. (Join-Path $repo 'src/LfoL3Runtime.ps1')
function Get-LfoL3L0Locators { return $script:FixtureLocator }
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Refresh-SystemPrompt {}
function Trim-Messages {}
function Start-LfoTurnContext {}
function Get-HardGateContext { return '' }
function Get-RecentConversationText { return '' }
function Get-LfoTurnMemoryBlock { return '' }
function Get-LfoTurnRetrievedOldData { return '' }
function Get-FrontierPolicyReason { if ($script:HardGate) { return 'fixture' }; return '' }
function New-FixtureResponse([string]$Content, [string]$Done = 'stop') {
    return [pscustomobject]@{message=@{content=$Content};done_reason=$Done;eval_count=1;eval_duration=1;prompt_eval_count=1}
}
function Invoke-QwenLocalApi { $script:Calls += 'local'; return (New-FixtureResponse $script:LocalText) }
function Invoke-QwenSynthesis { $script:Calls += 'synthesis'; return (New-FixtureResponse $script:SynthesisText $script:SynthesisDone) }
function Invoke-QwenAnswerRecovery { $script:Calls += 'recovery'; return (New-FixtureResponse $script:RecoveryText) }
function Invoke-CodexReadOnly {
    $script:Calls += 'frontier'
    if ($script:FrontierFails) { throw 'fixture transport failure' }
    return $script:FrontierText
}
function Invoke-QwenMemoryNote { throw 'Unexpected memory-model call' }
function Invoke-MemoryCompaction { throw 'Unexpected compaction-model call' }

$root = Join-Path ([IO.Path]::GetTempPath()) ('LFO-l0-stages-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$reader = Join-Path $root 'Read-Fixture.ps1'
Set-Content -LiteralPath $reader -Encoding UTF8 -Value 'param([string]$Path) $ErrorActionPreference="Stop"; $r=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json; if($r.stage_sources_schema -ne 1 -or @($r.stage_sources).Count -lt 3){exit 1}'
$script:Model = 'fixture-local'
$script:ThinkEnabled = $false
$passed = 0
try {
    foreach ($case in @('local','recovery','recovery_failed','synthesis','routed_synthesis','fallback','invalid_synthesis','frontier_failed','malformed','sentinel')) {
        $pair = @()
        foreach ($enabled in @($false, $true)) {
            $script:Config = Import-PowerShellDataFile (Join-Path $repo 'config/QwenChat.config.psd1')
            $script:Config.Memory.DataDirectory = Join-Path $root ($case + '-' + $enabled)
            $script:Config.Memory.L0StageSourcesEnabled = $enabled
            $script:Config.Memory.StructuredEnabled = $false
            $script:Config.ResearchLogging.Enabled = $false
            Initialize-QwenMemoryConfiguration
            $script:RuntimeState = New-DefaultRuntimeState
            $script:Messages = @()
            $script:Calls = @()
            $script:HardGate = $case -in @('synthesis','fallback','invalid_synthesis','frontier_failed')
            $script:FrontierFails = $case -eq 'frontier_failed'
            $script:FrontierText = 'Independent frontier answer.'
            $script:LocalText = '{"route":"LOCAL","answer":"Local answer.","memory_note":"-","memory_ops":[]}'
            $script:SynthesisText = '{"answer":"Synthesized answer.","memory_note":"-","memory_ops":[]}'
            $script:SynthesisDone = $(if ($case -eq 'fallback') { 'length' } else { 'stop' })
            $script:RecoveryText = '{"answer":"Recovered answer."}'
            if ($case -in @('recovery','recovery_failed')) { $script:LocalText = '{"route":"LOCAL","answer":"-","memory_note":"-","memory_ops":[]}' }
            if ($case -eq 'recovery_failed') { $script:RecoveryText = '{"answer":"-"}' }
            if ($case -eq 'invalid_synthesis') { $script:SynthesisText = '{"answer":"-","memory_note":"-","memory_ops":[]}' }
            if ($case -eq 'routed_synthesis') { $script:LocalText = '{"route":"FRONTIER","answer":"","memory_note":"-","memory_ops":[]}' }
            if ($case -eq 'malformed') { $script:LocalText = 'Unstructured answer.' }
            if ($case -eq 'sentinel') { $script:LocalText = '-' }
            $prompt = 'Explain ' + [char]0x017E + [char]0x00F4 + "`nsecond line?"
            Invoke-Qwen $prompt | Out-Null
            $file = Get-MonthlyLogPath 'conversation'
            $row = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            Assert ($row.user -ceq $prompt) 'Unicode/newline source changed'
            Assert ($row.turn_id -eq 1 -and $row.epoch -eq 1) 'Turn identity changed'
            Assert (@(Get-ChildItem $script:LogDir -Filter 'trace-*').Count -eq 0) 'Research trace unexpectedly required'
            Assert (-not (Test-Path $script:StructuredMemoryPath)) 'Unexpected L2 DB'
            Assert (-not (Test-Path $script:PendingNotesPath)) 'Unexpected L1 note'
            $candidate = [pscustomobject]@{Id=1;SourceLayer='L0';SourceRef='turn:1'}
            $scan = @(Get-LfoL3RuntimeL0Evidence @($candidate) $script:LogDir 1)
            $script:FixtureLocator = [pscustomobject]@{item_id=1;source_file=[IO.Path]::GetFileName($file);byte_offset=0;byte_length=(Get-Item $file).Length}
            $direct = @(Get-LfoL3RuntimeL0Evidence @($candidate) $script:LogDir 1 'fixture')
            Assert ($scan.Count -eq 1 -and $direct.Count -eq 1 -and $scan[0].Text -ceq $direct[0].Text) 'L3 locator/scan evidence differs'
            Assert ($direct[0].Text -notmatch 'stage_sources|memory_ops') 'Stage data leaked into L3 evidence'
            if ($enabled) {
                Assert ($row.stage_sources_schema -eq 1) 'Missing stage schema'
                $sources = @($row.stage_sources)
                Assert ($sources[0].actor -eq 'USER' -and $sources[0].source_field -eq 'user') 'USER reference missing'
                Assert ($sources[-1].actor -eq 'FINAL' -and $sources[-1].source_field -eq 'assistant') 'FINAL reference missing'
                Assert (-not ($sources[0].PSObject.Properties.Name -contains 'content')) 'USER duplicated'
                Assert (-not ($sources[-1].PSObject.Properties.Name -contains 'content')) 'FINAL duplicated'
                for ($i=0; $i -lt $sources.Count; $i++) { Assert ($sources[$i].stage_id -eq ('s' + ($i+1))) 'Stage sequence invalid' }
                if ($case -in @('synthesis','routed_synthesis','fallback','invalid_synthesis')) {
                    $synthesis = @($sources | Where-Object { $_.actor -eq 'LOCAL' -and $_.phase -eq 'synthesis' })
                    Assert ($synthesis.Count -eq 1 -and $synthesis[0].content -ceq $script:SynthesisText) 'Synthesis output lost'
                    $frontier = @($sources | Where-Object actor -eq 'FRONTIER')
                    Assert ($frontier.Count -eq 1 -and $frontier[0].content -ceq $script:FrontierText) 'Frontier output lost'
                }
                if ($case -in @('recovery','recovery_failed')) {
                    $recovery = @($sources | Where-Object { $_.actor -eq 'LOCAL' -and $_.phase -eq 'answer_recovery' })
                    Assert ($recovery.Count -eq 1 -and $recovery[0].content -ceq $script:RecoveryText) 'Recovery output lost'
                    Assert ($sources[1].content -ceq $script:LocalText) 'Original sentinel output lost'
                }
                $producer = switch ($case) {
                    {$_ -in @('fallback','invalid_synthesis')} { 'FRONTIER'; break }
                    {$_ -in @('frontier_failed','sentinel','recovery_failed')} { 'WRAPPER'; break }
                    default { 'LOCAL' }
                }
                Assert ($sources[-1].producer -eq $producer) ('Wrong final producer: ' + $case)
                if ($case -eq 'frontier_failed') { Assert ($sources[1].status -eq 'failed' -and $sources[1].producer -eq 'WRAPPER') 'Transport error attributed to model' }
                if ($script:HardGate) { Assert (@($sources | Where-Object phase -eq 'initial').Count -eq 0) 'Invented skipped LOCAL stage' }
                # Read again in a fresh process: actual persisted JSONL, no session state.
                $engineName = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } elseif ($env:OS -eq 'Windows_NT') { 'pwsh.exe' } else { 'pwsh' }
                $engine = Join-Path $PSHOME $engineName
                & $engine -NoProfile -ExecutionPolicy Bypass -File $reader -Path $file
                Assert ($LASTEXITCODE -eq 0) 'Fresh-process read failed'
            } else {
                Assert (-not ($row.PSObject.Properties.Name -contains 'stage_sources')) 'OFF added source data'
                Assert (-not ($row.PSObject.Properties.Name -contains 'stage_sources_schema')) 'OFF changed schema'
            }
            $pair += [pscustomobject]@{Answer=$row.assistant;Route=$row.route;Calls=($script:Calls -join ',');Evidence=$direct[0].Text}
        }
        Assert (($pair[0] | ConvertTo-Json -Compress) -ceq ($pair[1] | ConvertTo-Json -Compress)) ('OFF/ON behavior differs: ' + $case)
        $passed++
    }
    # Old configs and memory-disabled configurations must remain inert.
    $script:Config.Memory.Remove('L0StageSourcesEnabled')
    Initialize-QwenMemoryConfiguration
    Assert (-not $script:L0StageSourcesEnabled) 'Old config enabled capture'
    $script:Config.Memory.L0StageSourcesEnabled = $true
    $script:Config.Memory.Enabled = $false
    Initialize-QwenMemoryConfiguration
    Assert (-not $script:L0StageSourcesEnabled) 'Capture enabled without authoritative L0'
    [pscustomobject]@{PASS=$true;Cases=$passed;Variants=20;ModelCalls=0;ProductionMemoryTouched=$false}
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
