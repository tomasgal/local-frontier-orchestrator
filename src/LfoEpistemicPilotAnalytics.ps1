# R2-C bounded deterministic analytics over explicit R1 observations.
# Read-only. No model calls, no prompt injection, no inference of psychological traits.

function Add-LfoEpistemicCount {
    param([hashtable]$Table,[string]$Key)
    if($null -eq $Key){$Key=''}
    if($Table.ContainsKey($Key)){$Table[$Key]=[int]$Table[$Key]+1}else{$Table[$Key]=1}
}

function ConvertTo-LfoEpistemicCountRows {
    param([hashtable]$Table,[string]$Name)
    return @($Table.Keys | Sort-Object | ForEach-Object {
        [pscustomobject]@{name=[string]$_;count=[int]$Table[$_]}
    })
}

function Get-LfoEpistemicPilotAnalytics {
    param(
        [Parameter(Mandatory)]$Connection,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$StoreId,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Epoch,
        [ValidateRange(1,200)][int]$PageSize=200,
        [ValidateRange(1,100000)][int]$MaxRecords=10000
    )
    $items=New-Object System.Collections.ArrayList
    $after=''
    do{
        $page=Find-LfoEpistemicObservations -Connection $Connection -StoreId $StoreId -Epoch $Epoch -Limit $PageSize -AfterId $after
        foreach($item in @($page.Items)){
            if($items.Count -ge $MaxRecords){throw 'Pilot analytics MaxRecords exceeded.'}
            [void]$items.Add($item)
        }
        $next=[string]$page.NextAfterId
        if($next -and $next -ceq $after){throw 'Pilot analytics pagination did not advance.'}
        $after=$next
    }while($after)

    $byActor=@{};$byType=@{};$byInteraction=@{};$byStage=@{}
    $index=@{}
    foreach($item in @($items)){
        Add-LfoEpistemicCount $byActor ([string]$item.actor)
        Add-LfoEpistemicCount $byType ([string]$item.observation_type)
        Add-LfoEpistemicCount $byInteraction ([string]$item.interaction)
        Add-LfoEpistemicCount $byStage ([string]$item.stage)
        $index[[string]$item.observation_id]=$item
    }

    $patterns=@{}
    $linked=0
    foreach($item in @($items)){
        $rid=[string]$item.related_observation_id
        if(-not $rid){continue}
        $linked++
        if(-not $index.ContainsKey($rid)){throw ('Linked observation missing from analytic scope: '+$rid)}
        $parent=$index[$rid]
        $key=([string]$item.actor)+'->'+([string]$parent.actor)+'|'+([string]$item.interaction)
        Add-LfoEpistemicCount $patterns $key
    }

    return [pscustomobject]@{
        Schema='lfo-r2-pilot-analytics-v1'
        StoreId=$StoreId
        Epoch=$Epoch
        ObservationCount=$items.Count
        LinkedObservationCount=$linked
        ByActor=(ConvertTo-LfoEpistemicCountRows $byActor 'actor')
        ByStage=(ConvertTo-LfoEpistemicCountRows $byStage 'stage')
        ByType=(ConvertTo-LfoEpistemicCountRows $byType 'observation_type')
        ByInteraction=(ConvertTo-LfoEpistemicCountRows $byInteraction 'interaction')
        LinkedPatterns=(ConvertTo-LfoEpistemicCountRows $patterns 'linked_pattern')
        Interpretation='Counts describe stored annotations in the selected corpus only; they are not truth, prevalence, importance, diagnosis, or detector-quality evidence.'
    }
}
