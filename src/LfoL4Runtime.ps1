# LFO v9.6.1 ordinary-runtime adapter over frozen L4 components.
# Import is side-effect free. D1 remains offline and is not imported or called here.

foreach ($moduleName in @('LfoEpistemicStore.ps1','LfoEpistemicObservatory.ps1','LfoEpistemicInteractionAnalytics.ps1','LfoEpistemicPolicyCapsule.ps1','LfoEpistemicIntervention.ps1')) {
    $modulePath=Join-Path $PSScriptRoot $moduleName
    if(-not (Test-Path -LiteralPath $modulePath -PathType Leaf)){throw "Required L4 runtime dependency missing: $modulePath"}
    . $modulePath
}

function Get-LfoL4EnvBool([string]$Name,[bool]$Default){
    $raw=[Environment]::GetEnvironmentVariable($Name)
    if([string]::IsNullOrWhiteSpace($raw)){return $Default}
    if($raw.Trim().ToLowerInvariant() -in @('1','true','yes','on')){return $true}
    if($raw.Trim().ToLowerInvariant() -in @('0','false','no','off')){return $false}
    return $Default
}
function Resolve-LfoL4Bool($Explicit,[string]$Name,[bool]$Default){
    if($null -ne $Explicit){return [bool]$Explicit}
    return Get-LfoL4EnvBool $Name $Default
}
function Write-LfoL4RuntimeStatus([string]$Message,[string]$Color='DarkGray'){
    if($null -eq $script:LfoL4State -or -not [bool]$script:LfoL4State.Observability){return}
    Write-Host ("[L4 {0}]" -f $Message) -ForegroundColor $Color
}
function Get-LfoL4RuntimeState{return $script:LfoL4State}
function Get-LfoL4ByteDigest([byte[]]$Bytes,[string]$Algorithm='SHA256'){
    $h=[Security.Cryptography.HashAlgorithm]::Create($Algorithm)
    try{return ([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
}

function Initialize-LfoL4Runtime {
    param(
        [Parameter(Mandatory)][string]$LogDirectory,
        [bool]$MemoryEnabled=$true,
        [bool]$L0StageSourcesEnabled=$true,
        [Nullable[bool]]$Enabled=$null,
        [Nullable[bool]]$PolicyEnabled=$null,
        [Nullable[bool]]$InterventionEnabled=$null,
        [Nullable[bool]]$Observability=$null,
        [string]$Endpoint='',
        [pscredential]$Credential=$null,
        [string]$CredentialPath='',
        [string]$ConfigPath=''
    )
    if([string]::IsNullOrWhiteSpace($ConfigPath)){$ConfigPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'config\L4Runtime.psd1'}
    try{$cfg=Import-PowerShellDataFile -LiteralPath $ConfigPath -ErrorAction Stop}catch{
        $script:LfoL4State=[pscustomobject]@{Enabled=$false;Available=$false;Reason='config-unavailable';Observability=$false;CurrentIntervention=$null;PendingIntervention=$null}
        return $script:LfoL4State
    }
    $enabledDefault=if($cfg.ContainsKey('Enabled')){[bool]$cfg.Enabled}else{$false}
    $policyDefault=if($cfg.ContainsKey('PolicyEnabled')){[bool]$cfg.PolicyEnabled}else{$false}
    $interventionDefault=if($cfg.ContainsKey('InterventionEnabled')){[bool]$cfg.InterventionEnabled}else{$false}
    $observeDefault=if($cfg.ContainsKey('Observability')){[bool]$cfg.Observability}else{$false}
    $isEnabled=Resolve-LfoL4Bool $Enabled 'LFO_L4_ENABLED' $enabledDefault
    $policyOn=Resolve-LfoL4Bool $PolicyEnabled 'LFO_L4_POLICY' $policyDefault
    $p2On=Resolve-LfoL4Bool $InterventionEnabled 'LFO_L4_INTERVENTION' $interventionDefault
    $observe=Resolve-LfoL4Bool $Observability 'LFO_L4_OBSERVABILITY' $observeDefault
    $script:LfoL4State=[pscustomobject]@{
        Enabled=$isEnabled;Available=$false;Reason=$(if($isEnabled){'initializing'}else{'disabled'});Observability=$observe
        PolicyEnabled=$policyOn;InterventionEnabled=$p2On;LogDirectory=$LogDirectory;StoreId='';Connection=$null
        Detector='l4.runtime.t1';DetectorVersion=$(if($cfg.ContainsKey('DetectorVersion')){[string]$cfg.DetectorVersion}else{'1.0.0'})
        WindowTurns=$(if($cfg.ContainsKey('AnalyticsWindowTurns')){[int]$cfg.AnalyticsWindowTurns}else{8})
        MinSignalTurns=$(if($cfg.ContainsKey('MinSignalTurnsBeforeAnalytics')){[int]$cfg.MinSignalTurnsBeforeAnalytics}else{2})
        CooldownTurns=$(if($cfg.ContainsKey('AnalyticsCooldownTurns')){[int]$cfg.AnalyticsCooldownTurns}else{1})
        PageSize=$(if($cfg.ContainsKey('PageSize')){[int]$cfg.PageSize}else{50})
        MaxRecords=$(if($cfg.ContainsKey('MaxRecords')){[int]$cfg.MaxRecords}else{200})
        SupportLimit=$(if($cfg.ContainsKey('SupportLimit')){[int]$cfg.SupportLimit}else{12})
        SignalTurns=0;LastSignalTurn=0;LastAnalyticsTurn=0;CurrentIntervention=$null;PendingIntervention=$null;LastResult=$null
    }
    if(-not $isEnabled){Write-LfoL4RuntimeStatus 'runtime -> DISABLED';return $script:LfoL4State}
    if(-not $MemoryEnabled -or -not $L0StageSourcesEnabled){
        $script:LfoL4State.Reason='l0-provenance-disabled'
        Write-LfoL4RuntimeStatus 'runtime -> UNAVAILABLE reason=l0-provenance-disabled' 'Yellow'
        return $script:LfoL4State
    }
    try{
        $dir=Get-Item -LiteralPath $LogDirectory -ErrorAction Stop
        if(-not $dir.PSIsContainer){throw 'L0 log directory unavailable'}
        if([string]::IsNullOrWhiteSpace($Endpoint)){$Endpoint=[Environment]::GetEnvironmentVariable('LFO_L4_ENDPOINT')}
        if([string]::IsNullOrWhiteSpace($Endpoint) -and $cfg.ContainsKey('Endpoint')){$Endpoint=[string]$cfg.Endpoint}
        if($null -eq $Credential){
            if([string]::IsNullOrWhiteSpace($CredentialPath)){$CredentialPath=[Environment]::GetEnvironmentVariable('LFO_L4_RUNTIME_CREDENTIAL')}
            if([string]::IsNullOrWhiteSpace($CredentialPath) -and $cfg.ContainsKey('CredentialPath')){$CredentialPath=[string]$cfg.CredentialPath}
            if([string]::IsNullOrWhiteSpace($CredentialPath)){throw 'L4 credential path not configured'}
            $Credential=Import-Clixml -LiteralPath $CredentialPath -ErrorAction Stop
        }
        if([string]::IsNullOrWhiteSpace($Endpoint)){throw 'L4 endpoint not configured'}
        $timeout=if($cfg.ContainsKey('TimeoutSec')){[int]$cfg.TimeoutSec}else{3}
        $conn=New-LfoEpistemicConnection -Endpoint $Endpoint -Credential $Credential -TimeoutSec $timeout
        $null=Invoke-LfoEpistemicQuery $conn 'RETURN 1;'
        $store=Register-LfoEpistemicL0Store -LogDirectory $dir.FullName
        $script:LfoL4State.Connection=$conn;$script:LfoL4State.StoreId=$store;$script:LfoL4State.Available=$true;$script:LfoL4State.Reason='ready'
        Write-LfoL4RuntimeStatus ("runtime -> READY policy={0} p2={1}" -f $(if($policyOn){'ON'}else{'OFF'}),$(if($p2On){'ON'}else{'OFF'})) 'Green'
    }catch{
        $script:LfoL4State.Available=$false;$script:LfoL4State.Reason='store-unavailable'
        Write-LfoL4RuntimeStatus 'runtime -> UNAVAILABLE reason=store-unavailable' 'Yellow'
    }
    return $script:LfoL4State
}

function Test-LfoL4AsymmetricEvidenceRequest([string]$Text){
    if([string]::IsNullOrWhiteSpace($Text)){return $false}
    $patterns=@(
        '(?is)\b(?:nezauj[ií]maj[uú]\s+ma|nechcem|vynechaj|ignoruj)\b.{0,90}\b(?:protiargument\p{L}*|protichodn\p{L}*\s+d[oô]kaz\p{L}*|opa[cč]n\p{L}*\s+d[oô]kaz\p{L}*)',
        '(?is)\b(?:argument\p{L}*|d[oô]kaz\p{L}*)\b.{0,100}\b(?:potvrd\p{L}*|podpor\p{L}*)\b.{0,100}\b(?:m[oô]j|n[aá]zor\p{L}*|stanovisk\p{L}*)',
        '(?is)\b(?:chcem|daj|n[aá]jdi|uve[dď]|uk[aá][zž]|predlo[zž])\p{L}*.{0,60}\b(?:len|iba)\b.{0,80}\b(?:d[oô]kaz\p{L}*|argument\p{L}*)\b.{0,100}\b(?:m[aá]m\s+pravdu|potvrd\p{L}*|podpor\p{L}*)',
        "(?is)\b(?:i\s+do\s+not|i\s+don't|i\s+dont)\s+(?:want|care\s+about)\b.{0,80}\b(?:counterarguments?|opposing\s+evidence|evidence\s+against)\b",
        "(?is)\b(?:arguments?|evidence)\b.{0,100}\b(?:support|confirm|prove)\w*\b.{0,100}\b(?:my\s+(?:view|position|opinion)|i(?:'m|\s+am)\s+right)\b",
        "(?is)\b(?:i\s+want|give\s+me|find|show|provide)\b.{0,60}\bonly\b.{0,80}\b(?:arguments?|evidence)\b.{0,100}\b(?:i(?:'m|\s+am)\s+right|support|confirm|prove)\w*\b"
    )
    foreach($p in $patterns){if($Text -match $p){return $true}};return $false
}
function Test-LfoL4ExplicitFraming([string]$Text){
    if([string]::IsNullOrWhiteSpace($Text)){return $false}
    $patterns=@(
        '(?is)\b(?:ber|pova[zž]uj|pokladaj)\b.{0,80}\b(?:za\s+fakt|za\s+preuk[aá]zan[eé]|za\s+dok[aá]zan[eé])\b',
        '(?is)\b(?:nespochyb[nň]uj|nespochyb[nň]ujte)\b.{0,50}\b(?:premisu|v[yý]chodisko|tvrdenie)\b',
        '(?is)\b(?:treat|take|accept)\b.{0,80}\bas\b.{0,20}\b(?:a\s+fact|established|proven)\b',
        '(?is)\bdo\s+not\b.{0,25}\b(?:question|challenge)\b.{0,50}\b(?:the\s+)?premise\b'
    )
    foreach($p in $patterns){if($Text -match $p){return $true}};return $false
}
function Test-LfoL4ExplicitCounterevidenceIgnored([string]$Prompt,[string]$FinalContent){
    if(-not (Test-LfoL4AsymmetricEvidenceRequest $Prompt) -or [string]::IsNullOrWhiteSpace($FinalContent)){return $false}
    if($FinalContent -match '(?is)\b(?:protiargument\p{L}*|na\s+druhej\s+strane|av[sš]ak|opposing\s+evidence|counterarguments?|on\s+the\s+other\s+hand|however)\b'){return $false}
    $patterns=@(
        '(?is)\b(?:uvediem|d[aá]m|pon[uú]knem|zameriam\s+sa|s[uú]stred[ií]m\s+sa)\b.{0,80}\b(?:len|iba)\b.{0,100}\b(?:d[oô]kaz\p{L}*|argument\p{L}*|podpor\p{L}*)',
        '(?is)\btu\s+s[uú]\b.{0,40}\b(?:d[oô]kazy|argumenty)\b.{0,100}\b(?:potvrd\p{L}*|podpor\p{L}*)',
        '(?is)\b(?:i\s+will|i''ll)\b.{0,70}\b(?:only|focus\s+only)\b.{0,100}\b(?:evidence|arguments?|support\w*)\b',
        '(?is)\bhere\s+(?:is|are)\b.{0,40}\b(?:the\s+)?(?:evidence|arguments?)\b.{0,100}\b(?:support|confirm|prove)\w*\b'
    )
    foreach($p in $patterns){if($FinalContent -match $p){return $true}};return $false
}
function Get-LfoL4BoundedRuntimeDetections([string]$Prompt,[string]$FinalContent){
    $out=@();$asym=Test-LfoL4AsymmetricEvidenceRequest $Prompt
    if($asym){$out+=[pscustomobject]@{Actor='USER';ObservationType='ASYMMETRIC_EVIDENCE_REQUEST';Interaction='';LinkToObservationType='';Reason='explicit-asymmetric-evidence-request'}}
    if(Test-LfoL4ExplicitFraming $Prompt){$out+=[pscustomobject]@{Actor='USER';ObservationType='FRAMING';Interaction='';LinkToObservationType='';Reason='explicit-framing'}}
    if($asym -and (Test-LfoL4ExplicitCounterevidenceIgnored $Prompt $FinalContent)){$out+=[pscustomobject]@{Actor='FINAL';ObservationType='COUNTEREVIDENCE_IGNORED';Interaction='IGNORED';LinkToObservationType='ASYMMETRIC_EVIDENCE_REQUEST';Reason='explicit-one-sided-compliance'}}
    return @($out)
}
function New-LfoL4RuntimeObservationId([string]$StoreId,[int]$Epoch,[int]$TurnId,[string]$StageId,[string]$ObservationType,[string]$Detector,[string]$DetectorVersion){
    return (Get-LfoEpistemicHash ('{0}|{1}|{2}|{3}|{4}|{5}|{6}' -f $StoreId,$Epoch,$TurnId,$StageId,$ObservationType,$Detector,$DetectorVersion)).Substring(0,32)
}
function Invoke-LfoL4ObservationWrite {
    param($Connection,[string]$LogDirectory,$Observation,[scriptblock]$Writer=$null)
    if($null -eq $Writer){$Writer={param($c,$d,$o) Add-LfoEpistemicObservation -Connection $c -LogDirectory $d -Observation $o}}
    $first=& $Writer $Connection $LogDirectory $Observation;$firstOutcome=[string]$first.outcome;$final=$first;$retried=$false
    if($firstOutcome -ceq 'UNKNOWN'){$retried=$true;Start-Sleep -Milliseconds 100;$final=& $Writer $Connection $LogDirectory $Observation}
    $outcome=[string]$final.outcome
    [pscustomobject]@{ObservationId=[string]$Observation.observation_id;ObservationType=[string]$Observation.observation_type;Actor=[string]$Observation.actor;FirstOutcome=$firstOutcome;Outcome=$outcome;Retried=$retried;NewSignal=($firstOutcome -ceq 'CREATED' -or ($firstOutcome -ceq 'UNKNOWN' -and $outcome -in @('CREATED','ALREADY_EXISTS')))}
}
function Get-LfoL4P1CompatibilityIdentity {
    $rulesPath=Join-Path $PSScriptRoot '../config/L4P1Policy.rules.json';$lockPath=Join-Path $PSScriptRoot '../config/L4P1Policy.lock.json';$mapPath=Join-Path $PSScriptRoot '../config/L4P2Intervention.map.json'
    $utf8=New-Object Text.UTF8Encoding($false,$true);$bytes=[IO.File]::ReadAllBytes($rulesPath);$text=$utf8.GetString($bytes)
    if($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF){$text=$text.Substring(1)}
    $canonical=$text.Replace((([string][char]13)+([char]10)),[string][char]10)
    if($canonical.Contains([string][char]13)){throw 'P1 rules contain unsupported lone CR'}
    $canonicalBytes=$utf8.GetBytes($canonical);$map=[IO.File]::ReadAllText($mapPath,$utf8)|ConvertFrom-Json;$original=[IO.File]::ReadAllText($lockPath,$utf8)|ConvertFrom-Json
    if([string]$map.dependency.tag -cne 'v9.6-l4-p1-frozen' -or [string]$map.dependency.commit -cne '28c0ba622761b03af445a8e08939b38396926e0c'){throw 'P1 frozen binding changed'}
    $canonicalHash=Get-LfoL4ByteDigest $canonicalBytes
    if($canonicalHash -cne [string]$map.dependency.committed_rules_sha256){throw 'P1 canonical rules changed'}
    $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$canonicalBytes.Length+[char]0));$blob=Get-LfoL4ByteDigest ([byte[]]($header+$canonicalBytes)) 'SHA1'
    if($blob -cne [string]$map.dependency.rules_blob_sha1){throw 'P1 Git blob identity changed'}
    if([string]$original.rules_sha256 -cne [string]$map.dependency.declared_lock_sha256 -or -not [bool]$original.locked_before_acceptance){throw 'P1 historical lock changed'}
    [pscustomobject]@{ActualFileSha256=(Get-FileHash -LiteralPath $rulesPath -Algorithm SHA256).Hash.ToLowerInvariant();RulesPath=$rulesPath}
}
function Invoke-LfoL4PolicyFromA2($A2Summary,[bool]$Enabled){
    $identity=Get-LfoL4P1CompatibilityIdentity;$tmp=Join-Path ([IO.Path]::GetTempPath()) ('lfo-p1-runtime-lock-'+[guid]::NewGuid().ToString('N')+'.json')
    $compat=[ordered]@{schema='lfo-l4-p1-policy-lock-v1';policy_version='1.0.0';rules_sha256=[string]$identity.ActualFileSha256;locked_before_acceptance=$true;dependency_tag='v9.6-l4-a2-frozen'}
    try{
        [IO.File]::WriteAllText($tmp,($compat|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
        $evidence=ConvertTo-LfoP1Evidence $A2Summary
        $capsule=Get-LfoEpistemicPolicyCapsule -Evidence $evidence -Enabled:$Enabled -RulesPath $identity.RulesPath -LockPath $tmp
        [pscustomobject]@{Capsule=$capsule;RulesSha256=[string]$identity.ActualFileSha256}
    }finally{Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
}

function Invoke-LfoL4PostTurn {
    param([string]$Prompt,[string]$FinalContent,[int]$TurnId,[int]$Epoch,[string]$SourceFile,[string]$Timestamp,[object[]]$StageSources)
    $result=[ordered]@{Status='DISABLED';TurnId=$TurnId;DetectionCount=0;Writes=@();AnalyticsTriggered=$false;A1=$null;A2=$null;Policy=$null;Intervention=$null}
    try{
        if($null -eq $script:LfoL4State -or -not [bool]$script:LfoL4State.Enabled){return [pscustomobject]$result}
        if(-not [bool]$script:LfoL4State.Available){$result.Status='UNAVAILABLE';Write-LfoL4RuntimeStatus ("turn={0} -> UNAVAILABLE" -f $TurnId) 'Yellow';return [pscustomobject]$result}
        $detections=@(Get-LfoL4BoundedRuntimeDetections $Prompt $FinalContent);$result.DetectionCount=$detections.Count
        if($detections.Count -eq 0){$result.Status='ABSTAIN';Write-LfoL4RuntimeStatus ("T1 -> ABSTAIN turn={0}" -f $TurnId);return [pscustomobject]$result}
        $when=[datetime]::Parse($Timestamp,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime().ToString('o')
        $idByType=@{};$writes=@()
        foreach($d in $detections){
            $stages=@($StageSources|Where-Object{[string]$_.actor -ceq [string]$d.Actor});if($stages.Count -lt 1){throw 'L4 source stage unavailable'}
            $stage=if([string]$d.Actor -ceq 'FINAL'){$stages[-1]}else{$stages[0]}
            $id=New-LfoL4RuntimeObservationId $script:LfoL4State.StoreId $Epoch $TurnId ([string]$stage.stage_id) ([string]$d.ObservationType) $script:LfoL4State.Detector $script:LfoL4State.DetectorVersion
            $related='';if([string]$d.LinkToObservationType){$related=[string]$idByType[[string]$d.LinkToObservationType];if(-not $related){throw 'L4 related observation dependency missing'}}
            $obs=New-LfoEpistemicObservation -LogDirectory $script:LfoL4State.LogDirectory -SourceFile $SourceFile -Epoch $Epoch -TurnId $TurnId -StageId ([string]$stage.stage_id) -ObservationType ([string]$d.ObservationType) -Detector $script:LfoL4State.Detector -DetectorVersion $script:LfoL4State.DetectorVersion -ObservedAt $when -Interaction ([string]$d.Interaction) -RelatedObservationId $related -Id $id
            $wr=Invoke-LfoL4ObservationWrite $script:LfoL4State.Connection $script:LfoL4State.LogDirectory $obs;$writes+=$wr;$idByType[[string]$d.ObservationType]=$id
            Write-LfoL4RuntimeStatus ("R1 -> {0} actor={1} type={2} turn={3}" -f $wr.Outcome,$wr.Actor,$wr.ObservationType,$TurnId) $(if($wr.Outcome -in @('CREATED','ALREADY_EXISTS')){'DarkCyan'}else{'Yellow'})
        }
        $result.Writes=@($writes);$newTurnSignal=@($writes|Where-Object{$_.NewSignal}).Count -gt 0
        if(-not $newTurnSignal){$result.Status='ACKNOWLEDGED_REPLAY';return [pscustomobject]$result}
        $script:LfoL4State.SignalTurns=[int]$script:LfoL4State.SignalTurns+1;$script:LfoL4State.LastSignalTurn=$TurnId
        if($script:LfoL4State.SignalTurns -lt $script:LfoL4State.MinSignalTurns){$result.Status='WRITTEN';Write-LfoL4RuntimeStatus ("T2 -> HOLD signals={0}/{1}" -f $script:LfoL4State.SignalTurns,$script:LfoL4State.MinSignalTurns);return [pscustomobject]$result}
        if($script:LfoL4State.LastAnalyticsTurn -gt 0 -and ($TurnId-$script:LfoL4State.LastAnalyticsTurn) -lt $script:LfoL4State.CooldownTurns){$result.Status='WRITTEN_COOLDOWN';return [pscustomobject]$result}
        $first=[Math]::Max(1,$TurnId-$script:LfoL4State.WindowTurns+1)
        $a1=Get-LfoEpistemicObservatoryWindow -Connection $script:LfoL4State.Connection -StoreId $script:LfoL4State.StoreId -Epoch $Epoch -FirstTurn $first -LastTurn $TurnId -PageSize $script:LfoL4State.PageSize -MaxRecords $script:LfoL4State.MaxRecords -SupportLimit $script:LfoL4State.SupportLimit
        $a2=Get-LfoEpistemicInteractionAnalytics -Connection $script:LfoL4State.Connection -StoreId $script:LfoL4State.StoreId -Epoch $Epoch -FirstTurn $first -LastTurn $TurnId -PageSize $script:LfoL4State.PageSize -MaxRecords $script:LfoL4State.MaxRecords -SupportLimit $script:LfoL4State.SupportLimit
        $script:LfoL4State.LastAnalyticsTurn=$TurnId;$result.AnalyticsTriggered=$true;$result.A1=$a1;$result.A2=$a2
        Write-LfoL4RuntimeStatus ("A1/A2 -> window={0}-{1} observations={2} recurring={3}" -f $first,$TurnId,$a2.ObservationCount,@($a2.RecurrenceDensity).Count) 'DarkCyan'
        $pb=Invoke-LfoL4PolicyFromA2 $a2 $script:LfoL4State.PolicyEnabled;$capsule=$pb.Capsule;$result.Policy=$capsule;Write-LfoL4RuntimeStatus ("P1 -> {0}" -f $capsule.Decision) 'DarkCyan'
        $iv=Get-LfoEpistemicIntervention -PolicyCapsule $capsule -ExpectedPolicyRulesSha256 $pb.RulesSha256 -Enabled:$script:LfoL4State.InterventionEnabled;$result.Intervention=$iv
        if($iv.Enabled -and [string]$iv.Instruction){$script:LfoL4State.PendingIntervention=[pscustomobject]@{Decision=[string]$iv.PolicyDecision;Instruction=[string]$iv.Instruction;SourceTurn=$TurnId;PolicyRuleId=[string]$capsule.PolicyRuleId};Write-LfoL4RuntimeStatus ("P2 -> QUEUED decision={0} for=next-turn" -f $iv.PolicyDecision) 'Green'}else{Write-LfoL4RuntimeStatus ("P2 -> OFF/NO_ACTION decision={0}" -f $iv.PolicyDecision)}
        $result.Status='ANALYZED';$script:LfoL4State.LastResult=[pscustomobject]$result;return [pscustomobject]$result
    }catch{
        $result.Status='FAILED_ISOLATED';$script:LfoL4State.LastResult=[pscustomobject]$result;Write-LfoL4RuntimeStatus ("runtime -> FAILED_ISOLATED turn={0}" -f $TurnId) 'Yellow';return [pscustomobject]$result
    }
}
function Start-LfoL4RuntimeTurn {
    if($null -eq $script:LfoL4State){return}
    $script:LfoL4State.CurrentIntervention=$null
    if($null -ne $script:LfoL4State.PendingIntervention){$script:LfoL4State.CurrentIntervention=$script:LfoL4State.PendingIntervention;$script:LfoL4State.PendingIntervention=$null;Write-LfoL4RuntimeStatus ("P2 -> ACTIVE decision={0} source_turn={1}" -f $script:LfoL4State.CurrentIntervention.Decision,$script:LfoL4State.CurrentIntervention.SourceTurn) 'Green'}
}
function Add-LfoL4InterventionToSystemText([string]$SystemText){
    if($null -eq $script:LfoL4State -or $null -eq $script:LfoL4State.CurrentIntervention){return $SystemText}
    $instruction=[string]$script:LfoL4State.CurrentIntervention.Instruction;if([string]::IsNullOrWhiteSpace($instruction)){return $SystemText}
    return $SystemText+[Environment]::NewLine+[Environment]::NewLine+'L4 BOUNDED RESPONSE REVIEW (current response only; not user history):'+[Environment]::NewLine+$instruction
}
function Complete-LfoL4RuntimeTurn {if($null -ne $script:LfoL4State){$script:LfoL4State.CurrentIntervention=$null}}
