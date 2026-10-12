# L3-R3 deterministic retrieval planner / context compiler.
# Consumes only L3 metadata plus caller-supplied evidence payloads.
# L3 tags remain internal and are never rendered into the model-visible packet.

function Get-LfoL3PlannerTerms([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $stop = @(
        'ako','aky','aka','ake','a','aj','ale','alebo','by','co','je','som','sa','si','sme','ste',
        'ten','ta','to','tie','tento','tato','toto','tam','tu','na','do','od','po','pre','pri','s',
        'so','z','zo','v','vo','k','ku','u','o','uz','este','mi','ma','mu','ho','ich','ktory',
        'ktora','ktore','kolko','what','which','that','this','the','and','or','is','are','was',
        'were','to','of','in','on','for','with','about','it','we','you','i','our','my','does'
    )

    $seen = @{}
    $terms = @()
    foreach ($m in [regex]::Matches($Text, '[\p{L}\p{N}](?:[\p{L}\p{N}._:+-]*[\p{L}\p{N}])?')) {
        $key = ConvertTo-LfoL3Key ([string]$m.Value)
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if ($key.Length -lt 2 -and $key -notmatch '^\d+$') { continue }
        if ($stop -contains $key) { continue }
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $terms += $key
            if ($terms.Count -ge 24) { break }
        }
    }
    return @($terms)
}

function Get-LfoL3EvidenceLexicalScore([string]$Text, [string[]]$Terms) {
    if ([string]::IsNullOrWhiteSpace($Text) -or $null -eq $Terms -or $Terms.Count -eq 0) {
        return 0
    }
    $normalized = ConvertTo-LfoL3Key ($Text -replace '[^\p{L}\p{N}._:+-]+',' ')
    $score = 0
    foreach ($term in $Terms) {
        if ([string]::IsNullOrWhiteSpace($term)) { continue }
        if ($normalized -match ('(^|[-._:+])' + [regex]::Escape($term) + '([-._:+]|$)')) {
            $score += 1
        }
    }
    return $score
}

function Get-LfoL3QueryFacets($Classification) {
    if ($null -eq $Classification) { return @() }

    $facets = @()
    foreach ($x in @($Classification.Topics)) {
        if ($null -ne $x) {
            $facets += [pscustomobject]@{ Dimension='topic'; ValueKey=[string]$x.ValueKey; Weight=20 }
        }
    }
    foreach ($x in @($Classification.Entities)) {
        if ($null -ne $x) {
            $facets += [pscustomobject]@{ Dimension='entity'; ValueKey=[string]$x.ValueKey; Weight=40 }
        }
    }
    if ($null -ne $Classification.Kind) {
        $facets += [pscustomobject]@{ Dimension='kind'; ValueKey=[string]$Classification.Kind.ValueKey; Weight=10 }
    }
    return @($facets)
}

function Get-LfoL3CandidateItems(
    $Connection,
    [string]$ScopeId,
    $Classification,
    [int]$MaxCandidates = 48
) {
    $scope = $ScopeId.Trim()
    if ([string]::IsNullOrWhiteSpace($scope) -or $null -eq $Connection -or $MaxCandidates -le 0) {
        return @()
    }

    $queryFacets = @(Get-LfoL3QueryFacets $Classification)
    if ($queryFacets.Count -eq 0) { return @() }

    $byId = @{}
    $excluded = @{}

    foreach ($q in $queryFacets) {
        foreach ($row in @(Get-LfoL3ItemsByFacet $Connection $scope $q.Dimension $q.ValueKey 1)) {
            $id = [string]$row.id
            if (-not $byId.ContainsKey($id)) {
                $byId[$id] = [ordered]@{
                    Row = $row
                    Score = 0
                    TopicMatches = 0
                    EntityMatches = 0
                    KindMatches = 0
                }
            }
            $byId[$id].Score += [int]$q.Weight
            switch ([string]$q.Dimension) {
                'topic' { $byId[$id].TopicMatches++ }
                'entity' { $byId[$id].EntityMatches++ }
                'kind' { $byId[$id].KindMatches++ }
            }
        }
        foreach ($row in @(Get-LfoL3ItemsByFacet $Connection $scope $q.Dimension $q.ValueKey -1)) {
            $excluded[[string]$row.id] = $true
        }
    }

    foreach ($row in @(Get-LfoL3ItemsByFacet $Connection $scope 'retrieval' 'exclude' 1)) {
        $excluded[[string]$row.id] = $true
    }
    $priority = @{}
    foreach ($row in @(Get-LfoL3ItemsByFacet $Connection $scope 'retrieval' 'priority' 1)) {
        $priority[[string]$row.id] = $true
    }

    $out = @()
    foreach ($id in $byId.Keys) {
        if ($excluded.ContainsKey($id)) { continue }
        $entry = $byId[$id]
        if ($priority.ContainsKey($id)) { $entry.Score += 5 }
        $row = $entry.Row
        $out += [pscustomobject]@{
            Id = [int64]$row.id
            ScopeId = [string]$row.scope_id
            SourceLayer = [string]$row.source_layer
            SourceRef = [string]$row.source_ref
            SourceTurn = $row.source_turn
            ContentFingerprint = [string]$row.content_fingerprint
            MetadataScore = [int]$entry.Score
            TopicMatches = [int]$entry.TopicMatches
            EntityMatches = [int]$entry.EntityMatches
            KindMatches = [int]$entry.KindMatches
            Priority = $priority.ContainsKey($id)
        }
    }

    return @(
        $out |
        Sort-Object @{Expression='MetadataScore';Descending=$true},
                    @{Expression='SourceTurn';Descending=$true},
                    @{Expression='Id';Descending=$true} |
        Select-Object -First ([Math]::Min(128,[Math]::Max(1,$MaxCandidates)))
    )
}

function New-LfoL3ContextPlan(
    $Connection,
    [string]$ScopeId,
    [string]$Query,
    $Classification,
    [object[]]$EvidenceRecords,
    [int]$MaxItems = 3,
    [int]$MaxChars = 1200
) {
    $empty = [pscustomobject]@{
        Status = 'fallback_required'
        Packet = ''
        Selected = @()
        CandidateCount = 0
        ResolvedCandidates = 0
        SelectedCount = 0
        InputCandidateChars = 0
        PacketChars = 0
        DroppedChars = 0
        DuplicateDrops = 0
        LexicalNarrowDrops = 0
        AuthorityShadowDrops = 0
        BudgetDrops = 0
    }
    if ($null -eq $Connection -or [string]::IsNullOrWhiteSpace($ScopeId) -or
        $MaxItems -le 0 -or $MaxChars -le 0) {
        return $empty
    }

    $queryFacets = @(Get-LfoL3QueryFacets $Classification)
    if ($queryFacets.Count -eq 0) {
        $empty.Status = 'no_query_facets'
        return $empty
    }

    $candidates = @(Get-LfoL3CandidateItems $Connection $ScopeId $Classification 48)
    $empty.CandidateCount = $candidates.Count
    if ($candidates.Count -eq 0) {
        $empty.Status = 'no_candidates'
        return $empty
    }

    $payloadMap = @{}
    foreach ($record in @($EvidenceRecords)) {
        if ($null -eq $record) { continue }
        $layer = ([string]$record.SourceLayer).Trim().ToUpperInvariant()
        $ref = ([string]$record.SourceRef).Trim()
        $text = [string]$record.Text
        if ($layer -notin @('L0','L2') -or [string]::IsNullOrWhiteSpace($ref) -or
            [string]::IsNullOrWhiteSpace($text)) { continue }
        $payloadMap[$layer + '|' + $ref] = $record
    }

    $terms = @(Get-LfoL3PlannerTerms $Query)
    $resolved = @()
    $candidateChars = 0
    foreach ($candidate in $candidates) {
        $key = ([string]$candidate.SourceLayer).ToUpperInvariant() + '|' + [string]$candidate.SourceRef
        if (-not $payloadMap.ContainsKey($key)) { continue }
        $payload = $payloadMap[$key]
        $text = [string]$payload.Text
        $candidateChars += $text.Length

        $lexical = Get-LfoL3EvidenceLexicalScore $text $terms

        # Ranking is intentionally lexicographic in effect:
        #   1) metadata relevance dominates,
        #   2) for equal metadata relevance, compact/current L2 evidence
        #      outranks a more verbose L0 wording,
        #   3) lexical richness only breaks ties inside that authority class.
        # Max lexical contribution is bounded below the L2 authority step.
        $layerAuthority = if ([string]$candidate.SourceLayer -eq 'L2') { 200 } else { 0 }
        $resolved += [pscustomobject]@{
            Id = [int64]$candidate.Id
            SourceLayer = [string]$candidate.SourceLayer
            SourceRef = [string]$candidate.SourceRef
            SourceTurn = $candidate.SourceTurn
            ContentFingerprint = [string]$candidate.ContentFingerprint
            Text = $text
            MetadataScore = [int]$candidate.MetadataScore
            TopicMatches = [int]$candidate.TopicMatches
            EntityMatches = [int]$candidate.EntityMatches
            KindMatches = [int]$candidate.KindMatches
            LexicalScore = [int]$lexical
            Score = ([int]$candidate.MetadataScore * 1000) + $layerAuthority + ([int]$lexical * 5)
            Priority = [bool]$candidate.Priority
        }
    }
    $empty.ResolvedCandidates = $resolved.Count
    $empty.InputCandidateChars = $candidateChars
    if ($resolved.Count -eq 0) {
        $empty.Status = 'unresolved_candidates'
        return $empty
    }

    $deduped = @()
    $duplicateDrops = 0
    $groups = @{}
    $withoutFingerprint = @()
    foreach ($item in $resolved) {
        $fp = [string]$item.ContentFingerprint
        if ([string]::IsNullOrWhiteSpace($fp)) {
            $withoutFingerprint += $item
            continue
        }
        if (-not $groups.ContainsKey($fp)) { $groups[$fp] = @() }
        $groups[$fp] = @($groups[$fp]) + @($item)
    }
    foreach ($fp in $groups.Keys) {
        $group = @($groups[$fp])
        $winner = @(
            $group |
            Sort-Object @{Expression={if ($_.SourceLayer -eq 'L2') {1} else {0}};Descending=$true},
                        @{Expression={([string]$_.Text).Length};Descending=$false},
                        @{Expression='Score';Descending=$true},
                        @{Expression='SourceTurn';Descending=$true} |
            Select-Object -First 1
        )[0]
        $deduped += $winner
        $duplicateDrops += [Math]::Max(0,$group.Count - 1)
    }
    $deduped += $withoutFingerprint

    # If several L2 facts are equally eligible by matched L3 facets, use lexical
    # contrast only as a deterministic read-side discriminator.  This keeps a
    # broad query broad (all scores equal), but lets an explicit predicate name
    # such as os, ram or cpu_count suppress sibling facts from the same entity.
    # L0 evidence is never removed by this step.
    $lexicalNarrowDrops = 0
    $authorityShadowDrops = 0
    $l0Deduped = @($deduped | Where-Object { $_.SourceLayer -ne 'L2' })
    $l2Deduped = @($deduped | Where-Object { $_.SourceLayer -eq 'L2' })
    $narrowedL2 = @()
    $narrowedSignatures = @{}
    foreach ($group in @($l2Deduped | Group-Object -Property {
        '{0}|{1}|{2}' -f $_.TopicMatches,$_.EntityMatches,$_.KindMatches
    })) {
        $items = @($group.Group)
        if ($items.Count -le 1) {
            $narrowedL2 += $items
            continue
        }
        $range = $items | Measure-Object -Property LexicalScore -Minimum -Maximum
        if ([int]$range.Maximum -gt [int]$range.Minimum) {
            $keep = @($items | Where-Object { [int]$_.LexicalScore -gt [int]$range.Minimum })
            if ($keep.Count -gt 0) {
                $narrowedL2 += $keep
                $lexicalNarrowDrops += ($items.Count - $keep.Count)
                $narrowedSignatures[[string]$group.Name] = $true
                continue
            }
        }
        $narrowedL2 += $items
    }

    # When an explicit predicate signal has already narrowed current L2 facts,
    # equally-faceted L0 narration is redundant for that read and may carry an
    # obsolete predecessor value.  Shadow it only for signatures where lexical
    # narrowing actually fired; topic-only/broad L0 retrieval remains intact.
    $keptL0 = @()
    foreach ($item in $l0Deduped) {
        $signature = '{0}|{1}|{2}' -f $item.TopicMatches,$item.EntityMatches,$item.KindMatches
        if ($narrowedSignatures.ContainsKey($signature)) {
            $authorityShadowDrops++
            continue
        }
        $keptL0 += $item
    }
    $deduped = @($keptL0) + @($narrowedL2)

    $ranked = @(
        $deduped |
        Sort-Object @{Expression='Score';Descending=$true},
                    @{Expression={if ($_.SourceLayer -eq 'L2') {1} else {0}};Descending=$true},
                    @{Expression='SourceTurn';Descending=$true},
                    @{Expression='Id';Descending=$true}
    )

    $selected = @()
    $parts = @()
    $used = 0
    $budgetDrops = 0
    foreach ($item in $ranked) {
        if ($selected.Count -ge $MaxItems) {
            $budgetDrops++
            continue
        }
        $text = [string]$item.Text
        $cost = $text.Length + $(if ($parts.Count -gt 0) { 1 } else { 0 })
        if (($used + $cost) -gt $MaxChars) {
            $budgetDrops++
            continue
        }
        $selected += $item
        $parts += $text
        $used += $cost
    }

    if ($selected.Count -eq 0) {
        $empty.Status = 'budget_empty'
        $empty.DuplicateDrops = $duplicateDrops
        $empty.LexicalNarrowDrops = $lexicalNarrowDrops
        $empty.AuthorityShadowDrops = $authorityShadowDrops
        $empty.BudgetDrops = $budgetDrops
        return $empty
    }

    $packet = $parts -join "`n"
    return [pscustomobject]@{
        Status = 'ok'
        Packet = $packet
        Selected = @($selected)
        CandidateCount = $candidates.Count
        ResolvedCandidates = $resolved.Count
        SelectedCount = $selected.Count
        InputCandidateChars = $candidateChars
        PacketChars = $packet.Length
        DroppedChars = [Math]::Max(0,$candidateChars - $packet.Length)
        DuplicateDrops = $duplicateDrops
        LexicalNarrowDrops = $lexicalNarrowDrops
        AuthorityShadowDrops = $authorityShadowDrops
        BudgetDrops = $budgetDrops
    }
}
