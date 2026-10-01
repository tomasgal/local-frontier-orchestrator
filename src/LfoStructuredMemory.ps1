# v9.4 L2 structured-memory operation contract.
# Storage-independent: Qwen emits operations; wrapper validates and later applies them.

function Get-LfoStructuredMemoryOperationSchema([int]$MaxOps = 6) {
    return @{
        type = 'array'
        maxItems = $MaxOps
        items = @{
            type = 'object'
            properties = @{
                op = @{
                    type = 'string'
                    enum = @('SET_ATTRIBUTE', 'ADD_RELATION')
                }
                subject = @{
                    type = 'string'
                    maxLength = 80
                }
                subject_type = @{
                    type = 'string'
                    maxLength = 40
                }
                predicate = @{
                    type = 'string'
                    pattern = '^[a-z][a-z0-9_]{0,47}$'
                }
                target = @{
                    type = 'string'
                    maxLength = 160
                }
                target_type = @{
                    type = 'string'
                    enum = @('text', 'integer', 'real', 'boolean', 'entity')
                }
                target_entity_type = @{
                    type = 'string'
                    maxLength = 40
                }
            }
            required = @(
                'op',
                'subject',
                'subject_type',
                'predicate',
                'target',
                'target_type',
                'target_entity_type'
            )
            additionalProperties = $false
        }
    }
}

function ConvertFrom-LfoStructuredMemoryOps($RawOps, [int]$MaxOps = 6) {
    $valid = @()
    $rejected = @()

    if ($null -eq $RawOps) {
        return [pscustomobject]@{
            Valid = @()
            Rejected = @()
        }
    }

    $items = @($RawOps)
    if ($items.Count -gt $MaxOps) {
        $rejected += [pscustomobject]@{
            Reason = 'too-many-operations'
            Raw = $null
        }
        $items = @($items | Select-Object -First $MaxOps)
    }

    foreach ($item in $items) {
        try {
            $op = ([string]$item.op).Trim().ToUpperInvariant()
            $subject = ([string]$item.subject).Trim()
            $subjectType = ([string]$item.subject_type).Trim().ToLowerInvariant()
            $predicate = ([string]$item.predicate).Trim().ToLowerInvariant()
            $target = ([string]$item.target).Trim()
            $targetType = ([string]$item.target_type).Trim().ToLowerInvariant()
            $targetEntityType = ([string]$item.target_entity_type).Trim().ToLowerInvariant()

            if ($op -notin @('SET_ATTRIBUTE', 'ADD_RELATION')) {
                throw "unsupported op '$op'"
            }
            if ([string]::IsNullOrWhiteSpace($subject)) {
                throw 'empty subject'
            }
            if ($predicate -notmatch '^[a-z][a-z0-9_]{0,47}$') {
                throw "invalid predicate '$predicate'"
            }
            if ([string]::IsNullOrWhiteSpace($target)) {
                throw 'empty target'
            }
            if ($targetType -notin @('text', 'integer', 'real', 'boolean', 'entity')) {
                throw "invalid target_type '$targetType'"
            }

            if ($op -eq 'ADD_RELATION' -and $targetType -ne 'entity') {
                throw 'ADD_RELATION requires target_type=entity'
            }
            if ($op -eq 'SET_ATTRIBUTE' -and $targetType -eq 'entity') {
                throw 'SET_ATTRIBUTE cannot use target_type=entity'
            }

            $typedValue = $target
            switch ($targetType) {
                'integer' {
                    $parsed = [int64]0
                    if (-not [int64]::TryParse(
                        $target,
                        [Globalization.NumberStyles]::Integer,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$parsed)) {
                        throw "invalid integer '$target'"
                    }
                    $typedValue = $parsed
                }
                'real' {
                    $parsed = [double]0
                    if (-not [double]::TryParse(
                        $target,
                        [Globalization.NumberStyles]::Float,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$parsed)) {
                        throw "invalid real '$target'"
                    }
                    $typedValue = $parsed
                }
                'boolean' {
                    if ($target -match '^(?i:true)$') {
                        $typedValue = $true
                    } elseif ($target -match '^(?i:false)$') {
                        $typedValue = $false
                    } else {
                        throw "invalid boolean '$target'"
                    }
                }
            }

            $valid += [pscustomobject]@{
                Op = $op
                Subject = $subject
                SubjectType = $subjectType
                Predicate = $predicate
                Target = $target
                TargetType = $targetType
                TargetEntityType = $targetEntityType
                TypedValue = $typedValue
            }
        } catch {
            $rejected += [pscustomobject]@{
                Reason = $_.Exception.Message
                Raw = $item
            }
        }
    }

    return [pscustomobject]@{
        Valid = @($valid)
        Rejected = @($rejected)
    }
}
