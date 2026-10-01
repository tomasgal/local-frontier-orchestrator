# Isolated v9.4-dev2 model extraction probe.
# Calls local Ollama but does not touch any LFO memory database.

param(
    [string]$Model,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

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

$policy = Get-Content -LiteralPath (Join-Path $repoRoot 'policy\l2-structured-memory.txt') -Raw -Encoding UTF8
$schema = @{
    type = 'object'
    properties = @{
        memory_ops = Get-LfoStructuredMemoryOperationSchema 6
    }
    required = @('memory_ops')
    additionalProperties = $false
}

$cases = @(
    [pscustomobject]@{
        Name = 'multi-attribute'
        Prompt = 'ORION runs Ubuntu 24.04, uses PostgreSQL 16, has 64 GB RAM, and nightly backups are enabled.'
    },
    [pscustomobject]@{
        Name = 'relation'
        Prompt = 'Core has a GTX1050 graphics card. GTX1050 is NVIDIA. Core has 32 GB RAM.'
    },
    [pscustomobject]@{
        Name = 'correction'
        Prompt = 'Correction: ORION now runs Debian 13 instead of Ubuntu 24.04.'
    },
    [pscustomobject]@{
        Name = 'no-l2'
        Prompt = 'Prefer short technical answers and one CLI command per step.'
    }
)

foreach ($case in $cases) {
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
            temperature = 0.05
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 16 -Compress
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Uri "$baseUri/api/chat" -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 600
    $sw.Stop()

    $content = [string]$response.message.content
    $obj = $content | ConvertFrom-Json -ErrorAction Stop
    $parsed = ConvertFrom-LfoStructuredMemoryOps $obj.memory_ops 6

    Write-Host ""
    Write-Host ("=== {0} ===" -f $case.Name)
    Write-Host ("Prompt: {0}" -f $case.Prompt)
    Write-Host ("Time: {0:n2}s; valid={1}; rejected={2}" -f $sw.Elapsed.TotalSeconds, @($parsed.Valid).Count, @($parsed.Rejected).Count)
    Write-Host ("RawJSON: {0}" -f $content)

    if (@($parsed.Valid).Count -eq 0) {
        Write-Host "memory_ops: []"
    } else {
        $parsed.Valid |
            Select-Object Op,Subject,SubjectType,Predicate,Target,TargetType,TargetEntityType |
            Format-Table -AutoSize
    }

    if (@($parsed.Rejected).Count -gt 0) {
        Write-Host "Rejected:" -ForegroundColor Yellow
        $parsed.Rejected | Format-List
    }
}
