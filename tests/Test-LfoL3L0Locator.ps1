# L3 v4 L0 source-locator acceptance.
# TEMP-only; verifies direct byte lookup plus validated scan fallback.
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
foreach($relative in @('src\LfoMemoryStore.ps1','src\LfoL3Store.ps1','src\LfoL3Runtime.ps1')){
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $relative),[ref]$tokens,[ref]$errors)
  if(@($errors).Count -gt 0){throw ("Syntax FAIL {0}: {1}" -f $relative,(($errors|ForEach-Object Message)-join '; '))}
}
. (Join-Path $repoRoot 'src\LfoMemoryStore.ps1')
. (Join-Path $repoRoot 'src\LfoL3Store.ps1')
. (Join-Path $repoRoot 'src\LfoL3Runtime.ps1')

$root=Join-Path $env:TEMP ('LFO-l3-locator-'+[guid]::NewGuid().ToString('N'))
$logs=Join-Path $root 'logs'
[void](New-Item -ItemType Directory -Force -Path $logs)
$logPath=Join-Path $logs 'conversation-2026-10.jsonl'
$utf8=New-Object Text.UTF8Encoding($false)

function Add-LocatorTurn([int]$TurnId,[string]$User,[string]$Assistant){
  $offset=if(Test-Path -LiteralPath $logPath -PathType Leaf){[int64](Get-Item -LiteralPath $logPath).Length}else{[int64]0}
  $row=[ordered]@{event='turn';timestamp='2026-10-12T12:00:00Z';turn_id=$TurnId;epoch=1;route='LOCAL';user=$User;assistant=$Assistant}
  $line=($row|ConvertTo-Json -Compress)+[Environment]::NewLine
  [IO.File]::AppendAllText($logPath,$line,$utf8)
  $length=[int64](Get-Item -LiteralPath $logPath).Length-$offset
  [pscustomobject]@{File=[IO.Path]::GetFileName($logPath);Offset=$offset;Length=$length}
}

$loc1=Add-LocatorTurn 1 'Unrelated first turn.' 'Nothing relevant.'
$loc2=Add-LocatorTurn 2 'RETRO_ARCHIVE Žltý token.' 'HALCYON-77 is the archival token.'
$loc3=Add-LocatorTurn 3 'Another indexed turn.' 'OMEGA-3 marker.'

$dbPath=Join-Path $root 'l3-index.db'
$db=Open-LfoL3Store $dbPath
try{
  $schema=@(Invoke-LfoSqliteQuery $db "SELECT value FROM l3_meta WHERE key='schema_version';")
  if($schema.Count -ne 1 -or $schema[0].value -ne '4'){throw 'Locator test expected schema v4.'}

  $i2=Set-LfoL3Item $db 'conversation:1' 'L0' 'turn:2' 2 $null
  $i3=Set-LfoL3Item $db 'conversation:1' 'L0' 'turn:3' 3 $null
  [void](Set-LfoL3L0Locator $db ([int64]$i2.id) $loc2.File $loc2.Offset $loc2.Length)
  [void](Set-LfoL3L0Locator $db ([int64]$i3.id) $loc3.File $loc3.Offset $loc3.Length)

  $candidates=@(
    [pscustomobject]@{Id=[int64]$i2.id;SourceLayer='L0';SourceRef='turn:2'},
    [pscustomobject]@{Id=[int64]$i3.id;SourceLayer='L0';SourceRef='turn:3'}
  )
  $direct=@(Get-LfoL3RuntimeL0Evidence $candidates $logs 1 $db)
  if($direct.Count -ne 2 -or
     (@($direct|Where-Object SourceRef -ceq 'turn:2')[0].Text -notmatch 'HALCYON-77') -or
     (@($direct|Where-Object SourceRef -ceq 'turn:3')[0].Text -notmatch 'OMEGA-3')){
    throw ('Direct locator resolution failed: '+($direct|ConvertTo-Json -Depth 5 -Compress))
  }

  # Point turn:2 at turn:1. Runtime must reject the mismatched turn_id and
  # recover turn:2 through the authoritative JSONL scan fallback.
  [void](Set-LfoL3L0Locator $db ([int64]$i2.id) $loc1.File $loc1.Offset $loc1.Length)
  $fallback=@(Get-LfoL3RuntimeL0Evidence @($candidates[0]) $logs 1 $db)
  if($fallback.Count -ne 1 -or $fallback[0].SourceRef -cne 'turn:2' -or $fallback[0].Text -notmatch 'HALCYON-77'){
    throw ('Stale-locator fallback failed: '+($fallback|ConvertTo-Json -Depth 5 -Compress))
  }

  # Restore exact locator and verify locator persistence across reopen.
  [void](Set-LfoL3L0Locator $db ([int64]$i2.id) $loc2.File $loc2.Offset $loc2.Length)
} finally {
  Close-LfoSqliteDatabase $db
}
$db=Open-LfoL3ReadOnly $dbPath
try{
  $restart=@(Get-LfoL3L0Locators $db @([int64]$i2.id,[int64]$i3.id))
  if($restart.Count -ne 2){throw 'Locator persistence across restart failed.'}
} finally {
  Close-LfoSqliteDatabase $db
}

[pscustomobject]@{
  PASS=$true
  SchemaVersion=4
  DirectLocatorRead=$true
  Utf8ByteOffsetVerified=$true
  StaleLocatorRejected=$true
  ScanFallbackRecovered=$true
  RestartPersistence=$true
  ModelCalls=0
  ProductionMemoryTouched=$false
  TempFixture=$root
}|Format-List
