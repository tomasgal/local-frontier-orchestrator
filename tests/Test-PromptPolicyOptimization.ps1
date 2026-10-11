# Deterministic v9.4 prompt/policy optimization regression.
# No Ollama call and no production memory access.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

$syntaxFiles = @(
    (Join-Path $repoRoot 'src\QwenMemory.ps1'),
    (Join-Path $repoRoot 'src\QwenChat.ps1')
)
foreach ($syntaxFile in $syntaxFiles) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $syntaxFile,
        [ref]$tokens,
        [ref]$errors
    )
    if (@($errors).Count -gt 0) {
        throw ("PowerShell syntax error in {0}: {1}" -f $syntaxFile, (($errors | ForEach-Object Message) -join '; '))
    }
}

. (Join-Path $repoRoot 'src\QwenMemory.ps1')

$config = Import-PowerShellDataFile -LiteralPath (Join-Path $repoRoot 'config\QwenChat.config.psd1')
if ([double]$config.LocalGeneration.Temperature -ne 0.10) {
    throw "Unexpected LOCAL temperature: $($config.LocalGeneration.Temperature)"
}

$l2Policy = Get-Content -LiteralPath (Join-Path $repoRoot 'policy\l2-structured-memory.txt') -Raw -Encoding UTF8
# User-requested 2040-character candidate. Count the checked-in template with
# LF newlines, including its final LF, before evidence-scope substitution.
# Windows checkout CRLF must not change the reported policy budget.
# This structural check does not establish model extraction correctness.
$l2Policy = $l2Policy.Replace("`r`n", "`n")
if ($l2Policy.Length -ne 2040) {
    throw "Unexpected L2 policy size: $($l2Policy.Length) chars; expected 2040 (LF-normalized)"
}
if ([regex]::Matches($l2Policy, [regex]::Escape('{{L2_EVIDENCE_SCOPE}}')).Count -ne 1) {
    throw 'Expected exactly one L2 evidence-scope placeholder.'
}
foreach ($required in @(
    'SET_TEXT', 'SET_INTEGER', 'SET_REAL', 'SET_BOOLEAN', 'ADD_RELATION',
    'snake_case', 'target_entity_type MUST be empty for every SET_*',
    'A correction is simply another SET_*', 'Examples:',
    'Do not infer hidden facts, beliefs, motives, preferences or uncertain claims.',
    'Do not copy facts merely because they appear in input.',
    'Extract old-context facts only if this turn re-establishes them.',
    'Do not duplicate operations within a turn.',
    'target MUST be decimal digits with an optional leading minus.',
    'No braces, brackets, units or prose:',
    'invariant decimal notation', 'target MUST be exactly true or false.',
    'surface mentions, not canonical IDs', 'Do not invent aliases or canonicalize mentions.',
    'target_entity_type is only for ADD_RELATION.',
    'Emit [] when this pass establishes no suitable L2 fact.',
    'SET_INTEGER ORION / ram_gb / 64',
    'ADD_RELATION Core / has_gpu / GTX1050 / gpu',
    'SET_TEXT GTX1050 / vendor / NVIDIA',
    'SET_BOOLEAN ORION / nightly_backups_enabled / true',
    'SET_TEXT ORION / os / Ubuntu 24.04'
)) {
    if (-not $l2Policy.Contains($required)) {
        throw "L2 policy candidate lost required contract text: $required"
    }
}

$memorySource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\QwenMemory.ps1') -Raw -Encoding UTF8
if ($memorySource.Contains('STRUCTURED OUTPUT — FINAL RULES:')) {
    throw 'Duplicated structured-output final-rules block is still present.'
}

$trueCases = @(
    'ORION runs Ubuntu 24.04, uses PostgreSQL 16, has 64 GB RAM, and nightly backups are enabled.',
    'Correction: ORION now runs Debian 13 instead of Ubuntu 24.04.',
    'Zapamätaj si: ORION beží na Debian 13.'
)
foreach ($case in $trueCases) {
    if (-not (Test-DeclarativeStateUpdatePrompt $case)) {
        throw "Expected declarative state update: $case"
    }
}

$falseCases = @(
    'What operating system does ORION run?',
    'Summarize: ORION runs Debian 13.',
    'Prosím vysvetli, prečo ORION používa Debian 13.',
    'How should I configure ORION?'
)
foreach ($case in $falseCases) {
    if (Test-DeclarativeStateUpdatePrompt $case) {
        throw "Expected generated-answer request: $case"
    }
}

$chatSource = Get-Content -LiteralPath (Join-Path $repoRoot 'src\QwenChat.ps1') -Raw -Encoding UTF8
if (-not $chatSource.Contains("local-declarative-ack")) {
    throw 'Deterministic declarative acknowledgement path is missing.'
}

[pscustomobject]@{
    PASS = $true
    LocalTemperature = [double]$config.LocalGeneration.Temperature
    L2PolicyChars = $l2Policy.Length
    L2PolicyCountConvention = 'LF-normalized file including final LF; before scope substitution'
    ModelCalls = 0
    ModelExtractionAcceptance = 'PENDING'
    DeclarativeTrueCases = $trueCases.Count
    DeclarativeFalseCases = $falseCases.Count
    ProductionMemoryTouched = $false
} | Format-List
