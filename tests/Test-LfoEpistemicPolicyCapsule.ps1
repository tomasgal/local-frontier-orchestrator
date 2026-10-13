param([Parameter(Mandatory)][string]$ResultPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/LfoEpistemicPolicyCapsule.ps1')

$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}
function Throws([scriptblock]$Code,[string]$Message){$ok=$false;try{&$Code}catch{$ok=$true};Assert $ok $Message}

$fixture=(Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'fixtures/l4-p1-policy/cases.json') -Encoding UTF8|ConvertFrom-Json)
$lock=(Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../config/L4P1Policy.lock.json') -Encoding UTF8|ConvertFrom-Json)
Assert ([string]$fixture.schema -ceq 'lfo-l4-p1-policy-acceptance-v1') 'fixture schema'
Assert ([string]$fixture.rules_sha256 -ceq [string]$lock.rules_sha256) 'acceptance corpus bound to pre-acceptance rule hash'
Assert ([bool]$lock.locked_before_acceptance) 'rule lock predates acceptance execution'

$active=0;$noaction=0
foreach($case in @($fixture.cases)){
    $ev=$case.evidence
    $capsule=if([bool]$case.enabled){Get-LfoEpistemicPolicyCapsule -Evidence $ev -Enabled}else{Get-LfoEpistemicPolicyCapsule -Evidence $ev}
    Assert ([string]$capsule.Schema -ceq 'lfo-l4-p1-policy-capsule-v1') ($case.id+' schema')
    Assert ([string]$capsule.Decision -ceq [string]$case.expected) ($case.id+' decision')
    Assert ([string]$capsule.PolicyRulesSha256 -ceq [string]$lock.rules_sha256) ($case.id+' rule hash')
    Assert (@($capsule.SupportingObservationIds).Count -le 12) ($case.id+' support bound')
    if([string]$capsule.Decision -ceq 'NO_ACTION'){
        $noaction++
        Assert (-not [string]$capsule.PolicyRuleId) ($case.id+' no rule id on NO_ACTION')
        Assert (@($capsule.MatchedEvidence).Count -eq 0) ($case.id+' no matched evidence on NO_ACTION')
    }else{
        $active++
        Assert ([string]$capsule.PolicyRuleId -match '^P1-R[0-9]{3}$') ($case.id+' rule id')
        Assert ([string]$capsule.PolicyRuleVersion -ceq '1.0.0') ($case.id+' rule version')
        Assert (-not [string]::IsNullOrWhiteSpace([string]$capsule.ReasonCode)) ($case.id+' reason')
        Assert (@($capsule.MatchedEvidence).Count -ge 1) ($case.id+' matched aggregate')
        Assert (@($capsule.SupportingObservationIds).Count -ge 1) ($case.id+' support ids')
    }
}
Assert ($active -eq 6) 'exact active-case count'
Assert ($noaction -eq 4) 'exact NO_ACTION-case count'

# The adapter strips A2 to the bounded policy evidence surface.
$a2=[pscustomobject]@{
    Schema='lfo-l4-a2-interaction-analytics-v1';StoreId='22222222222222222222222222222222';Epoch=2;FirstTurn=5;LastTurn=8;WindowTurnCount=4
    RecurrenceDensity=@([pscustomobject]@{signature_kind='actor_type';signature='USER|FRAMING';occurrence_count=3;distinct_turn_count=3;window_turn_count=4;annotated_turn_count=4;distinct_turn_fraction=.75;annotated_turn_fraction=.75;supporting_observation_ids=@('00000000000000000000000000000301','00000000000000000000000000000302','00000000000000000000000000000303')})
    ResponseBalance=@([pscustomobject]@{actor='FINAL';linked_response_count=3;reinforced_count=0;challenged_count=1;corrected_count=2;ignored_count=0;reinforced_fraction=0.0;challenged_fraction=(1.0/3.0);corrected_fraction=(2.0/3.0);ignored_fraction=0.0;supporting_observation_ids=@('00000000000000000000000000000304','00000000000000000000000000000305','00000000000000000000000000000306')})
    ActorInteractionChains=@([pscustomobject]@{actor_chain='USER->LOCAL->FINAL';interaction_sequence='REINFORCED>CORRECTED';count=1;supporting_observation_ids=@('00000000000000000000000000000307')})
    TypeChains=@();ChainOccurrenceCount=1;ExcludedBoundaryLinks=0;ExcludedBoundaryChains=0;UnclassifiedLinkedInteractions=0
    SupportingObservationIds=@('00000000000000000000000000000301');Interpretation='descriptive'
}
$adapted=ConvertTo-LfoP1Evidence $a2
Assert ([string]$adapted.Schema -ceq 'lfo-l4-p1-policy-evidence-v1') 'adapter schema'
Assert (@($adapted.PSObject.Properties.Name).Count -eq 9) 'adapter exact top-level property count'
Assert ($null -eq $adapted.PSObject.Properties['ActorInteractionChains']) 'adapter excludes chain surface not used by P1'
Assert ($null -eq $adapted.PSObject.Properties['Interpretation']) 'adapter excludes free text'
Assert ((Get-LfoEpistemicPolicyCapsule -Evidence $adapted -Enabled).Decision -ceq 'REVIEW_FRAMING') 'adapter-to-policy path'

# Hard failures for non-canonical or unbounded evidence.
$badSchema=$adapted|ConvertTo-Json -Depth 20|ConvertFrom-Json;$badSchema.Schema='wrong'
Throws {Get-LfoEpistemicPolicyCapsule -Evidence $badSchema -Enabled|Out-Null} 'wrong schema rejected'
$badId=$adapted|ConvertTo-Json -Depth 20|ConvertFrom-Json;$badId.RecurrenceDensity[0].supporting_observation_ids=@('not-an-id')
Throws {Get-LfoEpistemicPolicyCapsule -Evidence $badId -Enabled|Out-Null} 'bad support id rejected'
$extra=$adapted|ConvertTo-Json -Depth 20|ConvertFrom-Json;$extra|Add-Member -NotePropertyName Excerpt -NotePropertyValue 'raw text'
Throws {Get-LfoEpistemicPolicyCapsule -Evidence $extra -Enabled|Out-Null} 'raw/extra field rejected'
$badWindow=$adapted|ConvertTo-Json -Depth 20|ConvertFrom-Json;$badWindow.WindowTurnCount=99
Throws {Get-LfoEpistemicPolicyCapsule -Evidence $badWindow -Enabled|Out-Null} 'window mismatch rejected'

# Pure-policy static boundary: no transport, store mutation, model or process launch.
$src=[IO.File]::ReadAllText((Join-Path $PSScriptRoot '../src/LfoEpistemicPolicyCapsule.ps1'))
foreach($token in @('Invoke-WebRequest','Invoke-RestMethod','Invoke-LfoEpistemicQuery','Add-LfoEpistemicObservation','Start-Process','ollama.exe','codex.exe')){
    Assert (-not $src.Contains($token)) ('forbidden dependency absent: '+$token)
}

$result=[ordered]@{
    schema='lfo-l4-p1-acceptance-result-v1'
    pass=$true
    checks=$script:checks
    cases=@($fixture.cases).Count
    active_cases=$active
    no_action_cases=$noaction
    rules_sha256=[string]$lock.rules_sha256
    model_calls=0
    automatic_r1_writes=0
    production_memory_touched=$false
}
$enc=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($ResultPath,(($result|ConvertTo-Json -Depth 10)+"`n"),$enc)
Write-Host ('P1_POLICY_PASS: '+$script:checks+' checks; Cases='+@($fixture.cases).Count+'; Active='+$active+'; NO_ACTION='+$noaction+'; ModelCalls=0; ProductionMemoryTouched=False')
