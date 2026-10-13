# L4-A2 recurrence/interaction analytics over frozen A1/R1.
# Read-only; no model calls; no detector promotion; no intervention.

if(-not (Get-Command Get-LfoObservatoryEpochItems -ErrorAction SilentlyContinue)){
    . (Join-Path $PSScriptRoot 'LfoEpistemicObservatory.ps1')
}

function Get-LfoA2Ratio {
    param([int]$Numerator,[int]$Denominator)
    if($Denominator -eq 0){return 0.0}
    return [double]$Numerator/[double]$Denominator
}

function New-LfoA2SupportIds {
    param([object[]]$Items,[ValidateRange(1,50)][int]$Limit=50)
    $seen=@{};$unique=@()
    foreach($i in @($Items)){
        $id=[string]$i.observation_id
        if($id -and -not $seen.ContainsKey($id)){$seen[$id]=$true;$unique+=$i}
    }
    return @($unique|Sort-Object @{Expression={[int]$_.source.turn_id}},@{Expression={Get-LfoObservatoryStageOrdinal ([string]$_.source.stage_id)}},@{Expression={[string]$_.observation_id}}|Select-Object -First $Limit|ForEach-Object{[string]$_.observation_id})
}

function Get-LfoA2WindowState {
    param(
        [object[]]$All,
        [hashtable]$Index,
        [int]$FirstTurn,
        [int]$LastTurn,
        [ValidateRange(1,50)][int]$SupportLimit=50
    )
    if($FirstTurn -gt $LastTurn){throw 'FirstTurn must not exceed LastTurn.'}
    $window=@($All|Where-Object{[int]$_.source.turn_id -ge $FirstTurn -and [int]$_.source.turn_id -le $LastTurn}|Sort-Object @{Expression={[int]$_.source.turn_id}},@{Expression={Get-LfoObservatoryStageOrdinal ([string]$_.source.stage_id)}},@{Expression={[string]$_.observation_id}})
    $inside=@{};foreach($i in $window){$inside[[string]$i.observation_id]=$true}

    $signatureGroups=@{}
    foreach($item in $window){
        $k='actor_type|'+([string]$item.actor)+'|'+([string]$item.observation_type)
        if(-not $signatureGroups.ContainsKey($k)){$signatureGroups[$k]=New-Object System.Collections.ArrayList}
        [void]$signatureGroups[$k].Add($item)
    }

    $linkedPairs=New-Object System.Collections.ArrayList
    $excludedLinks=0
    foreach($child in $window){
        $rid=[string]$child.related_observation_id
        if(-not $rid){continue}
        if(-not $Index.ContainsKey($rid)){throw ('Related observation missing from selected store/epoch: '+$rid)}
        $parent=$Index[$rid]
        if(-not $inside.ContainsKey($rid)){$excludedLinks++;continue}
        [void]$linkedPairs.Add([pscustomobject]@{Parent=$parent;Child=$child})
        $k='linked_response|'+([string]$parent.actor)+'->'+([string]$child.actor)+'|'+([string]$child.interaction)
        if(-not $signatureGroups.ContainsKey($k)){$signatureGroups[$k]=New-Object System.Collections.ArrayList}
        [void]$signatureGroups[$k].Add($child)
    }

    [pscustomobject]@{
        Window=$window
        Inside=$inside
        SignatureGroups=$signatureGroups
        LinkedPairs=@($linkedPairs)
        ExcludedBoundaryLinks=$excludedLinks
        FirstTurn=$FirstTurn
        LastTurn=$LastTurn
        WindowTurnCount=($LastTurn-$FirstTurn+1)
        AnnotatedTurnCount=@($window|ForEach-Object{[int]$_.source.turn_id}|Sort-Object -Unique).Count
        SupportLimit=$SupportLimit
    }
}

function Get-LfoA2SignatureRows {
    param([object]$State,[switch]$OnlyRecurring)
    $rows=@()
    foreach($k in ($State.SignatureGroups.Keys|Sort-Object)){
        $parts=$k -split '\|',2
        $kind=$parts[0];$signature=$parts[1]
        $items=@($State.SignatureGroups[$k])
        $turns=@($items|ForEach-Object{[int]$_.source.turn_id}|Sort-Object -Unique)
        if($OnlyRecurring -and $turns.Count -lt 2){continue}
        $rows += [pscustomobject]@{
            signature_kind=$kind
            signature=$signature
            occurrence_count=$items.Count
            distinct_turn_count=$turns.Count
            window_turn_count=[int]$State.WindowTurnCount
            annotated_turn_count=[int]$State.AnnotatedTurnCount
            distinct_turn_fraction=(Get-LfoA2Ratio $turns.Count $State.WindowTurnCount)
            annotated_turn_fraction=(Get-LfoA2Ratio $turns.Count $State.AnnotatedTurnCount)
            supporting_observation_ids=(New-LfoA2SupportIds $items $State.SupportLimit)
        }
    }
    return @($rows)
}

function Add-LfoA2ChainOccurrence {
    param([hashtable]$Table,[string]$Key,[object[]]$Nodes)
    if(-not $Table.ContainsKey($Key)){
        $Table[$Key]=[pscustomobject]@{Count=0;Items=(New-Object System.Collections.ArrayList)}
    }
    $entry=$Table[$Key]
    $entry.Count=[int]$entry.Count+1
    foreach($n in $Nodes){[void]$entry.Items.Add($n)}
}

function Get-LfoEpistemicInteractionAnalytics {
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
    $all=@(Get-LfoObservatoryEpochItems -Connection $Connection -StoreId $StoreId -Epoch $Epoch -PageSize $PageSize -MaxRecords $MaxRecords)
    $index=@{};foreach($i in $all){$index[[string]$i.observation_id]=$i}
    $state=Get-LfoA2WindowState $all $index $FirstTurn $LastTurn $SupportLimit

    $recurrence=@(Get-LfoA2SignatureRows $state -OnlyRecurring)

    $actorChains=@{};$typeChains=@{};$excludedChains=0;$chainOccurrences=0
    foreach($child in @($state.Window)){
        $rid=[string]$child.related_observation_id
        if(-not $rid){continue}
        if(-not $index.ContainsKey($rid)){throw ('Related observation missing from selected store/epoch: '+$rid)}
        $parent=$index[$rid]
        $grid=[string]$parent.related_observation_id
        if(-not $grid){continue}
        if(-not $index.ContainsKey($grid)){throw ('Grandparent observation missing from selected store/epoch: '+$grid)}
        $grand=$index[$grid]
        if(-not $state.Inside.ContainsKey($rid) -or -not $state.Inside.ContainsKey($grid)){$excludedChains++;continue}
        $chainOccurrences++
        $actorKey=([string]$grand.actor)+'->'+([string]$parent.actor)+'->'+([string]$child.actor)+'|'+([string]$parent.interaction)+'>'+([string]$child.interaction)
        $typeKey=([string]$grand.observation_type)+'->'+([string]$parent.observation_type)+'->'+([string]$child.observation_type)
        Add-LfoA2ChainOccurrence $actorChains $actorKey @($grand,$parent,$child)
        Add-LfoA2ChainOccurrence $typeChains $typeKey @($grand,$parent,$child)
    }

    $actorRows=@()
    foreach($k in ($actorChains.Keys|Sort-Object)){
        $parts=$k -split '\|',2;$entry=$actorChains[$k]
        $actorRows += [pscustomobject]@{
            actor_chain=$parts[0]
            interaction_sequence=$parts[1]
            count=[int]$entry.Count
            supporting_observation_ids=(New-LfoA2SupportIds @($entry.Items) $SupportLimit)
        }
    }
    $typeRows=@()
    foreach($k in ($typeChains.Keys|Sort-Object)){
        $entry=$typeChains[$k]
        $typeRows += [pscustomobject]@{
            type_chain=[string]$k
            count=[int]$entry.Count
            supporting_observation_ids=(New-LfoA2SupportIds @($entry.Items) $SupportLimit)
        }
    }

    $responseGroups=@{}
    $unclassifiedLinked=0
    foreach($pair in @($state.LinkedPairs)){
        $child=$pair.Child
        $interaction=[string]$child.interaction
        if($interaction -notin @('REINFORCED','CHALLENGED','CORRECTED','IGNORED')){$unclassifiedLinked++;continue}
        $actor=[string]$child.actor
        if(-not $responseGroups.ContainsKey($actor)){
            $responseGroups[$actor]=[pscustomobject]@{
                Total=0;REINFORCED=0;CHALLENGED=0;CORRECTED=0;IGNORED=0
                Items=(New-Object System.Collections.ArrayList)
            }
        }
        $g=$responseGroups[$actor]
        $g.Total=[int]$g.Total+1
        $g.$interaction=[int]$g.$interaction+1
        [void]$g.Items.Add($child)
    }
    $balance=@()
    foreach($actor in ($responseGroups.Keys|Sort-Object)){
        $g=$responseGroups[$actor]
        $balance += [pscustomobject]@{
            actor=$actor
            linked_response_count=[int]$g.Total
            reinforced_count=[int]$g.REINFORCED
            challenged_count=[int]$g.CHALLENGED
            corrected_count=[int]$g.CORRECTED
            ignored_count=[int]$g.IGNORED
            reinforced_fraction=(Get-LfoA2Ratio $g.REINFORCED $g.Total)
            challenged_fraction=(Get-LfoA2Ratio $g.CHALLENGED $g.Total)
            corrected_fraction=(Get-LfoA2Ratio $g.CORRECTED $g.Total)
            ignored_fraction=(Get-LfoA2Ratio $g.IGNORED $g.Total)
            supporting_observation_ids=(New-LfoA2SupportIds @($g.Items) $SupportLimit)
        }
    }

    return [pscustomobject]@{
        Schema='lfo-l4-a2-interaction-analytics-v1'
        StoreId=$StoreId;Epoch=$Epoch;FirstTurn=$FirstTurn;LastTurn=$LastTurn
        ObservationCount=@($state.Window).Count
        WindowTurnCount=[int]$state.WindowTurnCount
        DistinctAnnotatedTurnCount=[int]$state.AnnotatedTurnCount
        RecurrenceDensity=$recurrence
        ActorInteractionChains=$actorRows
        TypeChains=$typeRows
        ChainOccurrenceCount=$chainOccurrences
        ExcludedBoundaryLinks=[int]$state.ExcludedBoundaryLinks
        ExcludedBoundaryChains=$excludedChains
        ResponseBalance=$balance
        UnclassifiedLinkedInteractions=$unclassifiedLinked
        SupportingObservationIds=(New-LfoA2SupportIds @($state.Window) $SupportLimit)
        Interpretation='Descriptive structure of stored annotations in an explicit window; not behavioral prevalence, latent traits, causation, improvement, or deterioration.'
    }
}

function Compare-LfoEpistemicAdjacentInteractionWindows {
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
    if($FirstTurnA -gt $LastTurnA -or $FirstTurnB -gt $LastTurnB){throw 'Invalid adjacent-window bounds.'}
    if(($LastTurnA+1) -ne $FirstTurnB){throw 'A2 requires adjacent ordered windows: LastTurnA + 1 = FirstTurnB.'}

    $all=@(Get-LfoObservatoryEpochItems -Connection $Connection -StoreId $StoreId -Epoch $Epoch -PageSize $PageSize -MaxRecords $MaxRecords)
    $index=@{};foreach($i in $all){$index[[string]$i.observation_id]=$i}
    $a=Get-LfoA2WindowState $all $index $FirstTurnA $LastTurnA $SupportLimit
    $b=Get-LfoA2WindowState $all $index $FirstTurnB $LastTurnB $SupportLimit
    $ar=@(Get-LfoA2SignatureRows $a);$br=@(Get-LfoA2SignatureRows $b)
    $am=@{};foreach($r in $ar){$am[[string]$r.signature_kind+'|'+[string]$r.signature]=$r}
    $bm=@{};foreach($r in $br){$bm[[string]$r.signature_kind+'|'+[string]$r.signature]=$r}

    $rows=@();$counts=@{PRESENT_BOTH=0;ONLY_A=0;ONLY_B=0}
    foreach($key in @($am.Keys+$bm.Keys|Sort-Object -Unique)){
        $hasA=$am.ContainsKey($key);$hasB=$bm.ContainsKey($key)
        $status=if($hasA -and $hasB){'PRESENT_BOTH'}elseif($hasA){'ONLY_A'}else{'ONLY_B'}
        $counts[$status]=[int]$counts[$status]+1
        $ra=if($hasA){$am[$key]}else{$null};$rb=if($hasB){$bm[$key]}else{$null}
        $parts=$key -split '\|',2
        $rows += [pscustomobject]@{
            signature_kind=$parts[0]
            signature=$parts[1]
            status=$status
            a_occurrence_count=$(if($hasA){[int]$ra.occurrence_count}else{0})
            b_occurrence_count=$(if($hasB){[int]$rb.occurrence_count}else{0})
            a_distinct_turn_count=$(if($hasA){[int]$ra.distinct_turn_count}else{0})
            b_distinct_turn_count=$(if($hasB){[int]$rb.distinct_turn_count}else{0})
            a_supporting_observation_ids=$(if($hasA){@($ra.supporting_observation_ids)}else{@()})
            b_supporting_observation_ids=$(if($hasB){@($rb.supporting_observation_ids)}else{@()})
        }
    }

    return [pscustomobject]@{
        Schema='lfo-l4-a2-adjacent-window-presence-v1'
        StoreId=$StoreId;Epoch=$Epoch
        WindowA=[pscustomobject]@{FirstTurn=$FirstTurnA;LastTurn=$LastTurnA}
        WindowB=[pscustomobject]@{FirstTurn=$FirstTurnB;LastTurn=$LastTurnB}
        PresentBoth=[int]$counts.PRESENT_BOTH
        OnlyA=[int]$counts.ONLY_A
        OnlyB=[int]$counts.ONLY_B
        Signatures=$rows
        Interpretation='PRESENT_BOTH/ONLY_A/ONLY_B describe stored annotation signatures in two explicit adjacent windows only; they are not latent-trait persistence, emergence, cessation, improvement, deterioration, or causation.'
    }
}
