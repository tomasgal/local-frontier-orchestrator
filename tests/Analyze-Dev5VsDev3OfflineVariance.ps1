# Analyze a PREEXISTING model-free component report. Never invokes inference.
param([Parameter(Mandatory=$true)][string]$ReportPath)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$branch=(& git -C $repo branch --show-current).Trim()
if($LASTEXITCODE -ne 0 -or $branch -cne 'v9.4-dev5-compact-read'){throw 'Wrong branch'}
if(@(& git -C $repo status --porcelain).Count -ne 0){throw 'Dirty tree'}
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
$full=[IO.Path]::GetFullPath($ReportPath)
if(-not $full.StartsWith($temp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Report must be under TEMP'}
if(-not (Test-Path -LiteralPath $full -PathType Leaf)){throw 'Report missing'}
$r=Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json
if($r.schema -cne 'lfo-dev3-dev5-offline-components-v1' -or $r.kind -cne 'measured-offline-components-only' -or
   $r.dev3_commit -cne 'a34658b81742596520da844618b5bb39f3329279' -or
   $r.dev5_commit -cne '75e0b4b806d2016bb28571049e20712718be66aa' -or
   -not $r.accuracy_and_scope_checked -or $r.ollama_called -or $r.production_memory_touched){throw 'Report provenance or correctness failure'}
$obs=@($r.observations)
$n=[int]$r.repetitions_per_variant
if($n -lt 2 -or $obs.Count -ne 2*$n){throw 'Unexpected observation count'}
$fields=@('plain_local_intent','preference_only_intent','dense_parse','dense_write','correction_write','scoped_read_4_attributes')
$summary=@()
foreach($field in $fields){
    $pairs=@()
    foreach($rep in 1..$n){
        $a=@($obs|Where-Object{$_.variant -eq 'dev3' -and [int]$_.repetition -eq $rep})
        $b=@($obs|Where-Object{$_.variant -eq 'dev5' -and [int]$_.repetition -eq $rep})
        if($a.Count -ne 1 -or $b.Count -ne 1){throw "Missing or duplicated pair $rep"}
        $x=[double]$a[0].samples.$field;$y=[double]$b[0].samples.$field
        if($x -le 0 -or $y -le 0 -or [double]::IsNaN($x) -or [double]::IsNaN($y)){throw "Invalid measure $field"}
        $pairs+=100.0*($y/$x-1.0)
    }
    $positive=@($pairs|Where-Object{$_ -gt 0}).Count
    $negative=@($pairs|Where-Object{$_ -lt 0}).Count
    $summary+=[pscustomobject]@{
        Component=$field;Pairs=$n;Dev5SlowerPairs=$positive;Dev5FasterPairs=$negative
        MinPairedDeltaPct=[Math]::Round(($pairs|Measure-Object -Minimum).Minimum,2)
        MaxPairedDeltaPct=[Math]::Round(($pairs|Measure-Object -Maximum).Maximum,2)
        MeanPairedDeltaPct=[Math]::Round(($pairs|Measure-Object -Average).Average,2)
        StableSign=($positive -eq $n -or $negative -eq $n)
    }
}
$summary|Format-Table -AutoSize
[pscustomobject]@{PASS=$true;MeasuredComponentPairs=$n;ReportCommit=$r.dev5_commit;ModelCalls=0;ProductionMemoryTouched=$false;NotEndToEnd=$true;Interpretation='DESCRIPTIVE_ONLY: 4 paired observations; no inferential claim'}|Format-List
