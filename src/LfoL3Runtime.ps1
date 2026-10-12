# L3 read-side runtime adapter.
# Resolves L3 source references back to L0/L2 evidence without exposing L3 metadata.

function Get-LfoL3RuntimeBoundedText([string]$Text, [int]$MaxChars) {
    if ([string]::IsNullOrWhiteSpace($Text) -or $MaxChars -le 0) { return '' }
    $clean = [regex]::Replace($Text.Trim(), '\s+', ' ')
    if ($clean.Length -le $MaxChars) { return $clean }
    if ($MaxChars -lt 16) { return $clean.Substring(0, $MaxChars) }
    $marker = ' ... '
    $head = [Math]::Max(1, [int](($MaxChars - $marker.Length) * 0.62))
    $tail = $MaxChars - $marker.Length - $head
    return $clean.Substring(0, $head) + $marker + $clean.Substring($clean.Length - $tail)
}

function Format-LfoL3RuntimeL2Fact($Fact) {
    if ($null -ne $Fact.object_entity_id) {
        $value = '-> ' + [string]$Fact.object_name
    } else {
        $value = switch ([string]$Fact.literal_type) {
            'integer' { [string]$Fact.value_integer }
            'boolean' { if ([int64]$Fact.value_integer -eq 0) { 'false' } else { 'true' } }
            'real' { ([double]$Fact.value_real).ToString('G', [Globalization.CultureInfo]::InvariantCulture) }
            default { [string]$Fact.value_text }
        }
    }
    return ('{0}.{1} = {2} [scope={3}; source_turn={4}]' -f
        [string]$Fact.subject_name,[string]$Fact.predicate,$value,
        [string]$Fact.scope_id,[string]$Fact.source_turn)
}

function Get-LfoL3RuntimeL0Evidence(
    [object[]]$Candidates,
    [string]$LogDir,
    [int]$Epoch,
    $L3Connection = $null
) {
    $l0Candidates = @($Candidates | Where-Object { $_.SourceLayer -eq 'L0' })
    if ($l0Candidates.Count -eq 0 -or -not (Test-Path -LiteralPath $LogDir -PathType Container)) {
        return @()
    }

    $locatorByItem = @{}
    if ($null -ne $L3Connection -and
        $null -ne (Get-Command Get-LfoL3L0Locators -ErrorAction SilentlyContinue)) {
        $itemIds = @($l0Candidates | ForEach-Object { [int64]$_.Id } | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
        foreach ($loc in @(Get-LfoL3L0Locators $L3Connection $itemIds)) {
            $locatorByItem[[string][int64]$loc.item_id] = $loc
        }
    }

    $out = @()
    $wanted = @{}
    $utf8Strict = New-Object System.Text.UTF8Encoding($false,$true)

    foreach ($candidate in $l0Candidates) {
        $ref = [string]$candidate.SourceRef
        if ($ref -notmatch '^turn:(\d+)$') { continue }
        $turnId = [int64]$matches[1]
        $resolved = $false
        $locKey = [string][int64]$candidate.Id

        if ($locatorByItem.ContainsKey($locKey)) {
            $loc = $locatorByItem[$locKey]
            $rawFile = [string]$loc.source_file
            $fileName = [IO.Path]::GetFileName($rawFile)
            $offset = [int64]$loc.byte_offset
            $length = [int64]$loc.byte_length
            if (-not [string]::IsNullOrWhiteSpace($fileName) -and
                $rawFile -ceq $fileName -and
                $offset -ge 0 -and $length -gt 0 -and $length -le 1048576) {
                $path = Join-Path $LogDir $fileName
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    $info = Get-Item -LiteralPath $path
                    if (($offset + $length) -le [int64]$info.Length) {
                        $stream = $null
                        try {
                            $stream = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                            [void]$stream.Seek($offset,[IO.SeekOrigin]::Begin)
                            $bytes = New-Object byte[] ([int]$length)
                            $read = 0
                            while ($read -lt $bytes.Length) {
                                $n = $stream.Read($bytes,$read,$bytes.Length-$read)
                                if ($n -le 0) { break }
                                $read += $n
                            }
                            if ($read -eq $bytes.Length) {
                                $line = $utf8Strict.GetString($bytes).TrimEnd([char[]]@([char]13,[char]10))
                                $row = $line | ConvertFrom-Json -ErrorAction Stop
                                if ([string]$row.event -eq 'turn' -and
                                    [int]$row.epoch -eq $Epoch -and
                                    [int64]$row.turn_id -eq $turnId) {
                                    $u = Get-LfoL3RuntimeBoundedText ([string]$row.user) 620
                                    $a = Get-LfoL3RuntimeBoundedText ([string]$row.assistant) 360
                                    $out += [pscustomobject]@{
                                        SourceLayer = 'L0'
                                        SourceRef = $ref
                                        Text = ("T{0} U:{1} A:{2}" -f $turnId,$u,$a)
                                    }
                                    $resolved = $true
                                }
                            }
                        } catch {
                            $resolved = $false
                        } finally {
                            if ($null -ne $stream) { $stream.Dispose() }
                        }
                    }
                }
            }
        }

        if (-not $resolved) {
            $wanted[$turnId] = $ref
        }
    }

    if ($wanted.Count -eq 0) { return @($out) }

    # Compatibility/correctness fallback for pre-v4 indexes, stale locators,
    # moved/edited logs, or any locator validation failure.
    $files = @(Get-ChildItem -LiteralPath $LogDir -Filter 'conversation-*.jsonl' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    foreach ($file in $files) {
        foreach ($line in (Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $row = $line | ConvertFrom-Json } catch { continue }
            if ([string]$row.event -ne 'turn' -or [int]$row.epoch -ne $Epoch) { continue }
            $turnId = [int64]$row.turn_id
            if (-not $wanted.ContainsKey($turnId)) { continue }

            $u = Get-LfoL3RuntimeBoundedText ([string]$row.user) 620
            $a = Get-LfoL3RuntimeBoundedText ([string]$row.assistant) 360
            $out += [pscustomobject]@{
                SourceLayer = 'L0'
                SourceRef = [string]$wanted[$turnId]
                Text = ("T{0} U:{1} A:{2}" -f $turnId,$u,$a)
            }
            [void]$wanted.Remove($turnId)
            if ($wanted.Count -eq 0) { break }
        }
        if ($wanted.Count -eq 0) { break }
    }
    return @($out)
}

function Get-LfoL3RuntimeL2Evidence(
    [object[]]$Candidates,
    [string]$L2Path,
    [string]$ScopeId
) {
    $ids = @()
    $refs = @{}
    foreach ($candidate in @($Candidates | Where-Object { $_.SourceLayer -eq 'L2' })) {
        if ([string]$candidate.SourceRef -match '^fact:(\d+)$') {
            $id = [int64]$matches[1]
            if ($ids -notcontains $id) { $ids += $id }
            $refs[$id] = [string]$candidate.SourceRef
        }
    }
    if ($ids.Count -eq 0 -or -not (Test-Path -LiteralPath $L2Path -PathType Leaf)) {
        return @()
    }

    $reader = $null
    try {
        $reader = Open-LfoMemoryReadOnly $L2Path
        if ($null -eq $reader) { return @() }
        $placeholders = (1..$ids.Count | ForEach-Object { '?' + ($_ + 1) }) -join ','
        $sql = @"
SELECT f.id, f.source_turn, f.scope_id, f.predicate, f.literal_type,
       f.value_text, f.value_integer, f.value_real, f.object_entity_id,
       (SELECT n.name FROM entity_names n WHERE n.entity_id=f.subject_entity_id ORDER BY n.id LIMIT 1) AS subject_name,
       (SELECT n.name FROM entity_names n WHERE n.entity_id=f.object_entity_id ORDER BY n.id LIMIT 1) AS object_name
FROM current_facts f
WHERE f.scope_id = ?1
  AND f.id IN ($placeholders)
ORDER BY f.source_turn DESC, f.id DESC;
"@
        $params = [object[]](@($ScopeId) + @($ids))
        $rows = @(Invoke-LfoSqliteQuery $reader $sql $params)
        $out = @()
        foreach ($row in $rows) {
            $id = [int64]$row.id
            $out += [pscustomobject]@{
                SourceLayer = 'L2'
                SourceRef = [string]$refs[$id]
                Text = Format-LfoL3RuntimeL2Fact $row
            }
        }
        return @($out)
    } finally {
        if ($null -ne $reader) { Close-LfoSqliteDatabase $reader }
    }
}

function Get-LfoL3RuntimeContextPlan(
    [string]$Query,
    [string]$ScopeId,
    [string]$L3Path,
    [string]$L2Path,
    [string]$LogDir,
    [int]$Epoch,
    [int]$MaxItems = 3,
    [int]$MaxChars = 1200
) {
    $empty = [pscustomobject]@{
        Status = 'disabled'
        L0Text = ''
        L2Text = ''
        L0Count = 0
        L2Count = 0
        PacketChars = 0
        CandidateCount = 0
        SelectedCount = 0
        DroppedChars = 0
        DuplicateDrops = 0
        Error = $null
    }
    if ([string]::IsNullOrWhiteSpace($Query) -or
        [string]::IsNullOrWhiteSpace($ScopeId) -or
        -not (Test-Path -LiteralPath $L3Path -PathType Leaf)) {
        $empty.Status = 'missing_or_empty'
        return $empty
    }

    $connection = $null
    try {
        $connection = Open-LfoL3ReadOnly $L3Path
        if ($null -eq $connection) {
            $empty.Status = 'missing_db'
            return $empty
        }

        $classification = Get-LfoL3Classification $connection $Query
        if ($classification.Status -ne 'ok') {
            $empty.Status = 'no_query_facets'
            return $empty
        }

        $candidates = @(Get-LfoL3CandidateItems $connection $ScopeId $classification 48)
        if ($candidates.Count -eq 0) {
            $empty.Status = 'no_candidates'
            return $empty
        }

        $evidence = @()
        $evidence += @(Get-LfoL3RuntimeL0Evidence $candidates $LogDir $Epoch $connection)
        $evidence += @(Get-LfoL3RuntimeL2Evidence $candidates $L2Path $ScopeId)

        $plan = New-LfoL3ContextPlan $connection $ScopeId $Query $classification $evidence $MaxItems $MaxChars
        if ($plan.Status -ne 'ok') {
            $empty.Status = [string]$plan.Status
            $empty.CandidateCount = [int]$plan.CandidateCount
            return $empty
        }

        $l0 = @($plan.Selected | Where-Object { $_.SourceLayer -eq 'L0' })
        $l2 = @($plan.Selected | Where-Object { $_.SourceLayer -eq 'L2' })
        return [pscustomobject]@{
            Status = 'ok'
            L0Text = (($l0 | ForEach-Object { [string]$_.Text }) -join [Environment]::NewLine)
            L2Text = (($l2 | ForEach-Object { [string]$_.Text }) -join [Environment]::NewLine)
            L0Count = $l0.Count
            L2Count = $l2.Count
            PacketChars = [int]$plan.PacketChars
            CandidateCount = [int]$plan.CandidateCount
            SelectedCount = [int]$plan.SelectedCount
            DroppedChars = [int]$plan.DroppedChars
            DuplicateDrops = [int]$plan.DuplicateDrops
            Error = $null
        }
    } catch {
        return [pscustomobject]@{
            Status = 'failed'
            L0Text = ''
            L2Text = ''
            L0Count = 0
            L2Count = 0
            PacketChars = 0
            CandidateCount = 0
            SelectedCount = 0
            DroppedChars = 0
            DuplicateDrops = 0
            Error = $_.Exception.Message
        }
    } finally {
        if ($null -ne $connection) {
            try { Close-LfoSqliteDatabase $connection } catch {}
        }
    }
}
