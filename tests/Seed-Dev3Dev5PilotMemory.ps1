# Internal TEMP-only SQLite fixture worker; no model.
param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$DbPath)
$ErrorActionPreference='Stop'
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
if(-not ([IO.Path]::GetFullPath($DbPath)).StartsWith($temp+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Non-TEMP database refused'}
. (Join-Path $SourceRoot 'src\LfoMemoryStore.ps1')
$c=Open-LfoMemoryStore $DbPath
try{
    [void](Set-LfoMemoryAttribute $c 'BENCH_SERVER' 'os' 'Synthetic OS 13' 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $c 'BENCH_SERVER' 'ram_gb' ([int64]96) 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $c 'BENCH_SERVER' 'disk_gb' ([int64]512) 1 'server' 'conversation:1')
    [void](Set-LfoMemoryAttribute $c 'BENCH_SERVER' 'cpu_count' ([int64]8) 1 'server' 'conversation:1')
    $n=@(Invoke-LfoSqliteQuery $c "SELECT id FROM current_facts WHERE scope_id=?1;" @('conversation:1')).Count
    if($n -ne 4){throw "Fact count mismatch: $n"}
}finally{Close-LfoSqliteDatabase $c}
