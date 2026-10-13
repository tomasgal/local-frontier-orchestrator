param([Parameter(Mandatory)][string]$ResultPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/LfoEpistemicPolicyCapsule.ps1')

$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}

$root=Split-Path -Parent $PSScriptRoot
$rulesPath=Join-Path $root 'config/L4P1Policy.rules.json'
$lockPath=Join-Path $root 'config/L4P1Policy.lock.json'
$compatPath=Join-Path $root 'config/L4P1Integrity.compatibility-v1.json'
$fixture=(Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures/l4-p1-policy/cases.json') -Encoding UTF8|ConvertFrom-Json)
$contract=(Get-Content -Raw -LiteralPath $compatPath -Encoding UTF8|ConvertFrom-Json)

Assert ([string]$contract.schema -ceq 'lfo-l4-p1-integrity-compatibility-v1') 'compat schema'
Assert ([string]$contract.frozen_tag -ceq 'v9.6-l4-p1-frozen') 'frozen tag binding'
Assert ([string]$contract.frozen_commit -ceq '28c0ba622761b03af445a8e08939b38396926e0c') 'frozen commit binding'

$active=0;$noaction=0
foreach($case in @($fixture.cases)){
    $capsule=if([bool]$case.enabled){
        Get-LfoEpistemicPolicyCapsule -Evidence $case.evidence -Enabled -CompatibilityPath $compatPath
    }else{
        Get-LfoEpistemicPolicyCapsule -Evidence $case.evidence -CompatibilityPath $compatPath
    }
    Assert ([string]$capsule.Decision -ceq [string]$case.expected) ($case.id+' compatible decision')
    Assert ([string]$capsule.PolicyRulesSha256 -ceq [string]$contract.canonical_rules_sha256) ($case.id+' canonical rules identity')
    if($capsule.Decision -ceq 'NO_ACTION'){$noaction++}else{$active++}
}
Assert ($active -eq 6) 'exact compatible active count'
Assert ($noaction -eq 4) 'exact compatible NO_ACTION count'

# Representation portability: canonical LF, CRLF, and UTF-8 BOM+CRLF.
$utf8=New-Object Text.UTF8Encoding($false,$true)
$canonical=$utf8.GetString([IO.File]::ReadAllBytes($rulesPath))
if($canonical.Length -gt 0 -and $canonical[0] -eq [char]0xFEFF){$canonical=$canonical.Substring(1)}
$canonical=$canonical.Replace(([string][char]13+[char]10),[string][char]10)
$tmp=Join-Path $env:TEMP ('lfo-p1-compat-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp|Out-Null
try{
    $crlf=$canonical.Replace([string][char]10,([string][char]13+[char]10))
    $variants=@(
        [pscustomobject]@{Name='lf';Bytes=$utf8.GetBytes($canonical)},
        [pscustomobject]@{Name='crlf';Bytes=$utf8.GetBytes($crlf)},
        [pscustomobject]@{Name='bom-crlf';Bytes=[byte[]](@(0xEF,0xBB,0xBF)+$utf8.GetBytes($crlf))}
    )
    foreach($v in $variants){
        $p=Join-Path $tmp ($v.Name+'.json')
        [IO.File]::WriteAllBytes($p,[byte[]]$v.Bytes)
        $b=Get-LfoP1Rules -RulesPath $p -LockPath $lockPath -CompatibilityPath $compatPath
        Assert ([string]$b.RulesSha256 -ceq [string]$contract.canonical_rules_sha256) ($v.Name+' canonical hash')
        Assert ([string]$b.GitBlob -ceq [string]$contract.frozen_rules_git_blob) ($v.Name+' frozen blob')
    }
}finally{Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}

$result=[ordered]@{
    schema='lfo-l4-p1-compatibility-result-v1'
    pass=$true
    checks=$script:checks
    cases=@($fixture.cases).Count
    active_cases=$active
    no_action_cases=$noaction
    canonical_rules_sha256=[string]$contract.canonical_rules_sha256
    frozen_rules_git_blob=[string]$contract.frozen_rules_git_blob
    model_calls=0
    store_writes=0
    production_memory_touched=$false
}
[IO.File]::WriteAllText($ResultPath,(($result|ConvertTo-Json -Depth 8)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
Write-Host ('P1_COMPATIBILITY_PASS: '+$script:checks+' checks; Cases='+@($fixture.cases).Count+'; ModelCalls=0; StoreWrites=0; ProductionMemoryTouched=False')