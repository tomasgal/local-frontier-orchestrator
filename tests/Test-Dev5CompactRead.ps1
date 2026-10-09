# Dev5 candidate A: opt-in output schema compaction on L2-assisted read turns.
# Offline only. Never opens SQLite or production files, and never calls Ollama.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($relative in @('src\QwenChat.ps1','src\QwenMemory.ps1','src\LfoStructuredMemory.ps1')) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root $relative),[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) {
        throw ("Parser failure {0}: {1}" -f $relative,(($errors | ForEach-Object Message) -join '; '))
    }
}
. (Join-Path $root 'src\QwenMemory.ps1')
. (Join-Path $root 'src\LfoStructuredMemory.ps1')
# Import function definitions only; do NOT dot-source the interactive CLI.
$chat = Get-Content -LiteralPath (Join-Path $root 'src\QwenChat.ps1') -Raw -Encoding UTF8
$schemaDefinition = [regex]::Match(
    $chat,'(?ms)^function Get-QwenLocalOutputFormat \{.*?(?=^function Get-QwenSynthesisOutputFormat \{)')
# Both compact and full requests must pass through identical low-overhead
# timing markers. Static verification avoids invoking the interactive CLI.
foreach ($requiredMarker in @(
    "Add-LfoTurnPhase -Phase 'local_request_build'",
    "Add-LfoTurnPhase -Phase 'local_response_processing'",
    "return Invoke-LfoChatApi -Phase 'local_generation'"
)) {
    if (-not $chat.Contains($requiredMarker)) {
        throw "Dev5 LOCAL timing invariant missing: $requiredMarker"
    }
}
if (-not $schemaDefinition.Success) { throw 'Cannot isolate LOCAL schema declaration' }
Invoke-Expression $schemaDefinition.Value
$parseDefinition = [regex]::Match(
    $chat,'(?ms)^function ConvertFrom-QwenStructuredContent\(.*?(?=^# Measure the existing request)')
if (-not $parseDefinition.Success) { throw 'Cannot isolate LOCAL result parser' }
Invoke-Expression $parseDefinition.Value

$script:Config = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'config\QwenChat.config.psd1')
$script:MemoryNoteMaxChars = 40
$script:L2ReadEnabled = $true
$script:Config.LocalGeneration.CompactReadSchemaEnabled = $false
$script:LfoTurnContext = [pscustomobject]@{
    Query = 'What is the stored OS for ORION?'
    MemoryBlock = "STATE:`nPENDING:`nCURRENT STRUCTURED FACTS (L2):`nORION.os = Debian 13 [scope=conversation:1; source_turn=2]"
    Stats = [pscustomobject]@{ l2_read_items = 4 }
    RecentMessages = @(@{ role='user'; content='What is the stored OS for ORION?' })
}
function Get-OrchestratorSystemPrompt { return 'ORCHESTRATOR TEST POLICY' }
$script:L2StructuredMemoryTemplate = 'VALIDATED L2 EVIDENCE POLICY: {{L2_EVIDENCE_SCOPE}}'
$script:Messages = @(@{ role='system';content='TEST'},@{role='user';content='What is the stored OS for ORION?'})

$full = Get-QwenLocalOutputFormat
$fullChars = ($full | ConvertTo-Json -Depth 14 -Compress).Length
if ((Test-LfoDev5CompactReadEligible) -or
    @($full.required).Count -ne 4 -or
    @($full.properties.Keys).Count -ne 4 -or
    $null -eq $full.properties.memory_ops -or
    $null -eq $full.properties.memory_note) { throw 'Default full schema changed' }
$baselineMessages = @(Get-QwenConversationMessages)
if ([string]$baselineMessages[0].content -match 'DEV5 READ-ONLY OUTPUT OVERRIDE') {
    throw 'Default mode should not inject compact read override'
}

$script:Config.LocalGeneration.CompactReadSchemaEnabled = $true
$compact = Get-QwenLocalOutputFormat
$compactChars = ($compact | ConvertTo-Json -Depth 14 -Compress).Length
if (-not (Test-LfoDev5CompactReadEligible) -or
    @($compact.required).Count -ne 2 -or
    $compact.required -notcontains 'route' -or
    $compact.required -notcontains 'answer' -or
    @($compact.properties.Keys).Count -ne 2 -or
    $null -ne $compact.properties.memory_ops -or
    $null -ne $compact.properties.memory_note -or
    $compactChars -ge $fullChars) { throw 'Compact schema contract FAILED' }
$messages = @(Get-QwenConversationMessages)
if ([string]$messages[0].content -notmatch 'DEV5 READ-ONLY OUTPUT OVERRIDE' -or
    [string]$messages[0].content -notmatch 'VALIDATED L2 EVIDENCE POLICY' -or
    [string]$messages[0].content -notmatch 'ORION.os = Debian 13' -or
    $messages.Count -ne $baselineMessages.Count) { throw 'Read output policy assembly FAILED' }

# The same parser must still understand route+answer with missing memory fields.
$parsed = ConvertFrom-QwenStructuredContent '{"route":"LOCAL","answer":"ORION runs Debian 13."}' -ExpectRoute
if (-not $parsed.Success -or $parsed.Route -ne 'LOCAL' -or
    $parsed.Answer -ne 'ORION runs Debian 13.' -or
    @($parsed.MemoryOps.Valid).Count -ne 0 -or
    @($parsed.MemoryOps.Rejected).Count -ne 0 -or
    -not [string]::IsNullOrWhiteSpace([string]$parsed.MemoryNote.Text)) {
    throw 'Existing LOCAL parser rejected compact route+answer'
}
$frontier = ConvertFrom-QwenStructuredContent '{"route":"FRONTIER","answer":""}' -ExpectRoute
if (-not $frontier.Success -or $frontier.Route -ne 'FRONTIER' -or
    @($frontier.MemoryOps.Valid).Count -ne 0) { throw 'Compact FRONTIER route parsing FAILED' }

# Zero L2 hits, disabled L2 retrieval, or disabled feature must all retain the
# complete, validated memory schema. No implicit model-write behavior changes.
$script:LfoTurnContext.Stats.l2_read_items = 0
if ((Test-LfoDev5CompactReadEligible) -or (Get-QwenLocalOutputFormat).required.Count -ne 4) {
    throw 'No-L2-hit fell into compact schema'
}
$script:LfoTurnContext.Stats.l2_read_items = 4
$script:L2ReadEnabled = $false
if ((Test-LfoDev5CompactReadEligible) -or (Get-QwenLocalOutputFormat).required.Count -ne 4) {
    throw 'L2-disabled mode fell into compact schema'
}
$script:L2ReadEnabled = $true
$script:Config.LocalGeneration.CompactReadSchemaEnabled = $false
if ((Test-LfoDev5CompactReadEligible) -or (Get-QwenLocalOutputFormat).required.Count -ne 4) {
    throw 'Feature-disabled mode fell into compact schema'
}

[pscustomobject]@{
    PASS = $true
    FullSchemaChars = $fullChars
    CompactSchemaChars = $compactChars
    SchemaCharactersRemoved = ($fullChars - $compactChars)
    ReadOnlyEligibility = '4 L2 items + explicit opt-in'
    NormalWriteSchemaPreserved = $true
    FrontierRoutingPreserved = $true
    ExistingParserAcceptsCompact = $true
    OllamaCalled = $false
    TimingPhasesDeclared = 2
    ProductionMemoryTouched = $false
} | Format-List
