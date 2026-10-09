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
# The compact-policy experiment failed the unchanged extraction battery on
# a CPU-only reference host. Freeze the previously validated full policy:
# textual shortness alone is not a correctness acceptance criterion.
if ($l2Policy.Length -lt 1800 -or $l2Policy.Length -gt 3000) {
    throw "Unexpected full-baseline L2 policy size: $($l2Policy.Length) chars"
}
foreach ($required in @(
    'SET_TEXT', 'SET_INTEGER', 'SET_REAL', 'SET_BOOLEAN', 'ADD_RELATION',
    'snake_case', 'target_entity_type MUST be empty for every SET_*',
    'A correction is simply another SET_*', 'Examples:'
)) {
    if (-not $l2Policy.Contains($required)) {
        throw "Full-baseline L2 policy lost required contract text: $required"
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
    DeclarativeTrueCases = $trueCases.Count
    DeclarativeFalseCases = $falseCases.Count
    ProductionMemoryTouched = $false
} | Format-List
