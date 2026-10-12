# L3-R2 offline acceptance: bounded deterministic SQL-backed tagging.
# TEMP-only. No Ollama, network, production memory or Qwen runtime integration.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

foreach ($relative in @('src\LfoMemoryStore.ps1','src\LfoL3Store.ps1')) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $repoRoot $relative),
        [ref]$tokens,
        [ref]$errors
    )
    if (@($errors).Count -gt 0) {
        throw ("Syntax FAIL {0}: {1}" -f $relative, (($errors | ForEach-Object Message) -join '; '))
    }
}

. (Join-Path $repoRoot 'src\LfoMemoryStore.ps1')
. (Join-Path $repoRoot 'src\LfoL3Store.ps1')

$root = Join-Path $env:TEMP ('LFO-l3-r2-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Force -Path $root)
$dbPath = Join-Path $root 'l3-index.db'
$db = Open-LfoL3Store $dbPath

try {
    $rules = @(
        # Topics
        @('topic','lfo','LFO',100,'r2-topic-lfo'),
        @('topic','lfo','Local Frontier Orchestrator',120,'r2-topic-lfo'),
        @('topic','lfo','DEV5',90,'r2-topic-lfo'),
        @('topic','lfo','L3',80,'r2-topic-lfo'),
        @('topic','retrocomputing','retrocomputing',100,'r2-topic-retro'),
        @('topic','retrocomputing','Amiga',90,'r2-topic-retro'),
        @('topic','retrocomputing','Atari',90,'r2-topic-retro'),
        @('topic','retrocomputing','Kickstart',80,'r2-topic-retro'),
        @('topic','teaching','Science Technology and Humanity',100,'r2-topic-teaching'),
        @('topic','teaching','STH',90,'r2-topic-teaching'),
        @('topic','teaching','course',20,'r2-topic-teaching'),

        # Entities
        @('entity','orion','ORION',100,'r2-entity-orion'),
        @('entity','l3','L3',100,'r2-entity-l3'),
        @('entity','amiga1200','Amiga 1200',120,'r2-entity-amiga1200'),
        @('entity','amiga1200','A1200',100,'r2-entity-amiga1200'),

        # Functional kind
        @('kind','decision','decided',100,'r2-kind-decision'),
        @('kind','decision','decision',90,'r2-kind-decision'),
        @('kind','decision','agreed',100,'r2-kind-decision'),
        @('kind','decision','rejected',100,'r2-kind-decision'),
        @('kind','decision','rozhodli sme',110,'r2-kind-decision'),
        @('kind','configuration','configuration',100,'r2-kind-config'),
        @('kind','configuration','configured',100,'r2-kind-config'),
        @('kind','configuration','OS',80,'r2-kind-config'),
        @('kind','configuration','runs',80,'r2-kind-config'),
        @('kind','configuration','run',70,'r2-kind-config'),
        @('kind','configuration','uses',70,'r2-kind-config'),
        @('kind','configuration','používa',80,'r2-kind-config'),
        @('kind','result','passed',100,'r2-kind-result'),
        @('kind','result','failed',100,'r2-kind-result'),
        @('kind','result','PASS',90,'r2-kind-result'),
        @('kind','result','FAIL',90,'r2-kind-result'),
        @('kind','preference','prefer',100,'r2-kind-preference'),
        @('kind','preference','radšej',100,'r2-kind-preference')
    )
    foreach ($r in $rules) {
        Set-LfoL3TermRule $db $r[0] $r[1] $r[2] ([int]$r[3]) $r[4] $true
    }

    $cases = @(
        [pscustomobject]@{ Text='For LFO, what OS does ORION run?'; Topics=@('lfo'); Entities=@('orion'); Kind='configuration' },
        [pscustomobject]@{ Text='We decided to keep DEV5 A+B in LFO.'; Topics=@('lfo'); Entities=@(); Kind='decision' },
        [pscustomobject]@{ Text='Amiga 1200 Kickstart configuration'; Topics=@('retrocomputing'); Entities=@('amiga1200'); Kind='configuration' },
        [pscustomobject]@{ Text='The Atari benchmark passed.'; Topics=@('retrocomputing'); Entities=@(); Kind='result' },
        [pscustomobject]@{ Text='I prefer the LFO SQL path.'; Topics=@('lfo'); Entities=@(); Kind='preference' },
        [pscustomobject]@{ Text='What was discussed yesterday?'; Topics=@(); Entities=@(); Kind=$null },
        [pscustomobject]@{ Text='Compare LFO with the Amiga 1200 approach.'; Topics=@('lfo','retrocomputing'); Entities=@('amiga1200'); Kind=$null },
        [pscustomobject]@{ Text='ORION failed the LFO benchmark.'; Topics=@('lfo'); Entities=@('orion'); Kind='result' },
        [pscustomobject]@{ Text='ORION používa nový OS v LFO.'; Topics=@('lfo'); Entities=@('orion'); Kind='configuration' },
        [pscustomobject]@{ Text='LFO, Amiga and the STH course are separate areas.'; Topics=@('lfo','retrocomputing'); Entities=@(); Kind=$null }
    )

    $tp = 0
    $fp = 0
    $fn = 0
    $casePass = 0
    $maxFacetCount = 0

    foreach ($case in $cases) {
        $c = Get-LfoL3Classification $db $case.Text
        $actualTopics = @($c.Topics | ForEach-Object { $_.ValueKey })
        $actualEntities = @($c.Entities | ForEach-Object { $_.ValueKey })
        $actualKind = if ($null -eq $c.Kind) { $null } else { [string]$c.Kind.ValueKey }

        $expectedSet = @{}
        foreach ($v in @($case.Topics)) { $expectedSet['topic:' + $v] = $true }
        foreach ($v in @($case.Entities)) { $expectedSet['entity:' + $v] = $true }
        if ($null -ne $case.Kind) { $expectedSet['kind:' + $case.Kind] = $true }

        $actualSet = @{}
        foreach ($v in $actualTopics) { $actualSet['topic:' + $v] = $true }
        foreach ($v in $actualEntities) { $actualSet['entity:' + $v] = $true }
        if ($null -ne $actualKind) { $actualSet['kind:' + $actualKind] = $true }

        foreach ($k in $actualSet.Keys) {
            if ($expectedSet.ContainsKey($k)) { $tp++ } else { $fp++ }
        }
        foreach ($k in $expectedSet.Keys) {
            if (-not $actualSet.ContainsKey($k)) { $fn++ }
        }

        $sameTopics = (@($actualTopics) -join '|') -ceq (@($case.Topics) -join '|')
        $sameEntities = (@($actualEntities) -join '|') -ceq (@($case.Entities) -join '|')
        $sameKind = ([string]$actualKind) -ceq ([string]$case.Kind)
        if (-not ($sameTopics -and $sameEntities -and $sameKind)) {
            throw ("R2 classification mismatch: text='{0}' topics={1} entities={2} kind={3}" -f
                $case.Text,($actualTopics -join ','),($actualEntities -join ','),$actualKind)
        }

        if ($c.Topics.Count -gt 2 -or $c.Entities.Count -gt 3 -or @($c.Facets).Count -gt 6 -or $c.QueryKeys -gt 96) {
            throw 'R2 bounded-classification invariant failed.'
        }
        $maxFacetCount = [Math]::Max($maxFacetCount, @($c.Facets).Count)
        $casePass++
    }

    if ($tp -le 0 -or $fp -ne 0 -or $fn -ne 0 -or $casePass -ne $cases.Count) {
        throw ("R2 corpus metrics failed: tp={0}, fp={1}, fn={2}, passed={3}/{4}" -f $tp,$fp,$fn,$casePass,$cases.Count)
    }

    # Predicate is an independent bounded dimension.
    Set-LfoL3TermRule $db 'predicate' 'ram_gb' 'RAM' 100 'r2-predicate-ram' $true
    Set-LfoL3TermRule $db 'predicate' 'cpu_count' 'CPU count' 120 'r2-predicate-cpu' $true
    $predicateClass = Get-LfoL3Classification $db 'For ORION, what are the RAM and CPU count?'
    $predicateKeys = @($predicateClass.Predicates | ForEach-Object { $_.ValueKey })
    if ((@($predicateKeys) -join '|') -cne 'cpu_count|ram_gb' -and
        (@($predicateKeys) -join '|') -cne 'ram_gb|cpu_count') {
        throw ('R2 predicate dimension mismatch: ' + ($predicateKeys -join ','))
    }
    if ($predicateClass.Predicates.Count -gt 4) { throw 'R2 predicate bound exceeded.' }

    # Disabled rules must disappear without creating a negative tag.
    Set-LfoL3TermRule $db 'topic' 'teaching' 'STH' 90 'r2-topic-teaching' $false
    $disabled = Get-LfoL3Classification $db 'STH'
    if ($disabled.Topics.Count -ne 0) { throw 'Inactive L3 term rule still matched.' }

    # Persist one classification: only the bounded matched facets enter L3.
    $item = Set-LfoL3Item $db 'conversation:1' 'L0' 'turn:200' 200 'sha256:r2'
    $class = Get-LfoL3Classification $db 'For LFO, what OS does ORION run?'
    $written = Add-LfoL3ClassificationToItem $db $item.id $class
    $facets = @(Get-LfoL3Facets $db $item.id)
    if ($written -ne 3 -or $facets.Count -ne 3) {
        throw ("Persisted R2 facet count failed: written={0}, stored={1}" -f $written,$facets.Count)
    }
    if (@($facets | Where-Object { $_.polarity -ne 1 }).Count -ne 0) {
        throw 'Automatic R2 tagging wrote non-positive facets.'
    }

    $termCount = @(Invoke-LfoSqliteQuery $db 'SELECT COUNT(*) AS n FROM l3_terms WHERE active=1;')
    $schema = @(Invoke-LfoSqliteQuery $db "SELECT value FROM l3_meta WHERE key='schema_version';")
    if ($schema[0].value -ne '3') { throw 'R2 expected L3 schema version 3.' }

    [pscustomobject]@{
        PASS = $true
        SchemaVersion = 3
        CorpusCases = $cases.Count
        ExactCases = $casePass
        TruePositiveFacets = $tp
        FalsePositiveFacets = $fp
        FalseNegativeFacets = $fn
        MaxModelInvisibleFacetsPerCase = $maxFacetCount
        QueryKeyCap = 96
        TopicCap = 2
        EntityCap = 3
        KindCap = 1
        ActiveRules = [int64]$termCount[0].n
        PersistedFacetCount = $facets.Count
        DisabledRuleSuppressed = $true
        ModelCalls = 0
        ProductionMemoryTouched = $false
        TempFixture = $root
    } | Format-List
} finally {
    Close-LfoSqliteDatabase $db
}
