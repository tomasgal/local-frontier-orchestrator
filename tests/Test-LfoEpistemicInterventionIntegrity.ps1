param([Parameter(Mandatory)][string]$ResultPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/LfoEpistemicIntervention.ps1')
$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Message){$caught=$false;try{&$Action|Out-Null}catch{$caught=$true};Assert $caught $Message}
$utf8=New-Object Text.UTF8Encoding($false,$true)
$root=Join-Path ([IO.Path]::GetTempPath()) ('lfo-p2-integrity-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
$mapPath=Join-Path $PSScriptRoot '../config/L4P2Intervention.map.json'
$lockPath=Join-Path $PSScriptRoot '../config/L4P2Intervention.lock.json'
$contractPath=Join-Path $PSScriptRoot '../config/L4P2Integrity.compatibility-v1.json'
$canonical=[IO.File]::ReadAllText($mapPath,$utf8).Replace("`r`n","`n")
$historical=$canonical.Substring(0,$canonical.Length-1).Replace("`n","`r`n")+"`n"
$expectedHistorical='312f05eb128d59c83bc61558610df7e9320184e0a64b5476845ae123cc56c456'
$expectedCanonical='15611e74cc1c038fd1ae827b51504dd948345b7b2fdb58fd6ec9e1c9e44b9c8e'
$p1hash='a5da19563afcb4ac9698acce7aff423daf9b3e400cfe5af40f3a46aea4fe0106'
$capsule=[pscustomobject]@{Schema='lfo-l4-p1-policy-capsule-v1';PolicyVersion='1.0.0';PolicyRulesSha256=$p1hash;Decision='REVIEW_FRAMING'}
$inputs=@(
    @{name='LF';text=$canonical;bom=$false},
    @{name='CRLF';text=$canonical.Replace("`n","`r`n");bom=$false},
    @{name='historical-mixed';text=$historical;bom=$false},
    @{name='LF-BOM';text=$canonical;bom=$true},
    @{name='CRLF-BOM';text=$canonical.Replace("`n","`r`n");bom=$true}
)
$instructions=@()
foreach($inputCase in $inputs){
    $path=Join-Path $root ($inputCase.name+'.json')
    $encoding=New-Object Text.UTF8Encoding([bool]$inputCase.bom)
    [IO.File]::WriteAllText($path,$inputCase.text,$encoding)
    $identity=Get-LfoP2MapIntegrity $path $lockPath $contractPath
    Assert ($identity.HistoricalSha256 -ceq $expectedHistorical) ($inputCase.name+' historical artifact')
    Assert ($identity.CanonicalSha256 -ceq $expectedCanonical) ($inputCase.name+' canonical bytes')
    Assert ($identity.FileSha256 -ceq (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()) ($inputCase.name+' actual disk bytes')
    $iv=Get-LfoEpistemicIntervention $capsule $p1hash -Enabled -MapPath $path
    Assert ($iv.Enabled -and $iv.InterventionIntegrityContract -ceq 'lfo-l4-p2-integrity-compatibility-v1') ($inputCase.name+' explicit integrity contract')
    $instructions+=,$iv.Instruction
}
Assert (@($instructions|Select-Object -Unique).Count -eq 1) 'representation variants preserve the exact instruction'
# Frozen adapter is loaded in a private module so original and repaired functions
# remain independent; invoke it against the exactly recovered accepted artifact.
$repo=Split-Path -Parent $PSScriptRoot
$frozenSource=& git.exe -c ('safe.directory='+$repo.Replace('\','/')) -C $repo show 'v9.6-l4-p2-frozen:src/LfoEpistemicIntervention.ps1'
if($LASTEXITCODE -ne 0){throw 'Cannot load frozen adapter for differential check.'}
$frozenModulePath=Join-Path $root 'FrozenP2.psm1'
[IO.File]::WriteAllText($frozenModulePath,($frozenSource -join "`n"),$utf8)
$oldModule=Import-Module $frozenModulePath -Prefix FrozenP2 -PassThru -DisableNameChecking
$originalMap=Join-Path $root 'historical-mixed.json'
Assert ((Get-FileHash -LiteralPath $originalMap).Hash.ToLowerInvariant() -ceq $expectedHistorical) 'exact accepted mixed-EOL artifact recovered'
$allDecisions=@('NO_ACTION','REVIEW_FRAMING','REQUEST_COUNTEREVIDENCE','INCREASE_UNCERTAINTY_EXPLICITNESS','CHECK_REINFORCEMENT_PATTERN')
foreach($decision in $allDecisions){foreach($enabled in @($false,$true)){
    $capsule.Decision=$decision
    $old=Get-FrozenP2LfoEpistemicIntervention $capsule $p1hash -MapPath $originalMap -LockPath $lockPath -Enabled:$enabled
    $new=Get-LfoEpistemicIntervention $capsule $p1hash -Enabled:$enabled
    foreach($property in $old.PSObject.Properties.Name){Assert ($old.$property -ceq $new.$property) ($decision+' enabled='+$enabled+' frozen output '+$property)}
    if(-not $enabled -or $decision -ceq 'NO_ACTION'){
        $base=@{model='fixture';messages=@(@{role='system';content='base'},@{role='user';content='question'})}
        $before=$base|ConvertTo-Json -Depth 8 -Compress
        if($new.Enabled){$base.messages[0].content+="`n"+$new.Instruction}
        Assert (($base|ConvertTo-Json -Depth 8 -Compress) -ceq $before) 'OFF/NO_ACTION request identity'
    }
}}
$capsule.Decision='REVIEW_FRAMING'
$tampered=Join-Path $root 'tampered.json'
[IO.File]::WriteAllText($tampered,$canonical.Replace('Do not adopt','Always adopt'),$utf8)
Reject {Get-LfoEpistemicIntervention $capsule $p1hash -Enabled -MapPath $tampered} 'instruction modification rejected'
Reject {Get-LfoEpistemicIntervention $capsule $p1hash -MapPath $tampered} 'OFF does not bypass integrity'
[IO.File]::WriteAllText($tampered,$canonical.TrimEnd("`n"),$utf8)
Reject {Get-LfoP2MapIntegrity $tampered $lockPath} 'missing final newline rejected'
[IO.File]::WriteAllText($tampered,($canonical+' '),$utf8)
Reject {Get-LfoP2MapIntegrity $tampered $lockPath} 'non-EOL whitespace edit rejected'
[IO.File]::WriteAllBytes($tampered,[byte[]]@(255,254,192,175))
Reject {Get-LfoP2MapIntegrity $tampered $lockPath} 'invalid UTF8 rejected'
$badLock=Join-Path $root 'bad-lock.json'
$lock=Get-Content -Raw -Encoding UTF8 -LiteralPath $lockPath|ConvertFrom-Json
$lock.map_sha256=('0'*64)
[IO.File]::WriteAllText($badLock,($lock|ConvertTo-Json),$utf8)
Reject {Get-LfoP2MapIntegrity $mapPath $badLock} 'wrong historical lock rejected'
$lock=Get-Content -Raw -Encoding UTF8 -LiteralPath $lockPath|ConvertFrom-Json
$lock.locked_before_acceptance=$false
[IO.File]::WriteAllText($badLock,($lock|ConvertTo-Json),$utf8)
Reject {Get-LfoP2MapIntegrity $mapPath $badLock} 'unlocked map rejected'
$lock.locked_before_acceptance='false'
[IO.File]::WriteAllText($badLock,($lock|ConvertTo-Json),$utf8)
Reject {Get-LfoP2MapIntegrity $mapPath $badLock} 'truthy nonboolean lock rejected'
$lock.locked_before_acceptance=$true;$lock.intervention_version='9.9.9'
[IO.File]::WriteAllText($badLock,($lock|ConvertTo-Json),$utf8)
Reject {Get-LfoP2MapIntegrity $mapPath $badLock} 'mismatched lock version rejected'
$badContract=Join-Path $root 'bad-contract.json'
foreach($field in @('schema','version','frozen_tag','frozen_commit','frozen_map_git_blob','canonical_map_sha256','historical_map_sha256','canonicalization','historical_serialization','intervention_version')){
    $contract=Get-Content -Raw -Encoding UTF8 -LiteralPath $contractPath|ConvertFrom-Json
    $contract.$field='wrong'
    [IO.File]::WriteAllText($badContract,($contract|ConvertTo-Json),$utf8)
    Reject {Get-LfoP2MapIntegrity $mapPath $lockPath $badContract} ('wrong compatibility '+$field+' rejected')
}
$result=[ordered]@{schema='lfo-l4-p2-integrity-tests-v1';pass=$true;checks=$script:checks;representation_variants=5;differential_decision_enable_combinations=10;model_calls=0;store_writes=0;production_memory_touched=$false}
[IO.File]::WriteAllText($ResultPath,(($result|ConvertTo-Json)+"`n"),$utf8)
Write-Host ('P2_INTEGRITY_PASS: '+$script:checks+' checks; ModelCalls=0; ProductionMemoryTouched=False')
