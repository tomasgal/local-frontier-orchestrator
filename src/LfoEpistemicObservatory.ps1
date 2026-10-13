# A1-B explicit read-only Observatory analytics over frozen R1/R2.
# No model calls, no prompt injection, no response intervention.

function Add-LfoObservatoryCount {
    param([hashtable]$Table,[string]$Key,[int]$Amount=1)
    if($null -eq $Key){$Key=''}
    if($Table.ContainsKey($Key)){$Table[$Key]=[int]$Table[$Key]+$Amount}else{$Table[$Key]=$Amount}
}

function ConvertTo-LfoObservatoryCountRows {
    param([hashtable]$Table)
    return @($Table.Keys|Sort-Object|ForEach-Object{[pscustomobject]@{name=[string]$_;count=[int]$Table[$_]}})
}

function Get-LfoObservatoryStageOrdinal {
    param([string]$StageId)
    if($StageId -notmatch '^s([1-9][0-9]*)$'){throw 'Invalid stage_id in stored observation.'}
    return [int]$Matches[1]
}

function Get-LfoObservatoryEpochItems {
    param(
        [Parameter(Mandatory)]$Connection,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$StoreId,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Epoch,
        [ValidateRange(1,200)][int]$PageSize=100,
        [ValidateRange(1,100000)][int]$MaxRecords=10000
    )
    $items=New-Object System.Collections.ArrayList
    $after=''
    do{
        $page=Find-LfoEpistemicObservations -Connection $Connection -StoreId $StoreId -Epoch $Epoch -Limit $PageSize -AfterId $after
        foreach($item in @($page.Items)){
            if($items.Count -ge $MaxRecords){throw 'A1 MaxRecords exceeded.'}
            [void]$items.Add($item)
        }
        $next=[string]$page.NextAfterId
        if($next -and $next -ceq $after){throw 'A1 pagination did not advance.'}
        $after=$next
    }while($after)
    return @($items)
}

function New-LfoObservatorySupportIds {
    param([object[]]$Items,[ValidateRange(1,50)][int]$Limit=50)
    return @($Items|Sort-Object @{Expression={[int]$_.source.turn_id}},@{Expression={Get-LfoObservatoryStageOrdinal ([string]$_.source.stage_id)}},@{Expression={[string]$_.observation_id}}|Select-Object -First $Limit|ForEach-Object{[string]$_.observation_id})
}

function ConvertTo-LfoObservatorySupportRows {
    param([hashtable]$Groups,[ValidateRange(1,50)][int]$SupportLimit=50)
    $rows=@()
    foreach($key in ($Groups.Keys|Sort-Object)){
        $arr=@($Groups[$key])
        $rows += [pscustomobject]@{
            name=[string]$key
            count=$arr.Count
            supporting_observation_ids=(New-LfoObservatorySupportIds $arr $SupportLimit)
        }
    }
    return @($rows)
}

function Get-LfoObservatoryRecurrenceCandidates {
    param([object[]]$WindowItems,[hashtable]$AllIndex,[ValidateRange(1,50)][int]$SupportLimit=50)
    $groups=@{}

    foreach($item in @($WindowItems)){
        $sig=([string]$item.actor)+'|'+([string]$item.observation_type)
        if(-not $groups.ContainsKey($sig)){$groups[$sig]=New-Object System.Collections.ArrayList}
        [void]$groups[$sig].Add($item)
    }

    foreach($child in @($WindowItems)){
        $rid=[string]$child.related_observation_id
        if(-not $rid -or -not $AllIndex.ContainsKey($rid)){continue}
        $parent=$AllIndex[$rid]
        # Window boundary is checked by explicit membership, never annotation time.
        if(-not @($WindowItems|Where-Object observation_id -eq $rid).Count){continue}
        $sig=([string]$parent.actor)+'->'+([string]$child.actor)+'|'+([string]$child.interaction)
        if(-not $groups.ContainsKey($sig)){$groups[$sig]=New-Object System.Collections.ArrayList}
        [void]$groups[$sig].Add($child)
    }

    $rows=@()
    foreach($sig in ($groups.Keys|Sort-Object)){
        $arr=@($groups[$sig])
        $turns=@($arr|ForEach-Object{[int]$_.source.turn_id}|Sort-Object -Unique)
        $rows += [pscustomobject]@{
            signature=[string]$sig
            occurrence_count=$arr.Count
            distinct_turn_count=$turns.Count
            supporting_observation_ids=(New-LfoObservatorySupportIds $arr $SupportLimit)
        }
    }
    return @($rows)
}

function Get-LfoEpistemicObservatoryWindow {
    param(
        [Parameter(Mandatory)]$Connection,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$StoreId,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Epoch,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$FirstTurn,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$LastTurn,
        [ValidateRange(1,200)][int]$PageSize=100,
        [ValidateRange(1,100000)][int]$MaxRecords=10000,
        [ValidateRange(1,50)][int]$SupportLimit=50
    )
    if($FirstTurn -gt $LastTurn){throw 'FirstTurn must not exceed LastTurn.'}
    $all=@(Get-LfoObservatoryEpochItems $Connection $StoreId $Epoch $PageSize $MaxRecords)
    $index=@{}
    foreach($item in $all){$index[[string]$item.observation_id]=$item}
    $window=@($all|Where-Object{[int]$_.source.turn_id -ge $FirstTurn -and [int]$_.source.turn_id -le $LastTurn}|Sort-Object @{Expression={[int]$_.source.turn_id}},@{Expression={Get-LfoObservatoryStageOrdinal ([string]$_.source.stage_id)}},@{Expression={[string]$_.observation_id}})

    $actor=@{};$stage=@{};$type=@{};$interaction=@{}
    foreach($item in $window){
        Add-LfoObservatoryCount $actor ([string]$item.actor)
        Add-LfoObservatoryCount $stage ([string]$item.stage)
        Add-LfoObservatoryCount $type ([string]$item.observation_type)
        Add-LfoObservatoryCount $interaction ([string]$item.interaction)
    }

    $actorTransitions=@{};$typeTransitions=@{};$childInteractions=@{}
    $excluded=0
    foreach($child in $window){
        $rid=[string]$child.related_observation_id
        if(-not $rid){continue}
        if(-not $index.ContainsKey($rid)){throw ('Related observation missing from selected store/epoch: '+$rid)}
        $parent=$index[$rid]
        $inside=([int]$parent.source.turn_id -ge $FirstTurn -and [int]$parent.source.turn_id -le $LastTurn)
        if(-not $inside){$excluded++;continue}
        $ak=([string]$parent.actor)+'->'+([string]$child.actor)
        $tk=([string]$parent.observation_type)+'->'+([string]$child.observation_type)
        $ik=[string]$child.interaction
        foreach($pair in @(@($actorTransitions,$ak),@($typeTransitions,$tk),@($childInteractions,$ik))){
            $table=$pair[0];$key=[string]$pair[1]
            if(-not $table.ContainsKey($key)){$table[$key]=New-Object System.Collections.ArrayList}
            [void]$table[$key].Add($child)
        }
    }

    $candidates=@(Get-LfoObservatoryRecurrenceCandidates $window $index $SupportLimit)
    $recurrence=@($candidates|Where-Object distinct_turn_count -ge 2)

    return [pscustomobject]@{
        Schema='lfo-l4-a1-window-v1'
        StoreId=$StoreId;Epoch=$Epoch;FirstTurn=$FirstTurn;LastTurn=$LastTurn
        ObservationCount=$window.Count
        DistinctAnnotatedTurnCount=@($window|ForEach-Object{[int]$_.source.turn_id}|Sort-Object -Unique).Count
        CountsByActor=(ConvertTo-LfoObservatoryCountRows $actor)
        CountsByStage=(ConvertTo-LfoObservatoryCountRows $stage)
        CountsByObservationType=(ConvertTo-LfoObservatoryCountRows $type)
        CountsByInteraction=(ConvertTo-LfoObservatoryCountRows $interaction)
        ParentActorToChildActor=(ConvertTo-LfoObservatorySupportRows $actorTransitions $SupportLimit)
        ParentTypeToChildType=(ConvertTo-LfoObservatorySupportRows $typeTransitions $SupportLimit)
        ChildInteraction=(ConvertTo-LfoObservatorySupportRows $childInteractions $SupportLimit)
        ExcludedBoundaryLinks=$excluded
        Recurrence=$recurrence
        SupportingObservationIds=(New-LfoObservatorySupportIds $window $SupportLimit)
        Interpretation='Descriptive stored-annotation evidence only; not truth, prevalence, diagnosis, detector accuracy, trend, or causation.'
    }
}

function Compare-LfoEpistemicObservatoryWindows {
    param(
        [Parameter(Mandatory)]$Connection,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$StoreId,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Epoch,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$FirstTurnA,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$LastTurnA,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$FirstTurnB,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$LastTurnB,
        [ValidateRange(1,200)][int]$PageSize=100,
        [ValidateRange(1,100000)][int]$MaxRecords=10000,
        [ValidateRange(1,50)][int]$SupportLimit=50
    )
    if($FirstTurnA -gt $LastTurnA -or $FirstTurnB -gt $LastTurnB){throw 'Invalid comparison window.'}
    if($LastTurnA -ge $FirstTurnB){throw 'A1 comparison requires ordered non-overlapping windows A then B.'}

    $all=@(Get-LfoObservatoryEpochItems $Connection $StoreId $Epoch $PageSize $MaxRecords)
    $index=@{};foreach($i in $all){$index[[string]$i.observation_id]=$i}
    $a=@($all|Where-Object{[int]$_.source.turn_id -ge $FirstTurnA -and [int]$_.source.turn_id -le $LastTurnA})
    $b=@($all|Where-Object{[int]$_.source.turn_id -ge $FirstTurnB -and [int]$_.source.turn_id -le $LastTurnB})

    function Counts($items,$field){
        $h=@{};foreach($i in @($items)){Add-LfoObservatoryCount $h ([string]$i.$field)};return $h
    }
    function DeltaRows($ha,$hb){
        $keys=@($ha.Keys+$hb.Keys|Sort-Object -Unique);$rows=@()
        foreach($k in $keys){$av=if($ha.ContainsKey($k)){[int]$ha[$k]}else{0};$bv=if($hb.ContainsKey($k)){[int]$hb[$k]}else{0};$rows+=[pscustomobject]@{name=[string]$k;a=$av;b=$bv;delta=($bv-$av)}}
        return $rows
    }

    $typeDelta=DeltaRows (Counts $a 'observation_type') (Counts $b 'observation_type')
    $interactionDelta=DeltaRows (Counts $a 'interaction') (Counts $b 'interaction')

    $ra=@(Get-LfoObservatoryRecurrenceCandidates $a $index $SupportLimit)
    $rb=@(Get-LfoObservatoryRecurrenceCandidates $b $index $SupportLimit)
    $rmapA=@{};foreach($r in $ra){$rmapA[[string]$r.signature]=$r}
    $rmapB=@{};foreach($r in $rb){$rmapB[[string]$r.signature]=$r}
    $rrows=@()
    foreach($sig in @($rmapA.Keys+$rmapB.Keys|Sort-Object -Unique)){
        $at=if($rmapA.ContainsKey($sig)){[int]$rmapA[$sig].distinct_turn_count}else{0}
        $bt=if($rmapB.ContainsKey($sig)){[int]$rmapB[$sig].distinct_turn_count}else{0}
        if($at -lt 2 -and $bt -lt 2){continue}
        $rrows += [pscustomobject]@{signature=[string]$sig;a_distinct_turn_count=$at;b_distinct_turn_count=$bt;delta=($bt-$at)}
    }

    return [pscustomobject]@{
        Schema='lfo-l4-a1-window-comparison-v1'
        StoreId=$StoreId;Epoch=$Epoch
        WindowA=[pscustomobject]@{FirstTurn=$FirstTurnA;LastTurn=$LastTurnA}
        WindowB=[pscustomobject]@{FirstTurn=$FirstTurnB;LastTurn=$LastTurnB}
        CountDeltaByObservationType=$typeDelta
        CountDeltaByInteraction=$interactionDelta
        DistinctTurnDeltaByRecurrenceSignature=$rrows
        Interpretation='Descriptive B-minus-A count differences only; not trend, improvement, deterioration, prevalence change, causation, or intervention effect.'
    }
}

function Get-LfoEpistemicObservatoryProvenance {
    param(
        [Parameter(Mandatory)]$Connection,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{32}$')][string]$StoreId,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Epoch,
        [Parameter(Mandatory)][string[]]$ObservationId,
        [ValidateRange(1,50)][int]$Limit=50
    )
    $ids=@($ObservationId|Select-Object -Unique)
    if($ids.Count -gt $Limit){throw 'Provenance support exceeds requested bound.'}
    $out=@()
    foreach($id in $ids){
        if($id -cnotmatch '^[a-f0-9]{32}$'){throw 'Invalid observation ID in provenance request.'}
        $rows=@(Get-LfoEpistemicObservation -Connection $Connection -Id $id -StoreId $StoreId -Epoch $Epoch)
        if($rows.Count -ne 1){throw ('Observation unavailable in requested store/epoch: '+$id)}
        $i=$rows[0]
        $out += [pscustomobject]@{
            observation_id=[string]$i.observation_id
            store_id=[string]$i.source.store_id
            file=[string]$i.source.file
            epoch=[int]$i.source.epoch
            turn_id=[int]$i.source.turn_id
            stage_id=[string]$i.source.stage_id
            content_sha256=[string]$i.source.content_sha256
        }
    }
    return @($out|Sort-Object turn_id,@{Expression={Get-LfoObservatoryStageOrdinal $_.stage_id}},observation_id)
}
