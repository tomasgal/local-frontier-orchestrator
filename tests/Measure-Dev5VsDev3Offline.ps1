# Model-FREE component comparison against pinned dev3; NOT an answer-wall benchmark.
# Archives both committed snapshots to unique TEMP; never checks out another branch.
param([ValidateRange(2,20)][int]$Repetitions=4)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$dev3Pin='a34658b81742596520da844618b5bb39f3329279'
$expectedBranch='v9.4-dev5-compact-read'
function Invoke-LfoGit([string[]]$GitArguments){
    $lines=@(& git -C $repo @GitArguments)
    if($LASTEXITCODE -ne 0){throw "Git read failed: $($GitArguments -join ' ')"}
    return $lines
}
$branch=@(Invoke-LfoGit @('branch','--show-current'))
if($branch.Count -ne 1 -or [string]$branch[0] -cne $expectedBranch){throw 'Wrong branch: dev5 only.'}
$dirty=@(Invoke-LfoGit @('status','--porcelain'))
if($dirty.Count -ne 0){throw 'Dirty worktree: will not measure a moving/uncommitted checkout.'}
$dev5Resolved=@(Invoke-LfoGit @('rev-parse','HEAD'))
if($dev5Resolved.Count -ne 1){throw 'Ambiguous dev5 HEAD.'}
$dev5Pin=[string]$dev5Resolved[0]
if($dev5Pin -cnotmatch '^[0-9a-f]{40}$' -or $dev5Pin -ceq $dev3Pin){throw 'Invalid dev5 pin.'}
$type=@(Invoke-LfoGit @('cat-file','-t',$dev3Pin))
if($type.Count -ne 1 -or [string]$type[0] -cne 'commit'){throw 'Dev3 baseline commit missing locally; fetch project branches first.'}

$root=Join-Path ([IO.Path]::GetTempPath()) ('LFO-dev3-vs-dev5-offline-'+[guid]::NewGuid().ToString('N'))
$full=[IO.Path]::GetFullPath($root)
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
if(-not $full.StartsWith(($temp+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){
    throw 'Unsafe TEMP isolation root.'
}
[void](New-Item -ItemType Directory -Path $root -Force)
$modules=@('src/LfoStructuredMemory.ps1','src/LfoMemoryStore.ps1','src/QwenMemory.ps1')
$stages=@{}
foreach($variant in @('dev3','dev5')){
    $pin=if($variant -eq 'dev3'){$dev3Pin}else{$dev5Pin}
    $stage=Join-Path $root ('snapshot-'+$variant)
    [void](New-Item -ItemType Directory -Path $stage -Force)
    $archive=Join-Path $root ($variant+'.tar')
    $files=@($modules)
    if($variant -eq 'dev5'){$files+= 'src/LfoTurnTelemetry.ps1'}
    & git -C $repo archive --format=tar -o $archive $pin -- @files
    if($LASTEXITCODE -ne 0){throw "Cannot archive immutable $variant pin $pin"}
    & tar.exe -xf $archive -C $stage
    if($LASTEXITCODE -ne 0){throw "Cannot extract immutable $variant source snapshot."}
    foreach($file in $files){
        $p=Join-Path $stage $file
        if(-not (Test-Path -LiteralPath $p -PathType Leaf)){throw "Incomplete $variant archived source: $file"}
        $tokens=$null;$errors=$null
        [void][Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
        if(@($errors).Count -ne 0){throw "Syntax error in archived $variant $file : $($errors|Out-String)"}
    }
    $stages[$variant]=$stage
}
$worker=Join-Path $repo 'tests\Invoke-Dev5VsDev3OfflineWorker.ps1'
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($worker,[ref]$tokens,[ref]$errors)
if(@($errors).Count -ne 0){throw "Worker parser failed: $($errors|Out-String)"}
$exe=(Get-Command powershell.exe -ErrorAction Stop).Source
$results=@()
foreach($rep in 1..$Repetitions){
    $order=if($rep % 2 -eq 1){@('dev3','dev5')}else{@('dev5','dev3')}
    foreach($variant in $order){
        $sandbox=Join-Path $root ("run-$rep-$variant")
        [void](New-Item -ItemType Directory -Path $sandbox -Force)
        $output=Join-Path $sandbox 'measured-components.json'
        & $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -Variant $variant -SourceRoot $stages[$variant] -SandboxRoot $sandbox -OutputPath $output -Repetition $rep
        if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)){
            throw "Offline worker $variant repetition $rep failed; inspect $sandbox"
        }
        $item=Get-Content -LiteralPath $output -Raw -Encoding UTF8 | ConvertFrom-Json
        if([string]$item.schema -cne 'lfo-dev3-dev5-offline-components-v1' -or
           [string]$item.kind -cne 'measured-offline-components-only' -or
           [string]$item.variant -cne $variant -or [int]$item.repetition -ne $rep -or
           -not [bool]$item.checks.correct_intent -or -not [bool]$item.checks.dense_4_facts_written -or
           -not [bool]$item.checks.correction_history -or -not [bool]$item.checks.other_scope_preserved -or
           [bool]$item.checks.ollama_called -or [bool]$item.checks.production_memory_touched) {
            throw "Failed correctness or isolation provenance: $variant repetition $rep"
        }
        $results+= $item
    }
}
function Get-LfoOfflineMedian([double[]]$Numbers){
    $items=@($Numbers|Sort-Object);$n=$items.Count
    if($n -eq 0){throw 'Median requires observations.'}
    $m=[int][Math]::Floor($n/2)
    if($n % 2 -eq 1){return [double]$items[$m]}
    return ([double]$items[$m-1]+[double]$items[$m])/2.0
}
$cases=@('plain_local_intent','preference_only_intent','dense_parse','dense_write','correction_write','scoped_read_4_attributes')
$summary=@()
foreach($id in $cases){
    $old=Get-LfoOfflineMedian ([double[]]@($results|Where-Object{$_.variant -eq 'dev3'}|ForEach-Object{[double]$_.samples.$id}))
    $new=Get-LfoOfflineMedian ([double[]]@($results|Where-Object{$_.variant -eq 'dev5'}|ForEach-Object{[double]$_.samples.$id}))
    if($old -le 0 -or $new -le 0){throw "Bad/nonpositive sample in $id"}
    $summary+= [pscustomobject]@{
        Component=$id
        Dev3MedianMs=[Math]::Round(1000*$old,4)
        Dev5MedianMs=[Math]::Round(1000*$new,4)
        DeltaPct=[Math]::Round(100.0*($new-$old)/$old,2)
    }
}
$telemetry=Get-LfoOfflineMedian ([double[]]@($results|Where-Object{$_.variant -eq 'dev5'}|ForEach-Object{[double]$_.telemetry_three_phase_seconds}))
$report=[ordered]@{
    schema='lfo-dev3-dev5-offline-components-v1'
    kind='measured-offline-components-only'
    collected_utc=[DateTime]::UtcNow.ToString('o')
    dev3_commit=$dev3Pin
    dev5_commit=$dev5Pin
    process='separate-Windows-PowerShell-NoProfile-per-repetition'
    run_order='AB-BA-alternating'
    repetitions_per_variant=$Repetitions
    source_snapshots='exact-git-archive-commit'
    input_fixture='synthetic-private-temp-v1'
    host_os_version=[Environment]::OSVersion.VersionString
    powershell_version=$PSVersionTable.PSVersion.ToString()
    observations=@($results)
    comparison=@($summary)
    dev5_telemetry_three_phase_median_ms=[Math]::Round(1000*$telemetry,4)
    accuracy_and_scope_checked=$true
    ollama_called=$false
    production_memory_touched=$false
    explicitly_not_end_to_end=$true
}
$reportPath=Join-Path $root 'offline-components-report.json'
$report|ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$summary|Format-Table -AutoSize
[pscustomobject]@{
    PASS=$true
    Evidence='MEASURED_OFFLINE_COMPONENTS_ONLY'
    MatchedRepetitions=$Repetitions
    Dev3Pinned=$dev3Pin
    Dev5Pinned=$dev5Pin
    Dev5TelemetryThreePhaseMedianMs=[Math]::Round(1000*$telemetry,4)
    EndToEndNetGainEstablished=$false
    NoModelCalls=$true
    ProductionMemoryTouched=$false
    ReportPath=$reportPath
}|Format-List
