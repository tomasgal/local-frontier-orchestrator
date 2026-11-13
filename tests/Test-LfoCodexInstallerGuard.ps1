# v9.6.4 regression test for the real bootstrap's Codex installer try/finally block.
# Extracts the block from source and runs it under command mocks; no installer executes.
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$BootstrapPath)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $BootstrapPath -PathType Leaf)) {
    throw "Bootstrap script is missing: $BootstrapPath"
}

$source = Get-Content -LiteralPath $BootstrapPath -Raw -Encoding UTF8
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) { throw 'Bootstrap did not parse cleanly.' }

$matches = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.TryStatementAst] -and
    $node.Extent.Text.Contains('Codex installer SHA-256 mismatch: refusing to execute unverified installer.')
}, $true))
if ($matches.Count -ne 1) {
    throw "Expected exactly one Codex integrity try/finally block; found $($matches.Count)."
}
$blockText = $matches[0].Extent.Text
$hashPosition = $blockText.IndexOf('Get-Sha256 $codexInstaller', [StringComparison]::Ordinal)
$verifyPosition = $blockText.IndexOf('Assert-Lfo ($actualCodexInstallerSHA256 -ceq $CodexInstallerSHA256)', [StringComparison]::Ordinal)
$executePosition = $blockText.IndexOf('$installProc=Start-Process powershell.exe', [StringComparison]::Ordinal)
if ($hashPosition -lt 0 -or $verifyPosition -lt $hashPosition -or $executePosition -lt $verifyPosition) {
    throw 'Missing or reordered bootstrap hash check; refusing to test a different code path.'
}
$guardBlock = [scriptblock]::Create($blockText)

# The only file writes are a synthetic payload under this fresh, disposable directory.
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('lfo-codex-integrity-test-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop)
$codexInstaller = Join-Path $testRoot 'synthetic-installer.ps1'
$CodexInstallerUrl = 'mock://codex-installer'
$script:MockPayload = 'LFO_TEST_DATA_ONLY_NOT_EXECUTABLE_INSTALLER'
$script:MockStartProcessCalls = 0

# These functions shadow the real network and process execution commands inside the extracted block.
function Info { param([string]$Text) }
function Assert-Lfo { param($Value, [string]$Message) if (-not [bool]$Value) { throw $Message } }
function Get-Sha256 { param([string]$Path) return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Invoke-WebRequest {
    param([switch]$UseBasicParsing, [string]$Uri, [string]$OutFile)
    if ($Uri -cne 'mock://codex-installer') { throw 'Unexpected download target.' }
    [IO.File]::WriteAllBytes($OutFile, [Text.Encoding]::ASCII.GetBytes($script:MockPayload))
}
function Start-Process {
    param([Parameter(Position = 0)][string]$FilePath, [switch]$Wait,
        [switch]$PassThru, [switch]$NoNewWindow, [string[]]$ArgumentList)
    $script:MockStartProcessCalls++
    return [pscustomobject]@{ ExitCode = 0 }
}

try {
    # Negative case: intentionally wrong hash must fail before Start-Process.
    $CodexInstallerSHA256 = ('0' * 64)
    $failure = $null
    try { & $guardBlock } catch { $failure = $_.Exception.Message }
    if ($failure -notlike '*SHA-256 mismatch*') {
        throw "FAIL: wrong-hash path did not produce the expected failure: $failure"
    }
    if ($script:MockStartProcessCalls -ne 0) {
        throw 'FAIL: Start-Process was invoked after a hash mismatch.'
    }
    if (Test-Path -LiteralPath $codexInstaller) {
        throw 'FAIL: temporary installer was not removed after rejection.'
    }
    Write-Output 'PASS: wrong hash rejected before Start-Process; temporary file cleaned'

    # Positive case: matching hash should reach ONLY our fake Start-Process.
    $bytes = [Text.Encoding]::ASCII.GetBytes($script:MockPayload)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $CodexInstallerSHA256 = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    try { & $guardBlock } catch { throw "FAIL: matching hash did not pass: $($_.Exception.Message)" }
    if ($script:MockStartProcessCalls -ne 1) {
        throw "FAIL: expected one mocked Start-Process call; got $script:MockStartProcessCalls."
    }
    if (Test-Path -LiteralPath $codexInstaller) {
        throw 'FAIL: temporary installer was not removed after success.'
    }
    Write-Output 'PASS: matching hash reaches mocked Start-Process; temporary file cleaned'
    Write-Output 'PASS: bootstrap integrity guard regression tests completed (no real installer executed)'
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
