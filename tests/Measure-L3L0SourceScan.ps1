# Measure current linear L0 JSONL source-resolution cost before considering a source locator.
# TEMP-only; no Ollama, no production memory, no network.
[CmdletBinding()]
param([int[]]$TurnCounts=@(500,5000,20000),[ValidateRange(2,10)][int]$Repetitions=3)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'src\LfoL3Runtime.ps1'),[ref]$tokens,[ref]$errors)
if(@($errors).Count -gt 0){throw ("Syntax FAIL LfoL3Runtime.ps1: "+(($errors|ForEach-Object Message)-join '; '))}
. (Join-Path $repo 'src\LfoL3Runtime.ps1')

$root=Join-Path $env:TEMP ('LFO-l3-l0-scan-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $root)
$results=@()
foreach($n in $TurnCounts){
  if($n -le 0){continue}
  $dir=Join-Path $root ("n"+$n)
  [void](New-Item -ItemType Directory -Force -Path $dir)
  $path=Join-Path $dir 'conversation-2026-10.jsonl'
  $swWrite=[Diagnostics.Stopwatch]::StartNew()
  $writer=[IO.StreamWriter]::new($path,$false,[Text.UTF8Encoding]::new($false))
  try{
    for($i=1;$i -le $n;$i++){
      $row=[ordered]@{
        event='turn';timestamp='2026-10-12T00:00:00Z';turn_id=$i;epoch=1;route='LOCAL'
        user=("Synthetic query turn "+$i+" with bounded filler text.")
        assistant=("Synthetic answer turn "+$i+" with bounded filler text for source scan measurement.")
      }
      $writer.WriteLine(($row|ConvertTo-Json -Compress))
    }
  } finally {$writer.Dispose()}
  $swWrite.Stop()
  $candidate=[pscustomobject]@{SourceLayer='L0';SourceRef=("turn:"+$n)}
  $times=@()
  for($rep=1;$rep -le $Repetitions;$rep++){
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $e=@(Get-LfoL3RuntimeL0Evidence @($candidate) $dir 1)
    $sw.Stop()
    if($e.Count -ne 1 -or $e[0].SourceRef -cne ("turn:"+$n)){throw "Source resolution failed for $n turns."}
    $times += $sw.Elapsed.TotalMilliseconds
  }
  $sorted=@($times|Sort-Object)
  $median=if(($sorted.Count%2)-eq 1){$sorted[[int][Math]::Floor($sorted.Count/2)]}else{($sorted[$sorted.Count/2-1]+$sorted[$sorted.Count/2])/2}
  $size=(Get-Item -LiteralPath $path).Length
  $results += [pscustomobject]@{
    Turns=$n
    FileMiB=[Math]::Round($size/1MB,3)
    WriteMs=[Math]::Round($swWrite.Elapsed.TotalMilliseconds,2)
    MeanScanMs=[Math]::Round((($times|Measure-Object -Average).Average),2)
    MedianScanMs=[Math]::Round($median,2)
    MinScanMs=[Math]::Round((($times|Measure-Object -Minimum).Minimum),2)
    MaxScanMs=[Math]::Round((($times|Measure-Object -Maximum).Maximum),2)
    EvidenceCount=1
  }
}
$results|Format-Table -AutoSize
[pscustomobject]@{
  Completed=$true
  Repetitions=$Repetitions
  ProductionMemoryTouched=$false
  ModelCalls=0
  TempFixture=$root
  LargestCorpusTurns=($results|Measure-Object Turns -Maximum).Maximum
  LargestCorpusMedianScanMs=($results|Sort-Object Turns|Select-Object -Last 1).MedianScanMs
}|Format-List
