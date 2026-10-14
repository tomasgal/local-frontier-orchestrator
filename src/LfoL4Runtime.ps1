# Gate 1: shared I1 integration over frozen R1/A1/A2/P1/P2.
# Loading defines functions only. No fixtures, detector, model or ordinary-chat hook.
foreach ($l4Module in @('LfoEpistemicStore','LfoEpistemicObservatory','LfoEpistemicInteractionAnalytics','LfoEpistemicPolicyCapsule','LfoEpistemicIntervention')) {
    . (Join-Path $PSScriptRoot ($l4Module+'.ps1'))
}

function New-LfoL4RuntimePolicyBinding {
    param([Parameter(Mandatory)][string]$WorkDirectory)
    # I1's external compatibility lock; never rewrite the frozen rules/lock.
    $rules=Join-Path $PSScriptRoot '../config/L4P1Policy.rules.json'
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $text=$utf8.GetString([IO.File]::ReadAllBytes($rules))
    if($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF){$text=$text.Substring(1)}
    $canonical=$text.Replace("`r`n","`n")
    $canonicalHash=Get-LfoP2Digest ($utf8.GetBytes($canonical))
    if($canonicalHash -cne 'a5da19563afcb4ac9698acce7aff423daf9b3e400cfe5af40f3a46aea4fe0106'){throw 'P1 differs from I1 canonical rules.'}
    $p1hash=(Get-FileHash -LiteralPath $rules -Algorithm SHA256).Hash.ToLowerInvariant()
    $compat=[ordered]@{schema='lfo-l4-i1-p1-binding-v1';frozen_tag='v9.6-l4-p1-frozen';frozen_commit='28c0ba622761b03af445a8e08939b38396926e0c';git_blob='e29a1d5f346786e3e2afbf70e3f14b898fcf29ee';canonical_sha256=$canonicalHash;historical_declared_sha256='d837c9b6d62e387c6482b83449495d5dc5c4d2092976ef459892bceabe2ee7c3';scope='External compatibility binding; historical lock and frozen source unmodified.'}
    $lock=Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot '../config/L4P1Policy.lock.json')|ConvertFrom-Json
    if($lock.rules_sha256 -cne $compat.historical_declared_sha256){throw 'P1 historical lock changed.'}
    $lock.rules_sha256=$p1hash
    $compatLock=Join-Path $WorkDirectory ('p1-runtime-'+[guid]::NewGuid().ToString('N')+'.lock.json')
    $identity=Get-LfoP2MapIntegrity -MapPath (Join-Path $PSScriptRoot '../config/L4P2Intervention.map.json') -LockPath (Join-Path $PSScriptRoot '../config/L4P2Intervention.lock.json')
    [IO.File]::WriteAllText($compatLock,($lock|ConvertTo-Json -Depth 10)+"`n",$utf8)
    [pscustomobject]@{RulesPath=$rules;LockPath=$compatLock;RulesSha256=$p1hash;P1Binding=$compat;P2Integrity=$identity}
}

function Get-LfoL4RuntimeWindow {
    param(
        [Parameter(Mandatory)]$Connection,
        [Parameter(Mandatory)][string]$StoreId,
        [Parameter(Mandatory)][int]$Epoch,
        [Parameter(Mandatory)][int]$FirstTurn,
        [Parameter(Mandatory)][int]$LastTurn,
        [ValidateRange(1,200)][int]$PageSize=100,
        [ValidateRange(1,100000)][int]$MaxRecords=200,
        [ValidateRange(1,50)][int]$SupportLimit=50
    )
    # Frozen A1/A2 each scan a capped epoch before selecting the turn window.
    # Called on explicit /analyze only; no automatic T2 scheduling.
    $a=@{Connection=$Connection;StoreId=$StoreId;Epoch=$Epoch;FirstTurn=$FirstTurn;LastTurn=$LastTurn;PageSize=$PageSize;MaxRecords=$MaxRecords;SupportLimit=$SupportLimit}
    $a1=Get-LfoEpistemicObservatoryWindow @a
    $a2=Get-LfoEpistemicInteractionAnalytics @a
    [pscustomobject]@{A1=$a1;A2=$a2}
}

# Ordinary runtime: writes after L0; analytics only by explicit command.
function Initialize-LfoL4Recording {
    param([string]$LogDirectory,[bool]$ProvenanceEnabled,[hashtable]$Settings=@{})
    $ErrorActionPreference='Stop'
    $script:LfoL4Recording=[pscustomobject]@{Status='DISABLED';Connection=$null;LogDirectory=$LogDirectory;StoreId=''}
    try {
        $enabled=[bool]$Settings.Enabled
        if($env:LFO_L4_ENABLED){$enabled=$env:LFO_L4_ENABLED -in @('1','true','on')}
        if(-not $enabled){return $script:LfoL4Recording}
        if(-not $ProvenanceEnabled){throw 'Enable Memory and Memory.L0StageSourcesEnabled.'}
        $endpoint=[string]$Settings.Endpoint
        $credentialPath=[string]$Settings.CredentialPath
        if($env:LFO_L4_ENDPOINT){$endpoint=$env:LFO_L4_ENDPOINT}
        if($env:LFO_L4_RUNTIME_CREDENTIAL){$credentialPath=$env:LFO_L4_RUNTIME_CREDENTIAL}
        if(-not $endpoint -or -not $credentialPath){throw 'Configure L4.Endpoint and L4.CredentialPath (or LFO_L4 environment variables).'}
        $credential=Import-Clixml -LiteralPath $credentialPath
        $script:LfoL4Recording.Connection=New-LfoEpistemicConnection -Endpoint $endpoint -Credential $credential -TimeoutSec 3
        $script:LfoL4Recording.StoreId=Register-LfoEpistemicL0Store $LogDirectory
        # Connection is validated on use. No bootstrap, credentials or schema creation.
        $script:LfoL4Recording.Status='CONFIGURED'
    } catch {
        $script:LfoL4Recording.Status='UNAVAILABLE'
        Write-Host ('[L4 UNAVAILABLE: '+$_.Exception.Message+']') -ForegroundColor Yellow
    }
    return $script:LfoL4Recording
}

function Get-LfoL4TurnObservationType {
    param([AllowEmptyString()][string]$Text)
    # Bounded whole-input matching, not truncation; no model or D1 calls.
    if([string]::IsNullOrWhiteSpace($Text) -or $Text.Length -gt 2048){return 'ABSTAIN'}
    $builder=New-Object Text.StringBuilder
    foreach($ch in $Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray()){
        if([Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch) -ne [Globalization.UnicodeCategory]::NonSpacingMark){[void]$builder.Append($ch)}
    }
    $t=$builder.ToString().ToLowerInvariant().Trim()
    # Quotes, questions, negation, hypotheticals and metalinguistic contexts abstain.
    if($t -match '["\x27\x60\r\n?\u2018-\u201F\u00AB\u00BB]' -or
       $t -match '\b(?:not|never|dont|do\s+not|if|unless|hypothet\w*|example\w*|quot\w*|translat\w*|ak|keby|hypote\w*|priklad\w*|cit\w*|preloz\w*|nie|nechcem|neber|nepovazuj)\b'){return 'ABSTAIN'}
    if($t -match '^(?:please\s+)?(?:give\s+me|show\s+me|find|provide)\s+only\s+(?:evidence|arguments)\s+(?:that\s+)?(?:support\w*|confirm\w*|prov\w*)\s+(?:my\s+(?:view|position|opinion)|i\s+am\s+right)\s*[.!]?$' -or
       $t -match '^(?:prosim\s+)?(?:daj\s+mi|ukaz\s+mi|najdi|uved|chcem)\s+(?:len|iba)\s+(?:dokazy|argumenty)\s+(?:(?:ktore\s+)?(?:podpor\w*|potvrd\w*)\s+(?:moj\w*\s+(?:nazor|stanovisko|tvrdenie)|ze\s+mam\s+pravdu)|ze\s+mam\s+pravdu)\s*[.!]?$'){return 'ASYMMETRIC_EVIDENCE_REQUEST'}
    if($t -match '^(?:please\s+)?(?:treat|take|accept)\s+[^.!?;]{1,160}\s+as\s+(?:a\s+fact|established|proven)\s*[.!]?$' -or
       $t -match '^(?:prosim\s+)?(?:ber|povazuj|pokladaj)\s+(?:[^.!?;]{1,160}\s+)?(?:za|ako)\s+(?:fakt|preukazane|dokazane)(?:\s*,?\s+ze\s+[^.!?;]{1,160})?\s*[.!]?$'){return 'FRAMING'}
    return 'ABSTAIN'
}

function Invoke-LfoL4RecordTurn {
    param($Row,[string]$SourceFile)
    $ErrorActionPreference='Stop'
    try {
        $state=$script:LfoL4Recording
        if($null -eq $state -or $state.Status -cne 'CONFIGURED'){return [pscustomobject]@{Status='DISABLED_OR_UNAVAILABLE'}}
        $kind=Get-LfoL4TurnObservationType ([string]$Row.user)
        if($kind -ceq 'ABSTAIN'){return [pscustomobject]@{Status='ABSTAIN'}}
        if($Row.stage_sources_schema -ne 1 -or $Row.epoch -lt 1 -or $Row.turn_id -lt 1){throw 'L0 provenance missing.'}
        $stages=@($Row.stage_sources|Where-Object{$_.actor -ceq 'USER' -and $_.source_field -ceq 'user'})
        if($stages.Count -ne 1){throw 'L0 USER stage missing or ambiguous.'}
        $stage=$stages[0]
        $when=[datetime]::Parse($Row.timestamp,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime().ToString('o')
        $id=(Get-LfoEpistemicHash ("t1-v1|{0}|{1}|{2}|{3}|{4}|{5}" -f $state.StoreId,$SourceFile,$Row.epoch,$Row.turn_id,$stage.stage_id,$kind)).Substring(0,32)
        $obs=New-LfoEpistemicObservation -LogDirectory $state.LogDirectory -SourceFile $SourceFile -Epoch $Row.epoch -TurnId $Row.turn_id -StageId $stage.stage_id -ObservationType $kind -Detector 'l4.runtime.t1' -DetectorVersion '1.0.0' -ObservedAt $when -Id $id
        # Classify the exact persisted source; never accept a mismatched callback row.
        if($obs.source.content_sha256 -cne (Get-LfoEpistemicHash ([string]$Row.user))){throw 'L0 content differs from classified turn.'}
        $write=Add-LfoEpistemicObservation -Connection $state.Connection -LogDirectory $state.LogDirectory -Observation $obs
        return [pscustomobject]@{Status=[string]$write.outcome;ObservationId=$id;ObservationType=$kind}
    } catch {
        return [pscustomobject]@{Status='FAILED_ISOLATED'}
    }
}

function Invoke-LfoL4AnalyzeCommand {
    param([string]$Command,[int]$Epoch,[int]$LastTurn)
    $ErrorActionPreference='Stop'
    try {
        if($Command.Trim() -notmatch '^/analyze(?:\s+([0-9]{1,3}))?$'){Write-Host 'Usage: /analyze [1..100 turns]';return}
        $turns=8
        if($Matches[1]){$turns=[int]$Matches[1]}
        if($turns -lt 1 -or $turns -gt 100){Write-Host 'Usage: /analyze [1..100 turns]';return}
        $state=$script:LfoL4Recording
        if($null -eq $state -or $state.Status -cne 'CONFIGURED'){Write-Host '[L4 analysis unavailable: enable/configure L4 recording.]';return}
        if($LastTurn -lt 1){Write-Host '[L4: no completed turns in this conversation.]';return}
        $first=[Math]::Max(1,$LastTurn-$turns+1)
        $window=Get-LfoL4RuntimeWindow -Connection $state.Connection -StoreId $state.StoreId -Epoch $Epoch -FirstTurn $first -LastTurn $LastTurn -PageSize 50 -MaxRecords 200 -SupportLimit 12
        Write-Host ("L4 observations: {0}; annotated turns: {1}; epoch {2}, turns {3}-{4}" -f $window.A1.ObservationCount,$window.A1.DistinctAnnotatedTurnCount,$Epoch,$first,$LastTurn)
        Write-Host 'Reported signals only; ABSTAIN is not evidence of an unbiased turn. P2 OFF.'
        foreach($row in $window.A1.CountsByObservationType){Write-Host ("  {0}: {1}" -f $row.name,$row.count)}
        foreach($row in $window.A2.RecurrenceDensity){Write-Host ("  {0}: occurrences={1}, turns={2}" -f $row.signature,$row.occurrence_count,$row.distinct_turn_count)}
        $ids=@($window.A2.SupportingObservationIds)
        if($ids.Count){
            Write-Host 'L0 references (up to 12 observations):'
            foreach($ref in @(Get-LfoEpistemicObservatoryProvenance -Connection $state.Connection -StoreId $state.StoreId -Epoch $Epoch -ObservationId $ids -Limit 12)){
                Write-Host ("  {0} -> {1}, T{2}/{3}; sha256={4}" -f $ref.observation_id,$ref.file,$ref.turn_id,$ref.stage_id,$ref.content_sha256)
            }
        }
    } catch {
        Write-Host '[L4 analysis unavailable or record cap exceeded (200 per epoch); chat continues.]' -ForegroundColor Yellow
    }
}

function Get-LfoL4RuntimeResponse {
    param(
        [Parameter(Mandatory)]$A2Summary,
        [Parameter(Mandatory)]$PolicyBinding,
        [switch]$PolicyEnabled,
        [switch]$InterventionEnabled
    )
    # Separate from store I/O for future pre-response use of prior-turn state.
    # P1 receives only frozen bounded evidence, never raw observations.
    $ErrorActionPreference='Stop'
    try {
        $e=ConvertTo-LfoP1Evidence $A2Summary
        $policyArgs=@{RulesPath=$PolicyBinding.RulesPath;LockPath=$PolicyBinding.LockPath}
        $p=Get-LfoEpistemicPolicyCapsule -Evidence $e -Enabled:$PolicyEnabled @policyArgs
        $iv=Get-LfoEpistemicIntervention -PolicyCapsule $p -ExpectedPolicyRulesSha256 $PolicyBinding.RulesSha256 -Enabled:$InterventionEnabled
        [pscustomobject]@{Status='READY';Evidence=$e;Policy=$p;Intervention=$iv;Error=$null}
    } catch {
        [pscustomobject]@{Status='FAILED_ISOLATED';Evidence=$null;Policy=$null;Intervention=$null;Error=$_.Exception.Message}
    }
}

function Invoke-LfoL4RuntimeCycle {
    param(
        [Parameter(Mandatory)]$Connection,
        [Parameter(Mandatory)][string]$StoreId,
        [Parameter(Mandatory)][int]$Epoch,
        [Parameter(Mandatory)][int]$FirstTurn,
        [Parameter(Mandatory)][int]$LastTurn,
        [Parameter(Mandatory)]$PolicyBinding,
        [ValidateRange(1,200)][int]$PageSize=100,
        [ValidateRange(1,100000)][int]$MaxRecords=200,
        [ValidateRange(1,50)][int]$SupportLimit=50,
        [switch]$PolicyEnabled,
        [switch]$InterventionEnabled
    )
    $ErrorActionPreference='Stop'
    try {
        $window=Get-LfoL4RuntimeWindow -Connection $Connection -StoreId $StoreId -Epoch $Epoch -FirstTurn $FirstTurn -LastTurn $LastTurn -PageSize $PageSize -MaxRecords $MaxRecords -SupportLimit $SupportLimit
        $response=Get-LfoL4RuntimeResponse -A2Summary $window.A2 -PolicyBinding $PolicyBinding -PolicyEnabled:$PolicyEnabled -InterventionEnabled:$InterventionEnabled
        if($response.Status -cne 'READY'){throw $response.Error}
        [pscustomobject]@{Status='READY';A1=$window.A1;A2=$window.A2;Evidence=$response.Evidence;Policy=$response.Policy;Intervention=$response.Intervention;Error=$null}
    } catch {
        [pscustomobject]@{Status='FAILED_ISOLATED';A1=$null;A2=$null;Evidence=$null;Policy=$null;Intervention=$null;Error=$_.Exception.Message}
    }
}
