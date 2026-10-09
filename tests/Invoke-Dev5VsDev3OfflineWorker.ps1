# Worker for the model-free component comparison. Invoked by Measure-Dev5VsDev3Offline.ps1.
# Separate fresh Windows PowerShell process per variant/run; no Ollama or network.
param(
    [Parameter(Mandatory=$true)][ValidateSet('dev3','dev5')][string]$Variant,
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [Parameter(Mandatory=$true)][string]$SandboxRoot,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][int]$Repetition
)
$ErrorActionPreference='Stop'
function Assert-LfoBenchTempPath([string]$Path){
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
    $full=[IO.Path]::GetFullPath($Path)
    if(-not $full.StartsWith(($temp+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){
        throw 'Worker refuses output or SQLite outside TEMP.'
    }
}
Assert-LfoBenchTempPath $SandboxRoot
Assert-LfoBenchTempPath $OutputPath
if($Repetition -le 0){throw 'Repetition must be positive.'}
if(-not (Test-Path -LiteralPath $SandboxRoot -PathType Container)){throw 'Missing independent worker sandbox.'}
if(-not (Test-Path -LiteralPath (Join-Path $SourceRoot 'src\LfoMemoryStore.ps1') -PathType Leaf)){throw 'Missing source snapshot.'}

. (Join-Path $SourceRoot 'src\LfoStructuredMemory.ps1')
. (Join-Path $SourceRoot 'src\LfoMemoryStore.ps1')
. (Join-Path $SourceRoot 'src\QwenMemory.ps1')
if($Variant -eq 'dev5'){. (Join-Path $SourceRoot 'src\LfoTurnTelemetry.ps1')}

function Assert-LfoBench([bool]$Pass,[string]$Message) { if(-not $Pass){throw "Offline correctness gate failed: $Message"} }
function New-LfoBenchRaw([string]$Op,[string]$Predicate,[string]$Target) {
    return [pscustomobject]@{op=$Op;subject='BENCH_SERVER';subject_type='server';predicate=$Predicate;target=$Target;target_entity_type=''}
}
$rawDense=@(
    (New-LfoBenchRaw 'SET_TEXT' 'os' 'Synthetic OS 13'),
    (New-LfoBenchRaw 'SET_INTEGER' 'ram_gb' '64'),
    (New-LfoBenchRaw 'SET_INTEGER' 'disk_gb' '512'),
    (New-LfoBenchRaw 'SET_INTEGER' 'cpu_count' '8')
)
$rawCorrection=@(New-LfoBenchRaw 'SET_INTEGER' 'ram_gb' '96')
$dense=ConvertFrom-LfoStructuredMemoryOps -RawOps $rawDense -MaxOps 6
$correction=ConvertFrom-LfoStructuredMemoryOps -RawOps $rawCorrection -MaxOps 6
Assert-LfoBench (@($dense.Valid).Count -eq 4 -and @($dense.Rejected).Count -eq 0 -and @($correction.Valid).Count -eq 1) 'Operation parsing'
Assert-LfoBench (-not (Test-DeclarativeStateUpdatePrompt 'What is the status of BENCH_SERVER?')) 'Plain-local classified as memory update'
Assert-LfoBench (Test-DeclarativeStateUpdatePrompt 'Please remember this: I prefer concise plain text.') 'Explicit preference intent not recognized'

$sw=[Diagnostics.Stopwatch]::new()
$loops=250
$sw.Start()
for($i=0;$i -lt $loops;$i++){
    $flag=Test-DeclarativeStateUpdatePrompt 'What is the status of BENCH_SERVER?'
    if($flag){throw 'Plain-local intent changed'}
}
$sw.Stop(); $plainPer=[double]$sw.Elapsed.TotalSeconds/$loops

$sw.Restart()
for($i=0;$i -lt $loops;$i++){
    $flag=Test-DeclarativeStateUpdatePrompt 'Please remember this: I prefer concise plain text.'
    if(-not $flag){throw 'Preference-only intent changed'}
}
$sw.Stop(); $preferencePer=[double]$sw.Elapsed.TotalSeconds/$loops

$sw.Restart()
for($i=0;$i -lt 60;$i++){
    $p=ConvertFrom-LfoStructuredMemoryOps -RawOps $rawDense -MaxOps 6
    if(@($p.Valid).Count -ne 4 -or @($p.Rejected).Count -ne 0){throw 'Dense parser changed'}
}
$sw.Stop(); $parseDensePer=[double]$sw.Elapsed.TotalSeconds/60

$db=Open-LfoMemoryStore (Join-Path $SandboxRoot 'offline-components.db')
$writes=@();$corrections=@();$reads=@()
try{
    [void](Set-LfoMemoryAttribute $db 'BENCH_SERVER' 'ram_gb' ([int64]128) 1 'server' 'conversation:negative-control')
    foreach($i in 1..15){
        $scope="conversation:synthetic-$i"
        $sw.Restart()
        $result=Apply-LfoStructuredMemoryOps -Connection $db -ParsedOps $dense -SourceTurn 3 -ScopeId $scope
        $sw.Stop();$writes+= [double]$sw.Elapsed.TotalSeconds
        Assert-LfoBench ($result.Status -eq 'applied' -and [int]$result.AppliedCount -eq 4) "dense-write scope $i"
        $sw.Restart()
        $result=Apply-LfoStructuredMemoryOps -Connection $db -ParsedOps $correction -SourceTurn 4 -ScopeId $scope
        $sw.Stop();$corrections+= [double]$sw.Elapsed.TotalSeconds
        Assert-LfoBench ($result.Status -eq 'applied' -and [int]$result.AppliedCount -eq 1) "correction scope $i"
        $sw.Restart()
        $rows=@()
        foreach($predicate in @('os','ram_gb','disk_gb','cpu_count')){
            $rows+= @(Get-LfoMemoryCurrentAttribute $db 'BENCH_SERVER' $predicate $scope)
        }
        $sw.Stop();$reads+= [double]$sw.Elapsed.TotalSeconds
        Assert-LfoBench ($rows.Count -eq 4 -and
                          @($rows|Where-Object{$_.Predicate -eq 'ram_gb' -and [int64]$_.Value -eq 96}).Count -eq 1) "scoped-read scope $i"
        $history=@(Invoke-LfoSqliteQuery $db @'
SELECT value_integer,valid_to_turn FROM facts
WHERE scope_id=?1 AND predicate='ram_gb'
ORDER BY id;
'@ @($scope))
        Assert-LfoBench ($history.Count -eq 2 -and [int64]$history[0].value_integer -eq 64 -and
                          [int]$history[0].valid_to_turn -eq 4 -and [int64]$history[1].value_integer -eq 96 -and
                          $null -eq $history[1].valid_to_turn) "correction history scope $i"
    }
    $negative=@(Get-LfoMemoryCurrentAttribute $db 'BENCH_SERVER' 'ram_gb' 'conversation:negative-control')
    Assert-LfoBench ($negative.Count -eq 1 -and [int64]$negative[0].Value -eq 128) 'Negative scope changed'
}finally{Close-LfoSqliteDatabase $db}

function Get-LfoOfflineMedian([double[]]$Numbers){
    $items=@($Numbers|Sort-Object);$n=$items.Count;$m=[int][Math]::Floor($n/2)
    if($n % 2 -eq 1){return [double]$items[$m]}
    return ([double]$items[$m-1]+[double]$items[$m])/2.0
}
$telemetryPer=$null
if($Variant -eq 'dev5'){
    $times=@()
    # This absolute cost must not be interpreted as the full dev3/dev5 wall delta.
    foreach($i in 1..250){
        $sw.Restart()
        Start-LfoTurnTelemetry
        Add-LfoTurnPhase -Phase 'context' -WallSeconds 0.02 -Kind 'memory'
        Add-LfoTurnPhase -Phase 'request' -WallSeconds 0.03 -Kind 'wrapper'
        Add-LfoTurnPhase -Phase 'local' -WallSeconds 0.04 -Kind 'model'
        $phases=@(Get-LfoTurnPhases)
        $sw.Stop()
        Assert-LfoBench ($phases.Count -eq 3) 'Telemetry failed to record synthetic phases'
        $times+= [double]$sw.Elapsed.TotalSeconds
    }
    $telemetryPer=Get-LfoOfflineMedian ([double[]]$times)
}
$out=[ordered]@{
    schema='lfo-dev3-dev5-offline-components-v1'
    kind='measured-offline-components-only'
    variant=$Variant
    repetition=$Repetition
    units='seconds-per-operation'
    samples=[ordered]@{
        plain_local_intent=$plainPer
        preference_only_intent=$preferencePer
        dense_parse=$parseDensePer
        dense_write=$(Get-LfoOfflineMedian ([double[]]$writes))
        correction_write=$(Get-LfoOfflineMedian ([double[]]$corrections))
        scoped_read_4_attributes=$(Get-LfoOfflineMedian ([double[]]$reads))
    }
    telemetry_three_phase_seconds=$(if($Variant -eq 'dev5'){$telemetryPer}else{$null})
    checks=[ordered]@{
        correct_intent=$true
        dense_4_facts_written=$true
        correction_history=$true
        other_scope_preserved=$true
        ollama_called=$false
        production_memory_touched=$false
        new_sqlite_transactions_guarded=$false
    }
}
$out | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
