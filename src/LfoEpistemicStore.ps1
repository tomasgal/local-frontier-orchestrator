# L4-R1. Explicit, opt-in API; loading this file performs no I/O.
function Get-LfoEpistemicHash {
    param([AllowEmptyString()][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Register-LfoEpistemicL0Store {
    param([Parameter(Mandatory)][string]$LogDirectory)
    # Explicit registration only. Never infers a production memory directory.
    $dir = Get-Item -LiteralPath $LogDirectory -ErrorAction Stop
    if (-not $dir.PSIsContainer -or ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'L0 directory must be a physical directory.' }
    $path = Join-Path $dir.FullName 'l4-source-identity.json'
    if (-not (Test-Path -LiteralPath $path)) {
        $value = [ordered]@{schema_version=1;store_id=[guid]::NewGuid().ToString('N')}
        $bytes = [Text.Encoding]::UTF8.GetBytes(($value | ConvertTo-Json -Compress))
        $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    }
    return (Get-LfoEpistemicL0Identity $dir.FullName)
}

function Get-LfoEpistemicL0Identity {
    param([string]$LogDirectory)
    $path = Join-Path $LogDirectory 'l4-source-identity.json'
    $file = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Identity symlinks are not supported.' }
    $identity = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
    if ($identity.schema_version -ne 1 -or $identity.store_id -cnotmatch '^[a-f0-9]{32}$') { throw 'Invalid L0 identity.' }
    return [string]$identity.store_id
}

function Resolve-LfoEpistemicSource {
    param([Parameter(Mandatory)][string]$LogDirectory, [Parameter(Mandatory)]$Source)
    if ($Source.store_id -cne (Get-LfoEpistemicL0Identity $LogDirectory)) { throw 'L0 store identity mismatch.' }
    if ($Source.file -cnotmatch '^conversation-[0-9]{4}-[0-9]{2}\.jsonl$' -or $Source.epoch -lt 1 -or $Source.turn_id -lt 1 -or $Source.stage_id -cnotmatch '^s[1-9][0-9]*$') { throw 'Invalid L0 locator.' }
    $file = Get-Item -LiteralPath (Join-Path $LogDirectory $Source.file) -ErrorAction Stop
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source symlinks are not supported.' }
    $match = $null
    # Inspect an explicit monthly file; do not read unrelated stores or epochs.
    $reader = New-Object IO.StreamReader($file.FullName, (New-Object Text.UTF8Encoding($false,$true)))
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $row = $line | ConvertFrom-Json -ErrorAction Stop
            if ($row.event -eq 'turn' -and $row.epoch -eq $Source.epoch -and $row.turn_id -eq $Source.turn_id) {
                if ($null -ne $match) { throw 'Ambiguous L0 turn identity.' }
                $match = $row
            }
        }
    } finally { $reader.Dispose() }
    if ($null -eq $match -or $match.stage_sources_schema -ne 1) { throw 'L0 turn/stage provenance unavailable.' }
    $stages = @($match.stage_sources | Where-Object { $_.stage_id -ceq $Source.stage_id })
    if ($stages.Count -ne 1) { throw 'L0 stage missing or ambiguous.' }
    $s = $stages[0]
    if ($s.source_field) {
        if (($s.actor -ceq 'USER' -and $s.source_field -ceq 'user') -or ($s.actor -ceq 'FINAL' -and $s.source_field -ceq 'assistant')) { $content = [string]$match.($s.source_field) }
        else { throw 'Invalid source field mapping.' }
    } else {
        if ($s.actor -notin @('LOCAL','FRONTIER') -or $null -eq $s.content) { throw 'Missing stage content.' }
        $content = [string]$s.content
    }
    $hash = Get-LfoEpistemicHash $content
    if ($Source.content_sha256 -and $Source.content_sha256 -cne $hash) { throw 'L0 content hash mismatch.' }
    return [pscustomobject]@{Content=$content;ContentSHA256=$hash;Stage=$s}
}

function New-LfoEpistemicObservation {
    param(
        [Parameter(Mandatory)][string]$LogDirectory,
        [Parameter(Mandatory)][string]$SourceFile,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Epoch,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$TurnId,
        [Parameter(Mandatory)][ValidatePattern('^s[1-9][0-9]*$')][string]$StageId,
        [Parameter(Mandatory)][ValidateSet('FRAMING','PRESUPPOSITION','ASYMMETRIC_EVIDENCE_REQUEST','BIAS_CANDIDATE','OVERCONFIDENCE','UNCERTAINTY_SUPPRESSION','SYCOPHANTIC_REINFORCEMENT','COUNTEREVIDENCE_IGNORED','COUNTEREVIDENCE_INTRODUCED','BIAS_REINFORCED','BIAS_CHALLENGED','EPISTEMIC_RISK_SIGNAL')][string]$ObservationType,
        [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9._-]{1,80}$')][string]$Detector,
        [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9._-]{1,40}$')][string]$DetectorVersion,
        [Nullable[double]]$Confidence = $null,
        [ValidateLength(0,512)][string]$Excerpt = '',
        [ValidateSet('','INTRODUCED','REINFORCED','IGNORED','CHALLENGED','CORRECTED')][string]$Interaction = '',
        [ValidatePattern('^([a-f0-9]{32})?$')][string]$RelatedObservationId = '',
        [ValidatePattern('^[a-f0-9]{32}$')][string]$Id = ([guid]::NewGuid().ToString('N')),
        [string]$ObservedAt = ([DateTime]::UtcNow.ToString('o'))
    )
    if ($null -ne $Confidence -and ([double]::IsNaN($Confidence) -or [double]::IsInfinity($Confidence) -or $Confidence -lt 0 -or $Confidence -gt 1)) { throw 'Confidence must be unknown or in [0,1].' }
    if ($ObservedAt -notmatch 'Z$') { throw 'ObservedAt must be UTC with Z suffix.' }
    $when = [datetime]::Parse($ObservedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime().ToString('o')
    if ($RelatedObservationId -and (-not $Interaction -or $RelatedObservationId -ceq $Id)) { throw 'Related observation requires interaction and a distinct ID.' }
    $source = [ordered]@{store_id=(Get-LfoEpistemicL0Identity $LogDirectory);file=$SourceFile;epoch=$Epoch;turn_id=$TurnId;stage_id=$StageId}
    $resolved = Resolve-LfoEpistemicSource $LogDirectory $source
    if ($Excerpt -and -not $resolved.Content.Contains($Excerpt)) { throw 'Excerpt is not an exact substring of L0.' }
    $s = $resolved.Stage
    $mapping = @{USER='INPUT';LOCAL='LOCAL_RESPONSE';FRONTIER='FRONTIER_RESPONSE';FINAL='FINAL_RESPONSE'}
    if (-not $mapping.ContainsKey([string]$s.actor) -or $mapping[$s.actor] -cne $s.stage -or $s.producer -notin @('USER','LOCAL','FRONTIER','WRAPPER')) { throw 'Invalid actor/stage/producer provenance.' }
    $source.content_sha256 = $resolved.ContentSHA256
    return [pscustomobject][ordered]@{
        observation_id=$Id;schema_version=1;taxonomy_version=1;observed_at=$when
        source=$source;actor=[string]$s.actor;stage=[string]$s.stage;producer=[string]$s.producer
        phase=[string]$s.phase;source_status=[string]$s.status;model=$s.model
        observation_type=$ObservationType.ToUpperInvariant();confidence=$Confidence
        detector=$Detector;detector_version=$DetectorVersion;status='REPORTED'
        excerpt=$Excerpt;interaction=$Interaction.ToUpperInvariant();related_observation_id=$RelatedObservationId
    }
}

function New-LfoEpistemicConnection {
    param([Parameter(Mandatory)][string]$Endpoint, [Parameter(Mandatory)][pscredential]$Credential,
        [ValidateRange(1,30)][int]$TimeoutSec=5, [switch]$Bootstrap)
    $uri = [uri]$Endpoint
    if ($uri.Scheme -cne 'http' -or $uri.Host -cne '127.0.0.1' -or $uri.AbsolutePath -ne '/' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) { throw 'R1 requires an explicit http://127.0.0.1:port endpoint.' }
    return [pscustomobject]@{Endpoint=$Endpoint.TrimEnd('/');Credential=$Credential;TimeoutSec=$TimeoutSec;Bootstrap=[bool]$Bootstrap;Namespace='lfo';Database='epistemic'}
}

function Invoke-LfoEpistemicQuery {
    # Internal transport. Never pass model-generated SQL here.
    param($Connection,[string]$Sql,[hashtable]$Variables=@{})
    $pair = $Connection.Credential.UserName + ':' + $Connection.Credential.GetNetworkCredential().Password
    $headers = @{Authorization=('Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair)));Accept='application/json';'Surreal-NS'=$Connection.Namespace;'Surreal-DB'=$Connection.Database}
    if (-not $Connection.Bootstrap) { $headers['Surreal-Auth-NS']='lfo';$headers['Surreal-Auth-DB']='epistemic' }
    $json = @{id=1;method='query';params=@($Sql,$Variables)} | ConvertTo-Json -Depth 20 -Compress
    $body = [Text.Encoding]::UTF8.GetBytes($json)
    # JSON on the wire is UTF-8. Windows PowerShell 5.1 can guess another
    # encoding when the response Content-Type omits charset. Decode raw bytes
    # explicitly instead of using the already-decoded Content property.
    $http = Invoke-WebRequest -UseBasicParsing -Method Post -Uri ($Connection.Endpoint+'/rpc') -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec $Connection.TimeoutSec -ErrorAction Stop
    $buffer = New-Object IO.MemoryStream
    try {
        $stream = $http.RawContentStream
        if ($stream.CanSeek) { $stream.Position = 0 }
        $stream.CopyTo($buffer)
        $utf8 = New-Object Text.UTF8Encoding($false,$true)
        $response = $utf8.GetString($buffer.ToArray()) | ConvertFrom-Json -ErrorAction Stop
    } finally { $buffer.Dispose(); $http.RawContentStream.Dispose() }
    if ($response.error) { throw 'L4 RPC rejected the request. Check pinned schema/runtime compatibility.' }
    $results = @($response.result)
    if (-not $results.Count) { throw 'Missing L4 query result.' }
    foreach ($r in $results) {
        if ($r.status -cne 'OK') {
            $errorObject = New-Object InvalidOperationException('L4 statement rejected the operation.')
            $errorObject.Data['L4Rejected'] = $true
            throw $errorObject
        }
    }
    return ,$results
}

function Initialize-LfoEpistemicSchema {
    param($Connection,[Parameter(Mandatory)][pscredential]$RuntimeCredential)
    if (-not $Connection.Bootstrap) { throw 'Bootstrap connection required.' }
    $version = Invoke-RestMethod -Uri ($Connection.Endpoint+'/version') -TimeoutSec $Connection.TimeoutSec
    if ([string]$version -notmatch '(^|[- ])3\.3\.0($|[ +])') { throw 'Expected SurrealDB 3.3.0.' }
    $null = Invoke-LfoEpistemicQuery $Connection 'DEFINE NAMESPACE IF NOT EXISTS lfo; USE NS lfo; DEFINE DATABASE IF NOT EXISTS epistemic;'
    $schema = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '../schema/L4Observations.surql'))
    $null = Invoke-LfoEpistemicQuery $Connection $schema
    if ($RuntimeCredential.UserName -cne 'lfo_r1') { throw 'Runtime user must be lfo_r1.' }
    $password = $RuntimeCredential.GetNetworkCredential().Password
    if ($password -cnotmatch '^[a-f0-9]{32,128}$') { throw 'Bootstrap requires a generated 32-128 character hexadecimal runtime password.' }
    # DEFINE USER requires a literal in 3.3.0; this strictly hex-only bootstrap value cannot contain SQL.
    $null = Invoke-LfoEpistemicQuery $Connection ("DEFINE USER IF NOT EXISTS lfo_r1 ON DATABASE PASSWORD '"+$password+"' ROLES EDITOR;")
}

function Add-LfoEpistemicObservation {
    param($Connection,[Parameter(Mandatory)][string]$LogDirectory,[Parameter(Mandatory)]$Observation)
    if ($Connection.Bootstrap) { throw 'Runtime writes must not use root credentials.' }
    # Reconstruct and compare canonical fields: reject forged source hashes/metadata.
    $p = @{LogDirectory=$LogDirectory;SourceFile=$Observation.source.file;Epoch=$Observation.source.epoch;TurnId=$Observation.source.turn_id;StageId=$Observation.source.stage_id;ObservationType=$Observation.observation_type;Detector=$Observation.detector;DetectorVersion=$Observation.detector_version;Confidence=$Observation.confidence;Excerpt=$Observation.excerpt;Interaction=$Observation.interaction;RelatedObservationId=$Observation.related_observation_id;Id=$Observation.observation_id;ObservedAt=$Observation.observed_at}
    $canonical = New-LfoEpistemicObservation @p
    $a = $canonical | ConvertTo-Json -Depth 10 -Compress
    $b = $Observation | ConvertTo-Json -Depth 10 -Compress
    if ($a -cne $b) { throw 'Observation differs from canonical L0-linked payload. Use New-LfoEpistemicObservation.' }
    $record = @{}
    foreach ($prop in $canonical.PSObject.Properties) { $record[$prop.Name]=$prop.Value }
    $record.payload_sha256 = Get-LfoEpistemicHash $a
    $sql = @'
LET $rid = type::record('observations', $key);
LET $old = SELECT * FROM ONLY $rid;
IF $old != NONE {
    RETURN {outcome: IF $old.payload_sha256 = $row.payload_sha256 { 'ALREADY_EXISTS' } ELSE { 'CONFLICT' }, observation_id: $key};
} ELSE {
    IF $row.related_observation_id != '' {
        LET $related = SELECT * FROM ONLY type::record('observations', $row.related_observation_id);
        IF $related = NONE OR $related.source.store_id != $row.source.store_id OR $related.source.epoch != $row.source.epoch { THROW 'Related observation must exist in the same store and epoch'; };
    };
    CREATE ONLY $rid CONTENT object::extend($row, {observed_at: <datetime>$row.observed_at, recorded_at: time::now()});
    RETURN {outcome: 'CREATED', observation_id: $key};
};
'@
    try {
        $result = Invoke-LfoEpistemicQuery $Connection $sql @{key=$record.observation_id;row=$record}
        return $result[-1].result
    } catch {
        if ($_.Exception.Data['L4Rejected']) {
            return [pscustomobject]@{outcome='REJECTED';observation_id=$record.observation_id;message='Database rejected the operation; no successful acknowledgement.'}
        }
        # A timeout/disconnect can happen after commit. Never generate a new ID on retry.
        return [pscustomobject]@{outcome='UNKNOWN';observation_id=$record.observation_id;message='Write not acknowledged. Retry the same observation ID/payload; inspect service logs.'}
    }
}

function Get-LfoEpistemicObservation {
    param($Connection,[Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$Id,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$StoreId,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Epoch)
    $r = Invoke-LfoEpistemicQuery $Connection 'SELECT * FROM type::record("observations",$key) WHERE source.store_id=$store AND source.epoch=$epoch;' @{key=$Id;store=$StoreId;epoch=$Epoch}
    return $r[-1].result
}

function Find-LfoEpistemicObservations {
    param($Connection,[Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$StoreId,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Epoch,
        [ValidateRange(1,200)][int]$Limit=50,
        [ValidatePattern('^([a-f0-9]{32})?$')][string]$AfterId='',
        [ValidateSet('','USER','LOCAL','FRONTIER','FINAL')][string]$Actor='',
        [string]$ObservationType='', [string]$Detector='')
    $r = Invoke-LfoEpistemicQuery $Connection @'
SELECT * FROM observations WHERE source.store_id=$store AND source.epoch=$epoch
AND observation_id > $after AND ($actor='' OR actor=$actor)
AND ($kind='' OR observation_type=$kind) AND ($detector='' OR detector=$detector)
ORDER BY observation_id ASC LIMIT $limit;
'@ @{store=$StoreId;epoch=$Epoch;after=$AfterId;actor=$Actor;kind=$ObservationType;detector=$Detector;limit=$Limit}
    $items = @($r[-1].result)
    return [pscustomobject]@{Items=$items;NextAfterId=$(if ($items.Count -eq $Limit) { $items[-1].observation_id } else { $null })}
}
