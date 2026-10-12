# L3-LIVE2 pre-inference contract gate.
# Pure offline validation: accepts materialized baseline/L3 probes; never calls a model.
# Requires all five cases to pass before a LIVE2 inference runner is permitted.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ProbeJson,
    [switch]$PassThru
)
$ErrorActionPreference = 'Stop'
$expected = @('single_current','two_current','corrected_current','topic_l0','no_match')
if (-not (Test-Path -LiteralPath $ProbeJson -PathType Leaf)) { throw "Missing LIVE2 probes: $ProbeJson" }
$doc = Get-Content -LiteralPath $ProbeJson -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $doc -or @($doc.cases).Count -ne 5) { throw 'LIVE2 requires exactly five case probes.' }
if ([string]$doc.fixture_root -notmatch '(?i)(^|[\\/])temp([\\/]|$)|(?i)(^|[\\/])tmp([\\/]|$)') {
    throw 'LIVE2 fixture_root must be explicitly TEMP-only.'
}
if ($doc.production_memory_touched -ne $false -or [int]$doc.model_calls -ne 0) {
    throw 'LIVE2 preflight requires untouched production memory and zero model calls.'
}
$seen = @{}
foreach ($case in @($doc.cases)) {
    $id = [string]$case.id
    if ($expected -cnotcontains $id -or $seen.ContainsKey($id)) { throw "Unexpected/duplicate LIVE2 case: $id" }
    $seen[$id] = $true
    if ([string]::IsNullOrWhiteSpace([string]$case.query)) { throw "Missing query in $id" }
    $b = $case.baseline; $l = $case.l3
    if ($null -eq $b -or $null -eq $l) { throw "Missing paired probe: $id" }
    foreach ($p in @($b,$l)) {
        if ([string]$p.query -cne [string]$case.query) { throw "Variant query mismatch: $id" }
        if ([string]$p.model -cne [string]$doc.model) { throw "Model mismatch: $id" }
        if ([string]::IsNullOrWhiteSpace([string]$p.context)) { throw "Missing complete model-visible context: $id" }
        if ([int]$p.model_visible_chars -ne ([string]$p.context).Length) { throw "Context char count mismatch: $id" }
        if ([int]$p.model_calls -ne 0) { throw "Inference occurred before preflight: $id" }
    }
    if ($id -cin @('single_current','two_current','corrected_current') -and [string]$b.l2_status -cne 'ok') { throw "Invalid baseline retrieval: $id" }
    # L3 metadata are internal and must not appear in the model-visible packet.
    if ([string]$l.context -match '(?i)classifier_rule|content_fingerprint|retrieval_state|temporal_state|l3-l2-fact-v1|l3-topic-config-v1') {
        throw "L3 internal metadata leaked into context: $id"
    }
    switch ($id) {
        'single_current' {
            if (-not $l.l3_used -or [string]$l.l3_status -cne 'ok' -or
                [int]$l.l2_items -ne 1 -or [int]$b.l2_items -le 1) { throw 'Invalid single_current shape.' }
            if (@($l.predicate_keys).Count -ne 1 -or @($l.predicate_keys) -notcontains 'os') {
                throw 'single_current did not use the os predicate dimension.'
            }
        }
        'two_current' {
            if (-not $l.l3_used -or [string]$l.l3_status -cne 'ok' -or
                [int]$l.l2_items -ne 2 -or [int]$l.l0_items -ne 0 -or
                [int]$b.l2_items -lt 2) { throw 'Invalid two_current shape.' }
            if (@($l.predicate_keys).Count -ne 2 -or
                @($l.predicate_keys) -notcontains 'ram_gb' -or
                @($l.predicate_keys) -notcontains 'cpu_count') {
                throw 'two_current did not use ram_gb + cpu_count predicate dimensions.'
            }
        }
        'corrected_current' {
            if (-not $l.l3_used -or [string]$l.l3_status -cne 'ok' -or [int]$l.l2_items -lt 1) {
                throw 'Invalid corrected_current shape.'
            }
            if (@($l.predicate_keys).Count -ne 1 -or @($l.predicate_keys) -notcontains 'os') {
                throw 'corrected_current did not use the os predicate dimension.'
            }
            if ([string]::IsNullOrWhiteSpace([string]$case.historical_marker) -or
                [string]::IsNullOrWhiteSpace([string]$case.current_marker)) {
                throw 'Correction markers required.'
            }
            if (([string]$l.context).Contains([string]$case.historical_marker) -or
                -not (([string]$l.context).Contains([string]$case.current_marker))) {
                throw 'Historical leak or missing current fact.'
            }
        }
        'topic_l0' {
            if (-not $l.l3_used -or [string]$l.l3_status -cne 'ok' -or [int]$l.l0_items -lt 1) {
                throw 'L0 topic-only shape invalid.'
            }
            if ([int]$l.l2_items -ne 0) { throw 'Topic-only case unexpectedly selected L2.' }
        }
        'no_match' {
            if ($l.l3_used -or [string]$l.l3_status -cne 'no_query_facets' -or
                [string]$l.context -cne [string]$b.context -or
                [int]$l.model_visible_chars -ne [int]$b.model_visible_chars) {
                throw 'Exact no_query_facets baseline fallback violated.'
            }
        }
    }
    if ($id -cne 'no_match' -and [int]$l.model_visible_chars -gt [int]$b.model_visible_chars) {
        throw "L3 expanded model-visible context: $id"
    }
}
foreach ($id in $expected) { if (-not $seen.ContainsKey($id)) { throw "Missing LIVE2 case: $id" } }
$pass = [pscustomobject]@{ PASS=$true; Cases=5; Model=[string]$doc.model; ModelCalls=0; ProductionMemoryTouched=$false; Gate='L3-LIVE2 offline pre-inference' }
if ($PassThru) { $pass } else { $pass | Format-List }
