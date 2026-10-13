# R2 explicit human/offline annotation workflow over the frozen R1 API.
# This module does not detect turns, call a model, start a server, or infer a production L0 path.

function Assert-LfoEpistemicPlanProperties {
    param([Parameter(Mandatory)]$Object,[Parameter(Mandatory)][string[]]$Allowed,[Parameter(Mandatory)][string]$Context)
    foreach($p in @($Object.PSObject.Properties.Name)) {
        if($p -notin $Allowed) { throw ("Unknown "+$Context+" property: "+$p) }
    }
}

function Read-LfoEpistemicAnnotationPlan {
    param([Parameter(Mandatory)][string]$PlanPath)
    $file=Get-Item -LiteralPath $PlanPath -ErrorAction Stop
    if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Annotation plan must be a physical file.' }
    $utf8=New-Object Text.UTF8Encoding($false,$true)
    $plan=[IO.File]::ReadAllText($file.FullName,$utf8) | ConvertFrom-Json -ErrorAction Stop
    Assert-LfoEpistemicPlanProperties $plan @('schema','detector','detector_version','source','observations') 'plan'
    if($plan.schema -cne 'lfo-epistemic-annotation-plan-v1') { throw 'Unsupported annotation-plan schema.' }
    if([string]$plan.detector -cnotmatch '^[a-zA-Z0-9._-]{1,80}$') { throw 'Invalid plan detector.' }
    if([string]$plan.detector_version -cnotmatch '^[a-zA-Z0-9._-]{1,40}$') { throw 'Invalid plan detector_version.' }
    if($null -eq $plan.source) { throw 'Missing plan source.' }
    Assert-LfoEpistemicPlanProperties $plan.source @('file','epoch') 'source'
    if([string]$plan.source.file -cnotmatch '^conversation-[0-9]{4}-[0-9]{2}\.jsonl$') { throw 'Invalid plan source file.' }
    $epoch=[int]$plan.source.epoch
    if($epoch -lt 1) { throw 'Invalid plan epoch.' }
    $items=@($plan.observations)
    if($items.Count -lt 1 -or $items.Count -gt 200) { throw 'Annotation plan must contain 1-200 observations.' }
    return $plan
}

function ConvertFrom-LfoEpistemicAnnotationPlan {
    param([Parameter(Mandatory)][string]$PlanPath,[Parameter(Mandatory)][string]$LogDirectory)
    $plan=Read-LfoEpistemicAnnotationPlan $PlanPath
    $keys=New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $out=@()
    foreach($item in @($plan.observations)) {
        Assert-LfoEpistemicPlanProperties $item @('key','id','observed_at','turn_id','stage_id','observation_type','confidence','excerpt','interaction','related_key') 'observation'
        $key=[string]$item.key
        if($key -cnotmatch '^[a-z0-9][a-z0-9._-]{0,79}$') { throw 'Invalid observation key.' }
        if($keys.ContainsKey($key)) { throw ('Duplicate observation key: '+$key) }
        $id=[string]$item.id
        if($id -cnotmatch '^[a-f0-9]{32}$') { throw ('Invalid observation ID for key '+$key) }
        $relatedKey=if($null -eq $item.related_key){''}else{[string]$item.related_key}
        $relatedId=''
        if($relatedKey) {
            if(-not $keys.ContainsKey($relatedKey)) { throw ('related_key must reference an earlier observation in the same plan: '+$key+' -> '+$relatedKey) }
            $relatedId=$keys[$relatedKey]
        }
        $excerpt=if($null -eq $item.excerpt){''}else{[string]$item.excerpt}
        $interaction=if($null -eq $item.interaction){''}else{[string]$item.interaction}
        $p=@{
            LogDirectory=$LogDirectory
            SourceFile=[string]$plan.source.file
            Epoch=[int]$plan.source.epoch
            TurnId=[int]$item.turn_id
            StageId=[string]$item.stage_id
            ObservationType=[string]$item.observation_type
            Detector=[string]$plan.detector
            DetectorVersion=[string]$plan.detector_version
            Confidence=$(if($null -eq $item.confidence){$null}else{[double]$item.confidence})
            Excerpt=$excerpt
            Interaction=$interaction
            RelatedObservationId=$relatedId
            Id=$id
            ObservedAt=[string]$item.observed_at
        }
        $canonical=New-LfoEpistemicObservation @p
        $keys.Add($key,$id)
        $out += [pscustomobject]@{Key=$key;RelatedKey=$relatedKey;Observation=$canonical}
    }
    return [pscustomobject]@{
        Schema='lfo-epistemic-annotation-plan-v1'
        Detector=[string]$plan.detector
        DetectorVersion=[string]$plan.detector_version
        StoreId=(Get-LfoEpistemicL0Identity $LogDirectory)
        Epoch=[int]$plan.source.epoch
        SourceFile=[string]$plan.source.file
        Items=$out
    }
}

function Invoke-LfoEpistemicAnnotationPlan {
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$LogDirectory,
        $Connection,
        [switch]$ValidateOnly
    )
    $bundle=ConvertFrom-LfoEpistemicAnnotationPlan -PlanPath $PlanPath -LogDirectory $LogDirectory
    if($ValidateOnly) {
        return [pscustomobject]@{
            Validated=$true
            WriteAttempted=$false
            StoreId=$bundle.StoreId
            Epoch=$bundle.Epoch
            Count=@($bundle.Items).Count
            Items=@($bundle.Items | ForEach-Object {
                [pscustomobject]@{
                    key=$_.Key
                    observation_id=$_.Observation.observation_id
                    actor=$_.Observation.actor
                    stage=$_.Observation.stage
                    observation_type=$_.Observation.observation_type
                    interaction=$_.Observation.interaction
                    related_key=$_.RelatedKey
                }
            })
        }
    }
    if($null -eq $Connection) { throw 'Connection is required unless -ValidateOnly is used.' }
    $results=@()
    foreach($entry in @($bundle.Items)) {
        $w=Add-LfoEpistemicObservation -Connection $Connection -LogDirectory $LogDirectory -Observation $entry.Observation
        if($w.outcome -notin @('CREATED','ALREADY_EXISTS')) { throw ('Annotation write failed for '+$entry.Key+': '+$w.outcome) }
        $results += [pscustomobject]@{
            key=$entry.Key
            observation_id=$entry.Observation.observation_id
            actor=$entry.Observation.actor
            observation_type=$entry.Observation.observation_type
            interaction=$entry.Observation.interaction
            related_key=$entry.RelatedKey
            outcome=$w.outcome
        }
    }
    return [pscustomobject]@{
        Validated=$true
        WriteAttempted=$true
        StoreId=$bundle.StoreId
        Epoch=$bundle.Epoch
        Count=$results.Count
        Items=$results
    }
}
