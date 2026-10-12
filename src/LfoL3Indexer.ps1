# L3 deterministic post-turn indexing / maintenance.
# Runs after the user-visible answer. Reads L2, writes only reconstructible L3 metadata.

function Initialize-LfoL3DefaultKindRules($Connection) {
    foreach ($r in @(
        @('kind','decision','decided',100,'l3-kind-v1'),
        @('kind','decision','decision',90,'l3-kind-v1'),
        @('kind','decision','agreed',100,'l3-kind-v1'),
        @('kind','decision','rejected',100,'l3-kind-v1'),
        @('kind','decision','rozhodli sme',110,'l3-kind-v1'),
        @('kind','configuration','configuration',100,'l3-kind-v1'),
        @('kind','configuration','configured',100,'l3-kind-v1'),
        @('kind','configuration','OS',80,'l3-kind-v1'),
        @('kind','configuration','runs',80,'l3-kind-v1'),
        @('kind','configuration','run',70,'l3-kind-v1'),
        @('kind','configuration','uses',70,'l3-kind-v1'),
        @('kind','configuration','používa',80,'l3-kind-v1'),
        @('kind','configuration','pouziva',80,'l3-kind-v1'),
        @('kind','result','passed',100,'l3-kind-v1'),
        @('kind','result','failed',100,'l3-kind-v1'),
        @('kind','result','PASS',90,'l3-kind-v1'),
        @('kind','result','FAIL',90,'l3-kind-v1'),
        @('kind','preference','prefer',100,'l3-kind-v1'),
        @('kind','preference','radšej',100,'l3-kind-v1'),
        @('kind','preference','radsej',100,'l3-kind-v1')
    )) {
        Set-LfoL3TermRule $Connection $r[0] $r[1] $r[2] ([int]$r[3]) $r[4] $true
    }
}

function Sync-LfoL3ConfiguredTopicRules(
    $Connection,
    [object[]]$TopicRules
) {
    $count = 0
    foreach ($rule in @($TopicRules)) {
        if ($null -eq $rule) { continue }
        $topic = [string]$rule.Topic
        if ([string]::IsNullOrWhiteSpace($topic)) { continue }
        $priority = 100
        if ($null -ne $rule.PSObject.Properties['Priority']) {
            $priority = [int]$rule.Priority
        }
        foreach ($term in @($rule.Terms)) {
            if ([string]::IsNullOrWhiteSpace([string]$term)) { continue }
            Set-LfoL3TermRule $Connection 'topic' $topic ([string]$term) $priority 'l3-topic-config-v1' $true
            $count++
        }
    }
    return $count
}

function Sync-LfoL3EntityRulesFromL2(
    $L3Connection,
    [string]$L2Path,
    [string]$ScopeId
) {
    if (-not (Test-Path -LiteralPath $L2Path -PathType Leaf) -or
        [string]::IsNullOrWhiteSpace($ScopeId)) { return 0 }

    $reader = $null
    try {
        $reader = Open-LfoMemoryReadOnly $L2Path
        if ($null -eq $reader) { return 0 }

        $rows = @(Invoke-LfoSqliteQuery $reader @'
WITH scoped_entities AS (
    SELECT subject_entity_id AS entity_id
    FROM current_facts
    WHERE scope_id = ?1
    UNION
    SELECT object_entity_id AS entity_id
    FROM current_facts
    WHERE scope_id = ?1 AND object_entity_id IS NOT NULL
)
SELECT DISTINCT n.entity_id, n.name
FROM entity_names n
JOIN scoped_entities s ON s.entity_id = n.entity_id
ORDER BY n.entity_id, n.id;
'@ @($ScopeId))

        $count = 0
        foreach ($row in $rows) {
            $entityKey = 'l2:' + [string][int64]$row.entity_id
            $name = [string]$row.name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            Set-LfoL3TermRule $L3Connection 'entity' $entityKey $name 100 'l3-l2-entity-v1' $true
            $count++
        }
        return $count
    } finally {
        if ($null -ne $reader) { Close-LfoSqliteDatabase $reader }
    }
}

function Get-LfoL3PredicateRuleTerms([string]$Predicate) {
    $key = ConvertTo-LfoL3Key $Predicate
    if ([string]::IsNullOrWhiteSpace($key)) { return @() }

    $parts = @($key -split '[-._:+]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $seen = @{}
    $out = @()
    function Add-PredicateTerm([string]$Term,[int]$Priority) {
        $termKey = ConvertTo-LfoL3Key $Term
        if ([string]::IsNullOrWhiteSpace($termKey) -or $seen.ContainsKey($termKey)) { return }
        $seen[$termKey] = $true
        $script:__lfoPredicateTerms += [pscustomobject]@{ Term=$Term; Priority=$Priority }
    }

    $script:__lfoPredicateTerms = @()
    Add-PredicateTerm $Predicate 130
    if ($parts.Count -gt 1) {
        Add-PredicateTerm ($parts -join ' ') 120
    }

    $genericSuffix = @('gb','mb','tb','kb','count','id','value','name','flag','bool','boolean','enabled')
    foreach ($part in $parts) {
        if ($part -in $genericSuffix) { continue }
        Add-PredicateTerm $part 100
    }
    $out = @($script:__lfoPredicateTerms)
    Remove-Variable -Scope Script -Name __lfoPredicateTerms -ErrorAction SilentlyContinue
    return $out
}

function Sync-LfoL3PredicateRulesFromL2(
    $L3Connection,
    [string]$L2Path,
    [string]$ScopeId
) {
    if (-not (Test-Path -LiteralPath $L2Path -PathType Leaf) -or
        [string]::IsNullOrWhiteSpace($ScopeId)) { return 0 }

    $reader = $null
    try {
        $reader = Open-LfoMemoryReadOnly $L2Path
        if ($null -eq $reader) { return 0 }
        $rows = @(Invoke-LfoSqliteQuery $reader @'
SELECT DISTINCT predicate
FROM facts
WHERE scope_id = ?1
  AND predicate IS NOT NULL
  AND TRIM(predicate) <> ''
ORDER BY predicate;
'@ @($ScopeId))
        $count = 0
        foreach ($row in $rows) {
            $predicate = [string]$row.predicate
            foreach ($term in @(Get-LfoL3PredicateRuleTerms $predicate)) {
                Set-LfoL3TermRule $L3Connection 'predicate' $predicate ([string]$term.Term) ([int]$term.Priority) 'l3-l2-predicate-v1' $true
                $count++
            }
        }
        return $count
    } finally {
        if ($null -ne $reader) { Close-LfoSqliteDatabase $reader }
    }
}

function Get-LfoL3FactsTouchedAtTurn(
    [string]$L2Path,
    [string]$ScopeId,
    [int64]$TurnId
) {
    if (-not (Test-Path -LiteralPath $L2Path -PathType Leaf)) { return @() }

    $reader = $null
    try {
        $reader = Open-LfoMemoryReadOnly $L2Path
        if ($null -eq $reader) { return @() }

        return @(Invoke-LfoSqliteQuery $reader @'
SELECT
    f.id,
    f.subject_entity_id,
    f.object_entity_id,
    f.predicate,
    f.source_turn,
    f.valid_to_turn,
    CASE WHEN cf.id IS NULL THEN 0 ELSE 1 END AS is_current
FROM facts f
LEFT JOIN current_facts cf ON cf.id = f.id
WHERE f.scope_id = ?1
  AND (f.source_turn = ?2 OR f.valid_to_turn = ?2)
ORDER BY f.id;
'@ @($ScopeId,$TurnId))
    } finally {
        if ($null -ne $reader) { Close-LfoSqliteDatabase $reader }
    }
}

function Add-LfoL3TurnFacetsToItem(
    $Connection,
    [int64]$ItemId,
    $Classification
) {
    if ($null -eq $Classification) { return 0 }
    $count = 0
    foreach ($topic in @($Classification.Topics)) {
        [void](Set-LfoL3Facet $Connection $ItemId 'topic' ([string]$topic.ValueKey) 1 ([string]$topic.RuleId))
        $count++
    }
    if ($null -ne $Classification.Kind) {
        [void](Set-LfoL3ExclusiveFacet $Connection $ItemId 'kind' ([string]$Classification.Kind.ValueKey) 1 ([string]$Classification.Kind.RuleId))
        $count++
    }
    return $count
}

function Invoke-LfoL3PostTurnIndex(
    [string]$Prompt,
    [string]$FinalContent,
    [int64]$TurnId,
    [int]$Epoch,
    [string]$L2Path,
    [string]$L3Path,
    [object[]]$TopicRules
) {
    $result = [ordered]@{
        Status = 'disabled'
        TurnIndexed = $false
        L2FactsTouched = 0
        L2ItemsIndexed = 0
        FacetsWritten = 0
        TopicRulesSynced = 0
        EntityRulesSynced = 0
        PredicateRulesSynced = 0
        Error = $null
    }
    if ($TurnId -le 0 -or $Epoch -le 0 -or
        [string]::IsNullOrWhiteSpace($L3Path)) {
        return [pscustomobject]$result
    }

    $scopeId = "conversation:$Epoch"
    $db = $null
    try {
        $db = Open-LfoL3Store $L3Path
        Initialize-LfoL3DefaultKindRules $db
        $result.TopicRulesSynced = Sync-LfoL3ConfiguredTopicRules $db $TopicRules
        $result.EntityRulesSynced = Sync-LfoL3EntityRulesFromL2 $db $L2Path $scopeId
        $result.PredicateRulesSynced = Sync-LfoL3PredicateRulesFromL2 $db $L2Path $scopeId

        $facts = @(Get-LfoL3FactsTouchedAtTurn $L2Path $scopeId $TurnId)
        $result.L2FactsTouched = $facts.Count

        $classification = Get-LfoL3Classification $db $Prompt
        if ($classification.Status -eq 'ok') {
            $turnItem = Set-LfoL3Item $db $scopeId 'L0' ("turn:$TurnId") $TurnId $null
            $result.FacetsWritten += Add-LfoL3ClassificationToItem $db $turnItem.id $classification
            $result.TurnIndexed = $true
        }

        foreach ($fact in $facts) {
            $item = Set-LfoL3Item $db $scopeId 'L2' ("fact:$([int64]$fact.id)") ([int64]$fact.source_turn) $null

            $subjectKey = 'l2:' + [string][int64]$fact.subject_entity_id
            [void](Set-LfoL3Facet $db $item.id 'entity' $subjectKey 1 'l3-l2-fact-v1')
            $result.FacetsWritten++

            if ($null -ne $fact.object_entity_id) {
                $objectKey = 'l2:' + [string][int64]$fact.object_entity_id
                [void](Set-LfoL3Facet $db $item.id 'entity' $objectKey 1 'l3-l2-fact-v1')
                $result.FacetsWritten++
            }

            [void](Set-LfoL3ExclusiveFacet $db $item.id 'predicate' ([string]$fact.predicate) 1 'l3-l2-predicate-v1')
            $result.FacetsWritten++

            if ($classification.Status -eq 'ok') {
                $result.FacetsWritten += Add-LfoL3TurnFacetsToItem $db $item.id $classification
            }

            if ([int]$fact.is_current -eq 1) {
                [void](Set-LfoL3ExclusiveFacet $db $item.id 'temporal' 'current' 1 'l3-l2-temporal-v1')
                Remove-LfoL3Facet $db $item.id 'retrieval' 'exclude'
            } else {
                [void](Set-LfoL3ExclusiveFacet $db $item.id 'temporal' 'historical' 1 'l3-l2-temporal-v1')
                [void](Set-LfoL3Facet $db $item.id 'retrieval' 'exclude' 1 'l3-l2-temporal-v1')
            }
            $result.FacetsWritten++
            $result.L2ItemsIndexed++
        }

        $result.Status = 'ok'
        return [pscustomobject]$result
    } catch {
        $result.Status = 'failed'
        $result.Error = $_.Exception.Message
        return [pscustomobject]$result
    } finally {
        if ($null -ne $db) {
            try { Close-LfoSqliteDatabase $db } catch {}
        }
    }
}
