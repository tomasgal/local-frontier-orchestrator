# Experimental G2 policy. Dot-sourcing is side-effect free.
function Get-LfoG2HybridProfile {
    param([Parameter(Mandatory)][string]$ConfigPath,[string]$Profile)
    $cfg=Import-PowerShellDataFile -LiteralPath $ConfigPath
    if($cfg.SchemaVersion -ne 1 -or $cfg.DefaultProfile -cnotin @('COMPACT_CPU','SCOPED_CPU')){throw 'Invalid G2 profile configuration.'}
    if(-not $Profile){$Profile=[string]$cfg.DefaultProfile}
    if($Profile -cnotin @('COMPACT_CPU','SCOPED_CPU')){throw "Unknown G2 profile: $Profile"}
    $p=$cfg.Profiles[$Profile]
    $expected=if($Profile -ceq 'COMPACT_CPU'){'COMPACT'}else{'SCOPED'}
    if($null -eq $p -or $p.PredicateContract -cne $expected -or $p.CpuGate -isnot [bool] -or -not $p.CpuGate){throw "Invalid G2 profile definition: $Profile"}
    [pscustomobject]@{Name=$Profile;PredicateContract=$expected;CpuGate=$true;ContractVersion='semantic-provenance-p61-v1'}
}
function Get-LfoG2CpuGate {
    param($Metadata,[switch]$TrustedEnvelope)
    # TrustedEnvelope must be set by the wrapper, never derived from user/model content.
    # A kind/origin string alone cannot establish trust.
    if(-not $TrustedEnvelope -or $null -eq $Metadata -or $Metadata.origin -cne 'WRAPPER' -or $Metadata.coverage -cne 'ENTIRE_TARGET' -or $Metadata.target_available -isnot [bool]){return 'NPU'}
    if($Metadata.kind -ceq 'LITERAL_ONLY' -and $Metadata.target_available){return 'C'}
    if($Metadata.kind -ceq 'ASSERTION_TARGET_MISSING' -and -not $Metadata.target_available){return 'U'}
    return 'NPU'
}
function Resolve-LfoG2Provenance {
    param([string]$Semantic,[string]$Runtime)
    if($Semantic -cnotin @('present','absent','unknown') -or $Runtime -cnotin @('NONE','UNKNOWN','MATCHED')){return 'INVALID'}
    if($Semantic -ceq 'absent'){return 'C'}
    if($Semantic -ceq 'unknown' -or $Runtime -ceq 'UNKNOWN'){return 'U'}
    if($Runtime -ceq 'NONE'){return 'D'}
    return 'C'
}
function New-LfoG2HybridPlan {
    param([Parameter(Mandatory)]$Profile,[Parameter(Mandatory)][ValidateSet('PRE','POST')][string]$Phase,[AllowEmptyString()][string]$Text,$Metadata,[switch]$TrustedEnvelope)
    if($Profile.PredicateContract -cnotin @('COMPACT','SCOPED') -or $Profile.CpuGate -ne $true){throw 'Invalid resolved profile.'}
    $gate=Get-LfoG2CpuGate -Metadata $Metadata -TrustedEnvelope:$TrustedEnvelope
    if($gate -cne 'NPU'){
        return [pscustomobject]@{Profile=$Profile.Name;Contract=$Profile.PredicateContract;ContractVersion=$Profile.ContractVersion;Phase=$Phase;Decision=$gate;RequiresNpu=$false;Body=$null}
    }
    if($Profile.PredicateContract -ceq 'COMPACT'){
        $q=if($Phase -ceq 'PRE'){'Does the user request a claim of already completed assistant lookup, not a future lookup?'}else{'Does the assistant claim its own completed external lookup, not another actor, quotation or hypothetical?'}
        $criteria=@{present='Present';absent='Absent';unknown='Undetermined from text'}
    }else{
        $q=if($Phase -ceq 'PRE'){'Does the user ask the assistant to state as fact that it already did an external lookup?'}else{'Does the assistant state as fact that it personally already did an external lookup?'}
        $criteria=@{present='Own completed lookup asserted as fact (PRE: requested assertion)';absent='No such assertion; only other actor, quote, fiction, denial, future or hypothetical';unknown='Relevant assertion missing or meaning undetermined'}
    }
    $body=@{state=$Text;questions=@{V=@{type='choice';instructions=$q;criteria=$criteria}}}
    [pscustomobject]@{Profile=$Profile.Name;Contract=$Profile.PredicateContract;ContractVersion=$Profile.ContractVersion;Phase=$Phase;Decision=$null;RequiresNpu=$true;Body=$body}
}

function Get-LfoG2ExecutionPolicy {
    param([Parameter(Mandatory)][string]$ConfigPath,[string]$Topology,[bool]$Parallelism,[string]$EdgeDeviceId,[string]$MainDeviceId)
    $cfg=Import-PowerShellDataFile -LiteralPath $ConfigPath
    if($cfg.SchemaVersion -ne 1 -or $null -eq $cfg.Execution -or $cfg.Execution.Parallelism -isnot [bool]){throw 'Invalid execution configuration.'}
    if(-not $PSBoundParameters.ContainsKey('Topology')){$Topology=[string]$cfg.Execution.Topology}
    if(-not $PSBoundParameters.ContainsKey('Parallelism')){$Parallelism=$cfg.Execution.Parallelism}
    if(-not $PSBoundParameters.ContainsKey('EdgeDeviceId')){$EdgeDeviceId=[string]$cfg.Execution.EdgeDeviceId}
    if(-not $PSBoundParameters.ContainsKey('MainDeviceId')){$MainDeviceId=[string]$cfg.Execution.MainDeviceId}
    if($Topology -cnotin @('AUTO','CPU_GPU','NPU_GPU','GPU_GPU','CPU_CPU','NPU_CPU','GPU_CPU')){throw "Unknown execution topology: $Topology"}
    $edge='AUTO';$main='AUTO'
    if($Topology -cne 'AUTO'){$edge,$main=$Topology.Split('_')}
    [pscustomobject]@{Topology=$Topology;EdgeTarget=$edge;MainTarget=$main;EdgeDeviceId=$EdgeDeviceId;MainDeviceId=$MainDeviceId;Parallelism=$Parallelism}
}
function Get-LfoG2DispatchMode {
    param([Parameter(Mandatory)]$ExecutionPolicy,[Parameter(Mandatory)][ValidateSet('BLOCKING','INDEPENDENT','POST_REQUIRED')][string]$Dependency,[bool]$InputsReady,[bool]$RuntimeSupportsParallel)
    # RuntimeSupportsParallel is an explicit capability assertion by the adapter.
    # Placement names and config switches do not establish device availability.
    if(-not $InputsReady){return 'WAIT_DEPENDENCY'}
    if($Dependency -ceq 'BLOCKING'){return 'BEFORE_MAIN'}
    if($Dependency -ceq 'POST_REQUIRED'){return 'AFTER_OUTPUT'}
    if($ExecutionPolicy.Parallelism -eq $true -and $RuntimeSupportsParallel){return 'PARALLEL'}
    return 'SERIAL'
}

function Get-LfoG2ModelBinding {
    param([Parameter(Mandatory)][string]$ConfigPath,[Parameter(Mandatory)][ValidateSet('Main','Edge','Frontier')][string]$Role,[string]$Adapter,[string]$ModelId)
    $cfg=Import-PowerShellDataFile -LiteralPath $ConfigPath
    if($cfg.SchemaVersion -ne 1 -or $null -eq $cfg.Models -or $null -eq $cfg.Models[$Role]){throw "Missing model binding: $Role"}
    $binding=$cfg.Models[$Role]
    if(-not $PSBoundParameters.ContainsKey('Adapter')){$Adapter=[string]$binding.Adapter}
    if(-not $PSBoundParameters.ContainsKey('ModelId')){$ModelId=[string]$binding.ModelId}
    $enabled=$true
    if($Role -eq 'Frontier'){
        if($binding.Enabled -isnot [bool]){throw 'Frontier Enabled must be boolean.'}
        $enabled=$binding.Enabled
    }
    if($enabled -and ([string]::IsNullOrWhiteSpace($Adapter) -or [string]::IsNullOrWhiteSpace($ModelId))){throw "Incomplete model binding: $Role"}
    # A binding is declarative; actual availability, locality, capabilities,
    # credentials and outbound dispatch authorization belong to runtime adapters.
    [pscustomobject]@{Role=$Role;Adapter=$Adapter;ModelId=$ModelId;Enabled=$enabled}
}
