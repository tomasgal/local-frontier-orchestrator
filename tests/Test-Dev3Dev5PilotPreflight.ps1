# Read-only audit of an existing TEMP-only controlled dev3/dev5 pilot manifest.
# No inference. Separate capability-aware read mechanism, NOT system-wide benchmark.
param([Parameter(Mandatory=$true)][string]$ManifestPath)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if((& git -C $repo branch --show-current).Trim() -cne 'v9.4-dev5-compact-read'){throw 'Wrong experimental branch'}
if(@(& git -C $repo status --porcelain).Count -ne 0){throw 'Dirty worktree'}
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
$manifestFile=[IO.Path]::GetFullPath($ManifestPath)
if(-not $manifestFile.StartsWith($temp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
   -not (Test-Path -LiteralPath $manifestFile -PathType Leaf)){throw 'Manifest outside TEMP or missing'}
$m=Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
$root=Split-Path -Parent $manifestFile
if($m.schema -cne 'lfo-dev3-dev5-pilot-preflight-v1' -or
   $m.cohort -cne 'controlled-eligible-scoped-read' -or
   -not $m.strictly_not_representative_net_gain -or
   $m.dev3_commit -cne 'a34658b81742596520da844618b5bb39f3329279' -or
   $m.dev5_commit -cnotmatch '^[0-9a-f]{40}$' -or
   @($m.runs).Count -ne 2 -or
   $m.think -or [int]$m.num_ctx -ne 5120){throw 'Manifest provenance/fixture mismatch'}
$head=(& git -C $repo rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $m.dev5_commit -cne $head){throw 'Manifest dev5 SHA differs from current checkout; do not mix runs'}
if(Test-Path -LiteralPath (Join-Path $root 'pilot-manifest.json') -PathType Leaf){
    if([IO.Path]::GetFullPath((Join-Path $root 'pilot-manifest.json')) -ine $manifestFile){throw 'Manifest basename mismatch'}
}
$seen=@{}
foreach($item in @($m.runs)){
    $variant=[string]$item.variant
    if($variant -notin @('dev3','dev5') -or $seen.ContainsKey($variant)){throw 'Duplicated/unexpected variant'}
    $seen[$variant]=$true
    $expected=Join-Path $root $variant
    foreach($part in @('source','memory')){
        $actual=[IO.Path]::GetFullPath([string]$item.$part)
        $should=[IO.Path]::GetFullPath((Join-Path $expected $part))
        if($actual -ine $should -or -not $actual.StartsWith($temp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
           -not (Test-Path -LiteralPath $actual -PathType Container)){throw "Unsafe/absent $variant $part"}
    }
    $conf=[IO.Path]::GetFullPath([string]$item.config)
    if($conf -ine [IO.Path]::GetFullPath((Join-Path $expected 'config-isolated.psd1')) -or
       -not (Test-Path -LiteralPath $conf -PathType Leaf)){throw "Nonisolated config: $variant"}
    $cfg=Import-PowerShellDataFile -LiteralPath $conf
    if([IO.Path]::GetFullPath([string]$cfg.Memory.DataDirectory) -ine [IO.Path]::GetFullPath([string]$item.memory)){
        throw "Config redirects memory outside fixture: $variant"
    }
    foreach($relative in @('state\working_memory.txt','state\runtime_state.json','state\l2-memory.db')){
        if(-not (Test-Path -LiteralPath (Join-Path $item.memory $relative) -PathType Leaf)){throw "Missing $variant $relative"}
    }
    $state=(Get-Content -LiteralPath (Join-Path $item.memory 'state\runtime_state.json') -Raw -Encoding UTF8|ConvertFrom-Json)
    if([int]$state.epoch -ne 1 -or [int]$state.next_turn_id -ne 3){throw "Unexpected turn/scope: $variant"}
    $snapshotText=Get-Content -LiteralPath (Join-Path $item.memory 'state\working_memory.txt') -Raw -Encoding UTF8
    if($snapshotText -cne [string]$m.common_l1){throw "Common L1 seed mismatch: $variant"}
}
if($seen.Count -ne 2){throw 'Missing variant'}
$dev5=@($m.runs|Where-Object{$_.variant -eq 'dev5'})[0]
$src=[string]$dev5.source
foreach($name in @('LfoStructuredMemory.ps1','LfoMemoryStore.ps1','LfoStructuredRetrieval.ps1','LfoTurnTelemetry.ps1','QwenMemory.ps1')){
    $file=Join-Path $src ('src\'+$name)
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "Missing dev5 archived source $name"}
    $t=$null;$err=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$t,[ref]$err)
    if(@($err).Count -ne 0){throw "Archived dev5 source parser failure: $name"}
    . $file
}
$script:Config=Import-PowerShellDataFile -LiteralPath ([string]$dev5.config)
$script:RuntimeState=Get-Content -LiteralPath (Join-Path $dev5.memory 'state\runtime_state.json') -Raw -Encoding UTF8|ConvertFrom-Json
Initialize-QwenMemoryConfiguration -ContextLengthHint 5120
if(-not $script:L2ReadEnabled -or
   -not [bool]$script:Config.LocalGeneration.CompactReadSchemaEnabled -or
   -not [bool]$script:Config.LocalGeneration.LeanReadPolicyEnabled -or
   [bool]$script:Config.LocalGeneration.LowerTrustL2EvidenceEnabled -or
   [bool]$script:Config.LocalGeneration.MixedUserEvidenceWriteEnabled){throw 'A/B/C/mixed isolated flags incorrect'}
if(Test-DeclarativeStateUpdatePrompt ([string]$m.prompt)){throw 'Pilot prompt misclassified as a write'}
$l2=Get-LfoRelevantCurrentL2 ([string]$m.prompt)
if($l2.Status -cne 'ok' -or [int]$l2.Count -ne 4 -or
   $l2.Text -notmatch 'BENCH_SERVER' -or
   $l2.Text -notmatch 'Synthetic OS 13' -or
   $l2.Text -notmatch '96' -or
   $l2.Text -notmatch '512' -or
   $l2.Text -notmatch '8'){throw "L2 scoped retrieval failed: status=$($l2.Status), count=$($l2.Count)"}
$script:LfoTurnContext=[pscustomobject]@{
    Query=[string]$m.prompt
    Stats=[pscustomobject]@{l2_read_items=[int]$l2.Count}
}
if(-not (Test-LfoDev5CompactReadEligible) -or -not (Test-LfoDev5LeanReadPolicyEligible)){throw 'Dev5 A+B activation failed in offline eligibility audit'}
$script:LfoTurnContext=$null
[pscustomobject]@{
    PASS=$true
    Dev3Commit=[string]$m.dev3_commit
    Dev5Commit=[string]$m.dev5_commit
    IsolatedMemoryRoots=2
    Dev5ReadStatus=[string]$l2.Status
    Dev5L2Items=[int]$l2.Count
    Dev5AEligible=$true
    Dev5BEligible=$true
    ComparableModelPromptBytes=$false
    RepresentativeNetBenchmark=$false
    ModelCalls=0
    ProductionMemoryTouched=$false
}|Format-List
