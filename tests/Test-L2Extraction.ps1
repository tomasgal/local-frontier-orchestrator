# Isolated v9.4-dev2 model extraction probe.
# Calls local Ollama but does not touch any LFO memory database.

param(
    [string]$Model,
    [string]$ConfigPath,
    [string]$PolicyPath,
    [double]$Temperature = [double]::NaN,
    [int]$ContextLength = 5120,
    [int]$NumThreads = 1,
    [string]$EvidenceDirectory,
    [string]$ExpectedDigest
)

$ErrorActionPreference = 'Stop'
# This is an extraction probe, not acceptance of an epistemic/bias mediator.
# Select its sampling profile explicitly; never silently reuse it as a global
# LOCAL/FRONTIER synthesis setting. Missing values fail without a UI prompt.
if ([double]::IsNaN($Temperature) -or [double]::IsInfinity($Temperature) -or $Temperature -lt 0) {
    throw 'Specify an explicit finite non-negative -Temperature for this extraction probe.'
}
if ($ContextLength -lt 1) { throw 'ContextLength must be positive.' }
if ($NumThreads -lt 1) { throw 'NumThreads must be positive.' }
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path ([IO.Path]::GetTempPath()) ('LFO-r2-evidence-' + [guid]::NewGuid().ToString('N'))
}
$null = New-Item -ItemType Directory -Path $EvidenceDirectory -Force

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $repoRoot 'config\QwenChat.config.psd1'
}
$config = Import-PowerShellDataFile -LiteralPath $ConfigPath
if ([string]::IsNullOrWhiteSpace($Model)) {
    $Model = [string]$config.Model
}
$baseUri = [string]$config.BaseUri

. (Join-Path $repoRoot 'src\LfoStructuredMemory.ps1')

if ([string]::IsNullOrWhiteSpace($PolicyPath)) { $PolicyPath = Join-Path $repoRoot 'policy\l2-structured-memory.txt' }
$policyTemplate = Get-Content -LiteralPath $PolicyPath -Raw -Encoding UTF8
# Parser regression: the only tolerated malformed integer spelling is one
# exact brace wrapper around an otherwise valid integer.
$parserProbe = ConvertFrom-LfoStructuredMemoryOps @(
    [pscustomobject]@{
        op = 'SET_INTEGER'
        subject = 'Core'
        subject_type = 'computer'
        predicate = 'ram_gb'
        target = '{32}'
        target_entity_type = ''
    }
) 6
if (@($parserProbe.Valid).Count -ne 1 -or
    [int64]$parserProbe.Valid[0].TypedValue -ne 32 -or
    $parserProbe.Valid[0].Normalization -ne 'brace-wrapped-integer') {
    throw 'Brace-wrapped integer parser regression failed.'
}

$schema = @{
    type = 'object'
    properties = @{
        memory_ops = Get-LfoStructuredMemoryOperationSchema 6
    }
    required = @('memory_ops')
    additionalProperties = $false
}

$localScope = @'
This is a LOCAL pass. The evidence is only the CURRENT USER TURN.
'@

$synthesisScope = @'
This is a post-frontier SYNTHESIS pass. The evidence is the ORIGINAL USER REQUEST plus the FRONTIER RESULT.
Interpret both inputs and emit only durable factual state accepted after synthesis; do not mechanically copy every frontier detail.
'@

$cases = @(
    [pscustomobject]@{
        Name = 'multi-attribute'
        EvidenceScope = $localScope
        Prompt = 'ORION runs Ubuntu 24.04, uses PostgreSQL 16, has 64 GB RAM, and nightly backups are enabled.'
    },
    [pscustomobject]@{
        Name = 'relation'
        EvidenceScope = $localScope
        Prompt = 'Core has a GTX1050 graphics card. GTX1050 is NVIDIA. Core has 32 GB RAM.'
    },
    [pscustomobject]@{
        Name = 'correction'
        EvidenceScope = $localScope
        Prompt = 'Correction: ORION now runs Debian 13 instead of Ubuntu 24.04.'
    },
    [pscustomobject]@{
        Name = 'no-l2'
        EvidenceScope = $localScope
        Prompt = 'Prefer short technical answers and one CLI command per step.'
    },
    [pscustomobject]@{
        Name = 'frontier-synthesis'
        EvidenceScope = $synthesisScope
        Prompt = @'
ORIGINAL USER REQUEST:
What are the durable hardware facts about Core from the checked inventory?

FRONTIER RESULT:
The checked inventory identifies Core as an i7-8700 computer with 32 GB RAM and an NVIDIA GTX1050 graphics card. The inventory page was last updated on Tuesday.
'@
    }
)

foreach ($case in $cases) {
    if (-not [string]::IsNullOrWhiteSpace($ExpectedDigest)) {
        $tags = Invoke-RestMethod -Uri "$baseUri/api/tags" -TimeoutSec 15
        $pin = @($tags.models | Where-Object { $_.name -ceq $Model })
        if ($pin.Count -ne 1 -or $pin[0].digest -cne $ExpectedDigest) { throw 'Model digest changed or disappeared; no further inference.' }
    }
    $policy = $policyTemplate.Replace('{{L2_EVIDENCE_SCOPE}}', ([string]$case.EvidenceScope).Trim())

    $bodyObj = @{
        model = $Model
        messages = @(
            @{ role = 'system'; content = $policy.Trim() },
            @{ role = 'user'; content = $case.Prompt }
        )
        think = $false
        stream = $false
        keep_alive = '5m'
        format = $schema
        options = @{
            num_predict = 384
            temperature = $Temperature
            num_ctx = $ContextLength
            num_gpu = 0
            num_thread = $NumThreads
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 16 -Compress
    $body | Set-Content -LiteralPath (Join-Path $EvidenceDirectory ($case.Name + '.request.json')) -Encoding UTF8
    Write-Host ("Running {0} (temperature={1}; CPU threads={2})..." -f $case.Name,$Temperature,$NumThreads)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Uri "$baseUri/api/chat" -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
    $sw.Stop()
    $response | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory ($case.Name + '.response.json')) -Encoding UTF8

    $content = [string]$response.message.content
    Write-Host ("RawJSON: {0}" -f $content)
    if ($response.done -ne $true -or $response.done_reason -eq 'length') { throw "Incomplete/truncated response: $($case.Name); preserve evidence, do not retry automatically." }
    $obj = $content | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $obj.PSObject.Properties['memory_ops']) { throw "Missing memory_ops: $($case.Name)" }
    $parsed = ConvertFrom-LfoStructuredMemoryOps $obj.memory_ops 6
    $parsed | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory ($case.Name + '.parsed.json')) -Encoding UTF8

    Write-Host ""
    Write-Host ("=== {0} ===" -f $case.Name)
    Write-Host ("Prompt: {0}" -f $case.Prompt)
    Write-Host ("Profile: extraction-only; temperature={0}; num_ctx={1}; num_predict=384; think=false" -f $Temperature,$ContextLength)
    Write-Host ("Time: {0:n2}s; valid={1}; rejected={2}" -f $sw.Elapsed.TotalSeconds, @($parsed.Valid).Count, @($parsed.Rejected).Count)

    if (@($parsed.Valid).Count -eq 0) {
        Write-Host "memory_ops: []"
    } else {
        $parsed.Valid |
            Select-Object Op,Subject,SubjectType,Predicate,Target,TargetType,TargetEntityType,Normalization |
            Format-Table -AutoSize
    }

    if (@($parsed.Rejected).Count -gt 0) {
        Write-Host "Rejected:" -ForegroundColor Yellow
        $parsed.Rejected | Format-List
        throw "Rejected operations: $($case.Name); stop and inspect semantic output."
    }
}
Write-Host "Five responses collected. Semantic verdict: PENDING REVIEW. Evidence: $EvidenceDirectory"
