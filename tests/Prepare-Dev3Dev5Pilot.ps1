# TEMP-only preparation, no inference, no branch checkout or production memory.
# This is a CAPABILITY-AWARE pilot, not identical-input causal attribution:
# dev3 sees the facts in L1; dev5 also retrieves identical facts from L2.
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$baseline='a34658b81742596520da844618b5bb39f3329279'
$target='v9.4-dev5-compact-read'
if((& git -C $repo branch --show-current).Trim() -cne $target -or $LASTEXITCODE -ne 0){throw 'Wrong branch'}
if(@(& git -C $repo status --porcelain).Count -ne 0 -or $LASTEXITCODE -ne 0){throw 'Dirty worktree'}
& git -C $repo cat-file -e "$baseline^{commit}"
if($LASTEXITCODE -ne 0){throw 'Dev3 pin absent'}
$dev5=(& git -C $repo rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $dev5 -cnotmatch '^[0-9a-f]{40}$'){throw 'Bad dev5 commit'}
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$root=Join-Path $temp ('LFO-pilot-setup-'+[guid]::NewGuid().ToString('N'))
if(-not ([IO.Path]::GetFullPath($root)).StartsWith($temp+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe root'}
[void](New-Item -ItemType Directory -Path $root)
$utf8=New-Object Text.UTF8Encoding($false)
$memory='BENCH_SERVER runs Synthetic OS 13; RAM 96 GB; disk 512 GB; 8 CPUs.'
$prompt='State BENCH_SERVER operating system, RAM in GB, disk in GB and CPU count. Reply in one short sentence.'
$manifest=[ordered]@{schema='lfo-dev3-dev5-pilot-preflight-v1';dev3_commit=$baseline;dev5_commit=$dev5;model='qwen3.5:4b-q4_K_M';think=$false;num_ctx=5120;prompt=$prompt;common_l1=$memory;design='common L1 evidence, extra dev5 scoped L2 retrieval; capability-aware, not identical prompts';runs=@()}
foreach($variant in @('dev3','dev5')){
    $rev=if($variant -eq 'dev3'){$baseline}else{$dev5}
    $work=Join-Path $root $variant
    $source=Join-Path $work 'source'
    $data=Join-Path $work 'memory'
    $state=Join-Path $data 'state'
    [void](New-Item -ItemType Directory -Force -Path $source,$state)
    $tar=Join-Path $root ($variant+'.tar')
    & git -C $repo archive --format=tar -o $tar $rev
    if($LASTEXITCODE -ne 0){throw "Archive failure $variant"}
    & tar.exe -xf $tar -C $source
    if($LASTEXITCODE -ne 0){throw "Extract failure $variant"}
    $config=Join-Path $source 'config\QwenChat.config.psd1'
    $body=Get-Content -LiteralPath $config -Raw -Encoding UTF8
    $needle="DataDirectory = '%LOCALAPPDATA%\LocalFrontierOrchestrator'"
    if($body.Split([string[]]@($needle),[StringSplitOptions]::None).Count -ne 2){throw "$variant config path anchor missing"}
    $body=$body.Replace($needle,("DataDirectory = '"+$data+"'"))
    if($variant -eq 'dev5'){
        foreach($item in @(@('StructuredReadEnabled = $false','StructuredReadEnabled = $true'),@('CompactReadSchemaEnabled = $false','CompactReadSchemaEnabled = $true'),@('LeanReadPolicyEnabled = $false','LeanReadPolicyEnabled = $true'))){
            if($body.Split([string[]]@([string]$item[0]),[StringSplitOptions]::None).Count -ne 2){throw 'Dev5 feature anchor invalid'}
            $body=$body.Replace([string]$item[0],[string]$item[1])
        }
    }
    $cfgPath=Join-Path $work 'config-isolated.psd1'
    [IO.File]::WriteAllText($cfgPath,$body,$utf8)
    $cfg=Import-PowerShellDataFile -LiteralPath $cfgPath
    if([IO.Path]::GetFullPath([string]$cfg.Memory.DataDirectory) -ine [IO.Path]::GetFullPath($data)){throw 'Nonisolated config'}
    if($variant -eq 'dev5' -and (-not $cfg.Memory.StructuredReadEnabled -or -not $cfg.LocalGeneration.CompactReadSchemaEnabled -or -not $cfg.LocalGeneration.LeanReadPolicyEnabled -or $cfg.LocalGeneration.MixedUserEvidenceWriteEnabled -or $cfg.LocalGeneration.LowerTrustL2EvidenceEnabled)){throw 'Unexpected dev5 feature flags'}
    [IO.File]::WriteAllText((Join-Path $state 'working_memory.txt'),$memory,$utf8)
    [IO.File]::WriteAllText((Join-Path $state 'pending_notes.jsonl'),'',$utf8)
    $rs=[ordered]@{version=2;memory_schema=2;epoch=1;next_turn_id=3;completed_since_compaction=0}
    [IO.File]::WriteAllText((Join-Path $state 'runtime_state.json'),($rs|ConvertTo-Json),$utf8)
    # Both have the same underlying facts, although only dev5 reads them into the prompt.
    & powershell.exe -NoProfile -NonInteractive -Command "& { param([string]\$module,[string]\$db); . \$module; \$c=Open-LfoMemoryStore \$db; try { [void](Set-LfoMemoryAttribute \$c 'BENCH_SERVER' 'os' 'Synthetic OS 13' 1 'server' 'conversation:1'); [void](Set-LfoMemoryAttribute \$c 'BENCH_SERVER' 'ram_gb' ([int64]96) 1 'server' 'conversation:1'); [void](Set-LfoMemoryAttribute \$c 'BENCH_SERVER' 'disk_gb' ([int64]512) 1 'server' 'conversation:1'); [void](Set-LfoMemoryAttribute \$c 'BENCH_SERVER' 'cpu_count' ([int64]8) 1 'server' 'conversation:1'); \$n=@(Invoke-LfoSqliteQuery \$c 'SELECT id FROM current_facts WHERE scope_id=?1;' @('conversation:1')).Count; if(\$n -ne 4){throw 'Fact count mismatch'} } finally {Close-LfoSqliteDatabase \$c} }" (Join-Path $source 'src\LfoMemoryStore.ps1') (Join-Path $state 'l2-memory.db')
    if($LASTEXITCODE -ne 0){throw "SQLite seed failed $variant"}
    $manifest.runs+=@([ordered]@{variant=$variant;source=$source;config=$cfgPath;memory=$data})
}
$manifestPath=Join-Path $root 'pilot-manifest.json'
[IO.File]::WriteAllText($manifestPath,($manifest|ConvertTo-Json -Depth 6),$utf8)
Write-Host "PILOT PREFLIGHT PREPARED: $manifestPath"
Write-Host 'NO INFERENCE. Do not treat dev3 and dev5 as identical prompt input.'
[pscustomobject]@{PASS=$true;Variants=2;IsolatedStores=2;SeedFactsPerVariant=4;NoModelCalls=$true;ProductionMemoryTouched=$false;Manifest=$manifestPath}|Format-List
