# L3-R3 bounded offline acceptance runner.
# Deterministic TEMP tests only; no Ollama, network or production memory.
param([switch]$VerboseLogs)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$branch = (& git -C $repo branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -cne 'v9.5-l3-selective-index') {
    throw "Wrong branch: expected v9.5-l3-selective-index, got '$branch'"
}
$dirty = @(& git -C $repo status --porcelain)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Dirty or unreadable Git worktree.' }
$head = (& git -C $repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $head -cnotmatch '^[0-9a-f]{40}$') { throw 'Invalid checkout HEAD.' }

$temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
$root = Join-Path $temp ('LFO-l3-r3-offline-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $root)
$tests = @(
    'Test-LfoMemoryStore.ps1',
    'Test-Dev4L2Retrieval.ps1',
    'Test-LfoL3Store.ps1',
    'Test-LfoL3Tagger.ps1',
    'Test-LfoL3Planner.ps1'
)
$results = @()
try {
    foreach ($name in $tests) {
        $file = Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing test: $name" }
        $log = Join-Path $root ($name + '.log')
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $pass = $false
        try {
            & $file *> $log
            if (-not $?) { throw 'Test returned failure.' }
            $pass = $true
        } catch {
            Write-Host ("FAIL {0}: {1}" -f $name,$_.Exception.Message) -ForegroundColor Red
            if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 50 }
            throw
        } finally {
            $sw.Stop()
            $results += [pscustomobject]@{ Test=$name; PASS=$pass; Seconds=[Math]::Round($sw.Elapsed.TotalSeconds,2) }
        }
        Write-Host ("PASS {0} ({1:n2}s)" -f $name,$sw.Elapsed.TotalSeconds)
        if ($VerboseLogs) { Get-Content -LiteralPath $log -Tail 18 }
    }
} finally {
    $allPassed = ($results.Count -eq $tests.Count -and @($results | Where-Object { -not $_.PASS }).Count -eq 0)
    $report = [ordered]@{
        schema='lfo-l3-r3-offline-v1'
        l3_commit=$head
        completed_utc=[DateTime]::UtcNow.ToString('o')
        tests_total=$tests.Count
        tests_completed=$results.Count
        passed=$allPassed
        ollama_called=$false
        production_memory_touched=$false
        tests=@($results)
    }
    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'acceptance-report.json') -Encoding UTF8
    Write-Host "Acceptance logs: $root"
}
if (-not $allPassed) { throw 'L3-R3 offline acceptance incomplete or failed.' }
[pscustomobject]@{
    PASS=$true
    CompletedTests=$results.Count
    L3Commit=$head
    ModelCalls=0
    ProductionMemoryTouched=$false
    ReportPath=(Join-Path $root 'acceptance-report.json')
} | Format-List
