# L4 integrated runtime bridge.
# Import is pure. No detector, store write, model call, prompt injection or process launch.
# Ordinary turns remain default-OFF. Explicit review/one-shot intervention reads only
# already stored R1 annotations and bounded A2/P1/P2 surfaces.

function Initialize-LfoEpistemicRuntime {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$LogDirectory
    )
    $state=[ordered]@{
        Schema='lfo-l4-runtime-state-v1'
        Configured=$false
        Available=$false
        RecordRuntimeStatus=$false
        AllowExplicitReview=$false
        AllowExplicitOneShotIntervention=$false
        Endpoint=''
        StoreId=''
        Connection=$null
        CompatibilityPath=(Join-Path $PSScriptRoot '../config/L4P1Integrity.compatibility-v1.json')
        Error=$null
    }
    if($null -eq $Config -or -not $Config.ContainsKey('Epistemic')){return [pscustomobject]$state}
    $e=$Config.Epistemic
    if($null -eq $e -or -not [bool]$e.Enabled){return [pscustomobject]$state}
    $state.Configured=$true
    $state.RecordRuntimeStatus=($e.ContainsKey('RecordRuntimeStatus') -and [bool]$e.RecordRuntimeStatus)
    $state.AllowExplicitReview=($e.ContainsKey('AllowExplicitReview') -and [bool]$e.AllowExplicitReview)
    $state.AllowExplicitOneShotIntervention=($e.ContainsKey('AllowExplicitOneShotIntervention') -and [bool]$e.AllowExplicitOneShotIntervention)

    # Automatic policy/intervention is deliberately unsupported in this v1 bridge.
    if(($e.ContainsKey('PolicyEnabled') -and [bool]$e.PolicyEnabled) -or
       ($e.ContainsKey('InterventionEnabled') -and [bool]$e.InterventionEnabled)){
        $state.Error='Automatic L4 policy/intervention is not authorized by the v1 runtime bridge; keep both settings false.'
        return [pscustomobject]$state
    }
    try{
        $endpoint=[string]$e.Endpoint
        $credentialPath=[Environment]::ExpandEnvironmentVariables([string]$e.CredentialPath)
        if([string]::IsNullOrWhiteSpace($endpoint)){throw 'L4 endpoint is missing.'}
        if(-not(Test-Path -LiteralPath $credentialPath -PathType Leaf)){throw 'L4 runtime credential is unavailable.'}
        $version=Invoke-RestMethod -Uri ($endpoint.TrimEnd('/')+'/version') -TimeoutSec 3
        if([string]$version -notmatch '(^|[- ])3\.3\.0($|[ +])'){throw 'L4 requires SurrealDB 3.3.0.'}
        $credential=Import-Clixml -LiteralPath $credentialPath
        if($credential -isnot [Management.Automation.PSCredential] -or $credential.UserName -cne 'lfo_r1'){throw 'Invalid L4 runtime credential.'}
        $storeId=Register-LfoEpistemicL0Store -LogDirectory $LogDirectory
        $connection=New-LfoEpistemicConnection -Endpoint $endpoint -Credential $credential
        $state.Endpoint=$endpoint.TrimEnd('/')
        $state.StoreId=$storeId
        $state.Connection=$connection
        $state.Available=$true
    }catch{
        $state.Error=$_.Exception.Message
        $state.Available=$false
    }
    return [pscustomobject]$state
}

function Get-LfoEpistemicRuntimeStatus {
    param([Parameter(Mandatory)]$Runtime)
    return [pscustomobject][ordered]@{
        Schema='lfo-l4-runtime-status-v1'
        Configured=[bool]$Runtime.Configured
        Available=[bool]$Runtime.Available
        Endpoint=[string]$Runtime.Endpoint
        StoreId=[string]$Runtime.StoreId
        AutomaticPolicyEnabled=$false
        AutomaticInterventionEnabled=$false
        AllowExplicitReview=[bool]$Runtime.AllowExplicitReview
        AllowExplicitOneShotIntervention=[bool]$Runtime.AllowExplicitOneShotIntervention
        Error=$Runtime.Error
    }
}

function Get-LfoEpistemicRuntimeReview {
    param(
        [Parameter(Mandatory)]$Runtime,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Epoch,
        [Parameter(Mandatory)][ValidateRange(0,2147483647)][int]$LastTurn,
        [ValidateRange(1,64)][int]$WindowTurns=8,
        [switch]$EnableIntervention
    )
    if(-not [bool]$Runtime.Configured){return [pscustomobject]@{Status='disabled';Decision='NO_ACTION';ReasonCode='L4_DISABLED';InterventionActive=$false;Instruction='';Support=@();Error=$null}}
    if(-not [bool]$Runtime.Available){return [pscustomobject]@{Status='unavailable';Decision='NO_ACTION';ReasonCode='L4_UNAVAILABLE';InterventionActive=$false;Instruction='';Support=@();Error=$Runtime.Error}}
    if(-not [bool]$Runtime.AllowExplicitReview){return [pscustomobject]@{Status='not_authorized';Decision='NO_ACTION';ReasonCode='EXPLICIT_REVIEW_DISABLED';InterventionActive=$false;Instruction='';Support=@();Error=$null}}
    if($EnableIntervention -and -not [bool]$Runtime.AllowExplicitOneShotIntervention){return [pscustomobject]@{Status='not_authorized';Decision='NO_ACTION';ReasonCode='EXPLICIT_INTERVENTION_DISABLED';InterventionActive=$false;Instruction='';Support=@();Error=$null}}
    if($LastTurn -lt 1){return [pscustomobject]@{Status='no_turns';Decision='NO_ACTION';ReasonCode='NO_PERSISTED_TURNS';InterventionActive=$false;Instruction='';Support=@();Error=$null}}

    $first=[Math]::Max(1,$LastTurn-$WindowTurns+1)
    try{
        $summary=Get-LfoEpistemicInteractionAnalytics -Connection $Runtime.Connection -StoreId $Runtime.StoreId -Epoch $Epoch -FirstTurn $first -LastTurn $LastTurn
        $evidence=ConvertTo-LfoP1Evidence $summary
        $capsule=Get-LfoEpistemicPolicyCapsule -Evidence $evidence -Enabled -CompatibilityPath $Runtime.CompatibilityPath
        $intervention=Get-LfoEpistemicIntervention -PolicyCapsule $capsule -ExpectedPolicyRulesSha256 ([string]$capsule.PolicyRulesSha256) -Enabled:$EnableIntervention
        return [pscustomobject][ordered]@{
            Status='ok'
            Epoch=$Epoch
            FirstTurn=$first
            LastTurn=$LastTurn
            ObservationCount=[int]$summary.ObservationCount
            Decision=[string]$capsule.Decision
            PolicyRuleId=[string]$capsule.PolicyRuleId
            PolicyRuleVersion=[string]$capsule.PolicyRuleVersion
            PolicyRulesSha256=[string]$capsule.PolicyRulesSha256
            ReasonCode=[string]$capsule.ReasonCode
            Support=@($capsule.SupportingObservationIds)
            InterventionActive=[bool]$intervention.Enabled
            InterventionVersion=[string]$intervention.InterventionVersion
            Instruction=[string]$intervention.Instruction
            Error=$null
        }
    }catch{
        return [pscustomobject]@{Status='failed';Decision='NO_ACTION';ReasonCode='L4_REVIEW_FAILED';InterventionActive=$false;Instruction='';Support=@();Error=$_.Exception.Message}
    }
}

function New-LfoEpistemicRuntimeTurnTrace {
    param(
        [Parameter(Mandatory)]$Runtime,
        $ArmedReview=$null,
        [bool]$Attempted=$false
    )
    if(-not [bool]$Runtime.RecordRuntimeStatus){return $null}
    return [pscustomobject][ordered]@{
        schema='lfo-l4-runtime-turn-trace-v1'
        configured=[bool]$Runtime.Configured
        available=[bool]$Runtime.Available
        automatic_policy_enabled=$false
        automatic_intervention_enabled=$false
        explicit_one_shot_armed=($null -ne $ArmedReview -and [bool]$ArmedReview.InterventionActive)
        explicit_one_shot_attempted=$Attempted
        policy_decision=$(if($null -ne $ArmedReview){[string]$ArmedReview.Decision}else{'NO_ACTION'})
        policy_reason=$(if($null -ne $ArmedReview){[string]$ArmedReview.ReasonCode}else{'DEFAULT_OFF'})
        policy_rule_id=$(if($null -ne $ArmedReview){[string]$ArmedReview.PolicyRuleId}else{''})
        support_count=$(if($null -ne $ArmedReview){@($ArmedReview.Support).Count}else{0})
    }
}