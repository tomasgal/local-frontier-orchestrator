# Compare legacy linear L0 JSONL scan with schema-v4 byte locator.
# TEMP-only; no Ollama, no production memory, no network.
[CmdletBinding()]
param([int[]]$TurnCounts=@(500,5000,20000),[ValidateRange(2,10)][int]$Repetitions=3)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
foreach($relative in @('src\LfoMemoryStore.ps1','src\LfoL3Store.ps1','src\LfoL3Runtime.ps1')){
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $relative),[ref]$tokens,[ref]$errors)
  if(@($errors).Count -gt 0){throw ("Syntax FAIL {0}: {1}" -f $relative,(($errors|ForEach-Object Message)-join '; '))}
}
. (Join-Path $repo 'src\LfoMemoryStore.ps1')
. (Join-Path $repo 'src\LfoL3Store.ps1')
. (Join-Path $repo 'src\LfoL3Runtime.ps1')

function Get-Median([double[]]$Values){
  $sorted=@($Values|Sort-Object)
  if($sorted.Count -eq 0){return 0.0}
  if(($sorted.Count%2)-eq 1){return [double]$sorted[[int][Math]::Floor($sorted.Count/2)]}
  return ([double]$sorted[$sorted.Count/2-1]+[double]$sorted[$sorted.Count/2])/2.0
}

$root=Join-Path $env:TEMP ('LFO-l3-l0-scan-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $root)
$results=@()
$utf8=New-Object Text.UTF8Encoding($false)

foreach($n in $TurnCounts){
  if($n -le 0){continue}
  $dir=Join-Path $root ("n"+$n)
  [void](New-Item -ItemType Directory -Force -Path $dir)
  $path=Join-Path $dir 'conversation-2026-10.jsonl'
  $lastJson=''
  $swWrite=[Diagnostics.Stopwatch]::StartNew()
  $writer=[IO.StreamWriter]::new($path,$false,$utf8)
  try{
    for($i=1;$i -le $n;$i++){
      $row=[ordered]@{
        event='turn';timestamp='2026-10-12T00:00:00Z';turn_id=$i;epoch=1;route='LOCAL'
        user=("Synthetic query turn "+$i+" with bounded filler text.")
        assistant=("Synthetic answer turn "+$i+" with bounded filler text for source scan measurement.")
      }
      $json=$row|ConvertTo-Json -Compress
      $writer.WriteLine($json)
      if($i -eq $n){$lastJson=$json}
    }
  } finally {$writer.Dispose()}
  $swWrite.Stop()

  $size=[int64](Get-Item -LiteralPath $path).Length
  $lastLength=[int64]$utf8.GetByteCount($lastJson+[Environment]::NewLine)
  $lastOffset=$size-$lastLength
  if($lastOffset -lt 0 -or $lastLength -le 0){throw "Invalid synthetic locator for $n turns."}

  $dbPath=Join-Path $dir 'l3-index.db'
  $db=Open-LfoL3Store $dbPath
  try{
    $item=Set-LfoL3Item $db 'conversation:1' 'L0' ("turn:"+$n) $n $null
    [void](Set-LfoL3L0Locator $db ([int64]$item.id) ([IO.Path]::GetFileName($path)) $lastOffset $lastLength)
    $candidate=[pscustomobject]@{Id=[int64]$item.id;SourceLayer='L0';SourceRef=("turn:"+$n)}

    $scanTimes=@()
    $locatorTimes=@()
    $reference=$null
    for($rep=1;$rep -le $Repetitions;$rep++){
      $sw=[Diagnostics.Stopwatch]::StartNew()
      $scan=@(Get-LfoL3RuntimeL0Evidence @($candidate) $dir 1)
      $sw.Stop()
      if($scan.Count -ne 1 -or $scan[0].SourceRef -cne ("turn:"+$n)){throw "Scan resolution failed for $n turns."}
      $scanTimes += $sw.Elapsed.TotalMilliseconds
      if($null -eq $reference){$reference=[string]$scan[0].Text}

      $sw=[Diagnostics.Stopwatch]::StartNew()
      $direct=@(Get-LfoL3RuntimeL0Evidence @($candidate) $dir 1 $db)
      $sw.Stop()
      if($direct.Count -ne 1 -or $direct[0].SourceRef -cne ("turn:"+$n) -or [string]$direct[0].Text -cne $reference){
        throw "Locator resolution/parity failed for $n turns."
      }
      $locatorTimes += $sw.Elapsed.TotalMilliseconds
    }

    $scanMedian=Get-Median $scanTimes
    $locatorMedian=Get-Median $locatorTimes
    $results += [pscustomobject]@{
      Turns=$n
      FileMiB=[Math]::Round($size/1MB,3)
      WriteMs=[Math]::Round($swWrite.Elapsed.TotalMilliseconds,2)
      MeanScanMs=[Math]::Round((($scanTimes|Measure-Object -Average).Average),2)
      MedianScanMs=[Math]::Round($scanMedian,2)
      MeanLocatorMs=[Math]::Round((($locatorTimes|Measure-Object -Average).Average),2)
      MedianLocatorMs=[Math]::Round($locatorMedian,2)
      MedianSavedMs=[Math]::Round(($scanMedian-$locatorMedian),2)
      MedianSpeedupX=if($locatorMedian -gt 0){[Math]::Round(($scanMedian/$locatorMedian),2)}else{$null}
      ExactEvidenceParity=$true
    }
  } finally {
    Close-LfoSqliteDatabase $db
  }
}

$results|Format-Table -AutoSize
$largest=$results|Sort-Object Turns|Select-Object -Last 1
[pscustomobject]@{
  Completed=$true
  Repetitions=$Repetitions
  ProductionMemoryTouched=$false
  ModelCalls=0
  TempFixture=$root
  LargestCorpusTurns=$largest.Turns
  LargestCorpusMedianScanMs=$largest.MedianScanMs
  LargestCorpusMedianLocatorMs=$largest.MedianLocatorMs
  LargestCorpusMedianSavedMs=$largest.MedianSavedMs
  LargestCorpusMedianSpeedupX=$largest.MedianSpeedupX
  ExactEvidenceParity=$true
}|Format-List
