param(
    [Parameter(Mandatory)][string]$ResultPath,
    [Parameter(Mandatory)][string]$P1RulesPath,
    [Parameter(Mandatory)][string]$P1LockPath
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/LfoEpistemicPolicyCapsule.ps1')
. (Join-Path $PSScriptRoot '../src/LfoEpistemicIntervention.ps1')

$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Throws([scriptblock]$Code,[string]$Message){$ok=$false;try{&$Code}catch{$ok=$true};Assert $ok $Message}
function Capsule($case){
    if([bool]$case.policy_enabled){
        return Get-LfoEpistemicPolicyCapsule -Evidence $case.evidence -Enabled -RulesPath $P1RulesPath -LockPath $P1LockPath
    }
    return Get-LfoEpistemicPolicyCapsule -Evidence $case.evidence -RulesPath $P1RulesPath -LockPath $P1LockPath
}

$p1Hash=(Get-FileHash -Algorithm SHA256 -LiteralPath $P1RulesPath).Hash.ToLowerInvariant()
$fixture=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures/l4-p2-intervention/cases.json') -Encoding UTF8|ConvertFrom-Json
$lock=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../config/L4P2Intervention.lock.json') -Encoding UTF8|ConvertFrom-Json
Assert ([string]$fixture.schema -ceq 'lfo-l4-p2-intervention-corpus-v1') 'fixture schema'
Assert ([string]$fixture.intervention_map_sha256 -ceq [string]$lock.map_sha256) 'fixture bound to locked intervention map'
Assert ([bool]$lock.locked_before_acceptance) 'intervention map locked before acceptance'

$active=0;$noaction=0
foreach($case in @($fixture.cases)){
    $capsule=Capsule $case
    Assert ([string]$capsule.Decision -ceq [string]$case.expected_policy) ($case.id+' frozen P1 decision')
    Assert ([string]$capsule.PolicyRulesSha256 -ceq $p1Hash) ($case.id+' compatibility-verified P1 byte identity')
    $iv=Get-LfoEpistemicIntervention -PolicyCapsule $capsule -ExpectedPolicyRulesSha256 $p1Hash -Enabled
    Assert ([string]$iv.Schema -ceq 'lfo-l4-p2-intervention-v1') ($case.id+' intervention schema')
    Assert ([string]$iv.InterventionMapSha256 -ceq [string]$lock.map_sha256) ($case.id+' map hash')
    Assert (-not [bool]$iv.MutatesAnswer) ($case.id+' no direct mutation')
    Assert (-not [bool]$iv.PersistentState) ($case.id+' no persistent state')
    if([string]$case.expected_policy -ceq 'NO_ACTION'){
        $noaction++
        Assert (-not [bool]$iv.Enabled) ($case.id+' NO_ACTION disabled')
        Assert ([string]::IsNullOrEmpty([string]$iv.Instruction)) ($case.id+' NO_ACTION empty instruction')
    }else{
        $active++
        Assert ([bool]$iv.Enabled) ($case.id+' active intervention enabled')
        Assert (-not [string]::IsNullOrWhiteSpace([string]$iv.Instruction)) ($case.id+' active instruction present')
    }
}
Assert ($active -eq 8) '8 active cases'
Assert ($noaction -eq 2) '2 no-action cases'

$src=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/LfoEpistemicIntervention.ps1'))
foreach($token in @('Invoke-WebRequest','Invoke-RestMethod','Invoke-LfoEpistemicQuery','Add-LfoEpistemicObservation','Start-Process','ollama.exe','codex.exe')){
    Assert (-not $src.Contains($token)) ('adapter forbidden dependency absent: '+$token)
}

$good=Capsule $fixture.cases[0]
$wrong='0000000000000000000000000000000000000000000000000000000000000000'
Throws {Get-LfoEpistemicIntervention -PolicyCapsule $good -ExpectedPolicyRulesSha256 $wrong -Enabled|Out-Null} 'wrong compatibility hash rejected'
$bad=$good|ConvertTo-Json -Depth 20|ConvertFrom-Json;$bad.Decision='UNKNOWN'
Throws {Get-LfoEpistemicIntervention -PolicyCapsule $bad -ExpectedPolicyRulesSha256 $p1Hash -Enabled|Out-Null} 'unknown decision rejected'

$result=[ordered]@{
 schema='lfo-l4-p2-offline-acceptance-v2';pass=$true;checks=$script:checks
 active_cases=$active;no_action_cases=$noaction;model_calls=0;store_writes=0
 production_memory_touched=$false;intervention_map_sha256=[string]$lock.map_sha256
 p1_compatibility_rules_sha256=$p1Hash
}
$enc=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($ResultPath,(($result|ConvertTo-Json -Depth 10)+"`n"),$enc)
Write-Host ('P2_OFFLINE_PASS: '+$script:checks+' checks; Active=8; NO_ACTION=2; ModelCalls=0; ProductionMemoryTouched=False')
