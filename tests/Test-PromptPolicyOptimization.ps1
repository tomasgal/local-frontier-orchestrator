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

# Check repository defaults before any test fixture overrides them. The
# compact-read suite deliberately sets A/B/C itself, so it cannot prove this.
$defaultOff = [ordered]@{
    StructuredReadEnabled = $config.Memory.StructuredReadEnabled
    CompactReadSchemaEnabled = $config.LocalGeneration.CompactReadSchemaEnabled
    LeanReadPolicyEnabled = $config.LocalGeneration.LeanReadPolicyEnabled
    LowerTrustL2EvidenceEnabled = $config.LocalGeneration.LowerTrustL2EvidenceEnabled
    MixedUserEvidenceWriteEnabled = $config.LocalGeneration.MixedUserEvidenceWriteEnabled
}
foreach ($name in $defaultOff.Keys) {
    if ($defaultOff[$name] -isnot [bool] -or $defaultOff[$name] -ne $false) {
        throw "Experimental repository default must be boolean false: $name"
    }
}

$l2Policy = Get-Content -LiteralPath (Join-Path $repoRoot 'policy\l2-structured-memory.txt') -Raw -Encoding UTF8
# Conservative integration restores the pinned full policy; check exact LF bytes.
$l2Policy = $l2Policy.Replace("`r`n", "`n")
$sha = [Security.Cryptography.SHA256]::Create()
try {$actual = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($l2Policy))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
if ($l2Policy.Length -ne 2414 -or $actual -cne 'e569f902206f03a2318aed4de97ba4d62766ce89824ccac6fee3a5ea877a45ec') {
    throw 'Conservative full policy differs from pinned reference.'
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
    DefaultOffFlagsChecked = $defaultOff.Count
    L2PolicyChars = $l2Policy.Length
    L2PolicyCountConvention = 'LF-normalized file including final LF; before scope substitution'
    ModelCalls = 0
    ModelExtractionAcceptance = 'PENDING'
    DeclarativeTrueCases = $trueCases.Count
    DeclarativeFalseCases = $falseCases.Count
    ProductionMemoryTouched = $false
} | Format-List
