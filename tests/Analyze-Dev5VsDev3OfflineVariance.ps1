# Analyze an existing model-free component report; no inference or production-memory access.
param([Parameter(Mandatory=$true)][string]$ReportPath)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$branch=(& git -C $repo branch --show-current).Trim()
if($LASTEXITCODE -ne 0 -or $branch -cne 'v9.4-dev5-compact-read'){throw 'Wrong branch'}
if(@(& git -C $repo status --porcelain).Count -ne 0 -or $LASTEXITCODE -ne 0){throw 'Dirty tree'}
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
$full=[IO.Path]::GetFullPath($ReportPath)
if(-not $full.StartsWith($temp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Report must be under TEMP'}
if(-not (Test-Path -LiteralPath $full -PathType Leaf)){throw 'Report missing'}
$r=Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json
$dev3Pin='a34658b81742596520da844618b5bb39f3329279'
$dev5Pin=[string]$r.dev5_commit
# The report pin, not a hardcoded Lenovo SHA, identifies the measured dev5 source.
if($r.schema -cne 'lfo-dev3-dev5-offline-components-v1' -or $r.kind -cne 'measured-offline-components-only' -or
   $r.dev3_commit -cne $dev3Pin -or $dev5Pin -cnotmatch '^[0-9a-f]{40}$' -or $dev5Pin -ceq $dev3Pin -or
   $r.source_snapshots -cne 'exact-git-archive-commit' -or $r.input_fixture -cne 'synthetic-private-temp-v1' -or
   $r.process -cne 'separate-Windows-PowerShell-NoProfile-per-repetition' -or $r.run_order -cne 'AB-BA-alternating' -or
   -not $r.accuracy_and_scope_checked -or -not $r.explicitly_not_end_to_end -or
   $r.ollama_called -or $r.production_memory_touched){throw 'Report provenance or correctness failure'}
& git -C $repo cat-file -e "$dev5Pin^{commit}" 2>$null
if($LASTEXITCODE -ne 0){throw 'Report dev5 commit is not available locally'}
& git -C $repo merge-base --is-ancestor $dev5Pin HEAD
if($LASTEXITCODE -ne 0){throw 'Report dev5 commit is not in the current dev5 history'}
$obs=@($r.observations)
$n=[int]$r.repetitions_per_variant
if($n -lt 2 -or $n -gt 20 -or $obs.Count -ne 2*$n){throw 'Unexpected observation count'}
$fields=@('plain_local_intent','preference_only_intent','dense_parse','dense_write','correction_write','scoped_read_4_attributes')
$summary=@()
foreach($field in $fields){
    $pairs=@()
    foreach($rep in 1..$n){
        $a=@($obs|Where-Object{$_.variant -eq 'dev3' -and [int]$_.repetition -eq $rep})
        $b=@($obs|Where-Object{$_.variant -eq 'dev5' -and [int]$_.repetition -eq $rep})
        if($a.Count -ne 1 -or $b.Count -ne 1){throw "Missing or duplicated pair $rep"}
        foreach($item in @($a[0],$b[0])){
            if($item.units -cne 'seconds-per-operation' -or $item.schema -cne 'lfo-dev3-dev5-offline-components-v1' -or
               $item.kind -cne 'measured-offline-components-only' -or
               -not $item.checks.correct_intent -or -not $item.checks.dense_4_facts_written -or
               -not $item.checks.correction_history -or -not $item.checks.other_scope_preserved -or
               $item.checks.ollama_called -or $item.checks.production_memory_touched){throw "Failed sample provenance/correctness in pair $rep"}
        }
        $x=[double]$a[0].samples.$field
        $y=[double]$b[0].samples.$field
        if($x -le 0 -or $y -le 0 -or [double]::IsNaN($x) -or [double]::IsNaN($y) -or
           [double]::IsInfinity($x) -or [double]::IsInfinity($y)){throw "Invalid measure $field"}
        $pairs+=100.0*($y/$x-1.0)
    }
    $positive=@($pairs|Where-Object{$_ -gt 0}).Count
    $negative=@($pairs|Where-Object{$_ -lt 0}).Count
    $ordered=@($pairs|Sort-Object)
    $mid=[int][Math]::Floor($n/2)
    $median=if($n % 2 -eq 1){[double]$ordered[$mid]}else{([double]$ordered[$mid-1]+[double]$ordered[$mid])/2.0}
    $summary+=[pscustomobject]@{
        Component=$field
        Pairs=$n
        Dev5SlowerPairs=$positive
        Dev5FasterPairs=$negative
        MedianPairedDeltaPct=[Math]::Round($median,2)
        MinPairedDeltaPct=[Math]::Round(($pairs|Measure-Object -Minimum).Minimum,2)
        MaxPairedDeltaPct=[Math]::Round(($pairs|Measure-Object -Maximum).Maximum,2)
        MeanPairedDeltaPct=[Math]::Round(($pairs|Measure-Object -Average).Average,2)
        StableSign=($positive -eq $n -or $negative -eq $n)
    }
}
$summary|Format-Table -AutoSize
[pscustomobject]@{
    PASS=$true
    MeasuredComponentPairs=$n
    ReportCommit=$dev5Pin
    StablySlowerComponents=@($summary|Where-Object{$_.Dev5SlowerPairs -eq $n}).Count
    StablyFasterComponents=@($summary|Where-Object{$_.Dev5FasterPairs -eq $n}).Count
    ModelCalls=0
    ProductionMemoryTouched=$false
    NotEndToEnd=$true
    Interpretation='DESCRIPTIVE_ONLY: paired component observations; no statistical or end-to-end claim'
}|Format-List
