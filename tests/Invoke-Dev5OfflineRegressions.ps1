# Single-entry dev5 offline acceptance after LOCAL L2 write-authority changes.
# TEMP-only logs. No Ollama, network, or production memory; only curated
# deterministic test scripts are invoked. Does not checkout or mutate git.
param([switch]$VerboseLogs)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$branch=(& git -C $repo branch --show-current).Trim()
if($LASTEXITCODE -ne 0 -or $branch -cne 'v9.4-dev5-compact-read'){throw 'Wrong branch: dev5 only'}
$dirty=@(& git -C $repo status --porcelain)
if($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0){throw 'Dirty or unreadable Git worktree'}
$head=(& git -C $repo rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $head -cnotmatch '^[0-9a-f]{40}$'){throw 'Invalid checkout HEAD'}
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
$root=Join-Path $temp ('LFO-dev5-offline-acceptance-'+[guid]::NewGuid().ToString('N'))
if(-not [IO.Path]::GetFullPath($root).StartsWith($temp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Log location must be under TEMP'}
[void](New-Item -ItemType Directory -Path $root)
$tests=@(
    'Test-Dev5LocalWriteAdversarial.ps1',
    'Test-Dev5LocalModelWriteAuthority.ps1',
    'Test-Dev5MixedRuntimePersistence.ps1',
    'Test-Dev5SemanticReadBoundary.ps1',
    'Test-Dev5SqliteAtomicity.ps1',
    'Test-LfoMemoryStore.ps1',
    'Test-Dev5MixedUserProvenance.ps1',
    'Test-Dev5CompactRead.ps1',
    'Test-Dev4L2Retrieval.ps1',
    'Test-Dev4Observability.ps1',
    'Test-PromptPolicyOptimization.ps1',
    'Test-Dev5VsDev3Comparator.ps1'
)
$results=@()
try {
    foreach($name in $tests){
        $file=Join-Path $PSScriptRoot $name
        if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "Missing test: $name"}
        $log=Join-Path $root ($name+'.log')
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $pass=$false
        try {
            & $file *> $log
            if(-not $?){throw 'Test returned failure'}
            $pass=$true
        } catch {
            Write-Host ("FAIL {0}: {1}" -f $name,$_.Exception.Message) -ForegroundColor Red
            if(Test-Path -LiteralPath $log){Get-Content -LiteralPath $log -Tail 30}
            throw
        } finally {
            $sw.Stop()
            $results+= [pscustomobject]@{
                Test=$name;PASS=$pass;Seconds=[Math]::Round($sw.Elapsed.TotalSeconds,2)
            }
        }
        Write-Host ("PASS {0} ({1:n2}s)" -f $name,$sw.Elapsed.TotalSeconds)
        if($VerboseLogs){Get-Content -LiteralPath $log -Tail 12}
    }
} finally {
    $allPassed=($results.Count -eq $tests.Count -and
        @($results|Where-Object{-not $_.PASS}).Count -eq 0)
    $report=[ordered]@{
        schema='lfo-dev5-offline-acceptance-v1'
        dev5_commit=$head
        completed_utc=[DateTime]::UtcNow.ToString('o')
        tests_total=$tests.Count
        tests_completed=$results.Count
        passed=$allPassed
        ollama_called=$false
        production_memory_touched=$false
        tests=@($results)
    }
    $report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $root 'acceptance-report.json') -Encoding UTF8
    Write-Host "Acceptance logs: $root"
}
if(-not $allPassed){throw 'Offline acceptance incomplete or failed'}
[pscustomobject]@{
    PASS=$true
    CompletedTests=$results.Count
    Dev5Commit=$head
    ModelCalls=0
    ProductionMemoryTouched=$false
    ReportPath=(Join-Path $root 'acceptance-report.json')
}|Format-List
