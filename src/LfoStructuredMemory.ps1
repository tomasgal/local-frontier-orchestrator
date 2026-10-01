# v9.4 L2 structured-memory operation contract.
# Storage-independent: Qwen emits operations; wrapper validates and later applies them.
#
# Small-model rule: scalar type is encoded directly in the operation name.
# This intentionally avoids a second, potentially contradictory target_type field.

function Get-LfoStructuredMemoryOperationSchema([int]$MaxOps = 6) {
    return @{
        type = 'array'
        maxItems = $MaxOps
        items = @{
            type = 'object'
            properties = @{
                op = @{
                    type = 'string'
                    enum = @(
                        'SET_TEXT',
                        'SET_INTEGER',
                        'SET_REAL',
                        'SET_BOOLEAN',
                        'ADD_RELATION'
                    )
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
            $targetEntityType = ([string]$item.target_entity_type).Trim().ToLowerInvariant()

            if ($op -notin @(
                'SET_TEXT',
                'SET_INTEGER',
                'SET_REAL',
                'SET_BOOLEAN',
                'ADD_RELATION'
            )) {
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

            $targetType = switch ($op) {
                'SET_TEXT'    { 'text' }
                'SET_INTEGER' { 'integer' }
                'SET_REAL'    { 'real' }
                'SET_BOOLEAN' { 'boolean' }
                'ADD_RELATION'{ 'entity' }
            }

            if ($op -ne 'ADD_RELATION' -and -not [string]::IsNullOrWhiteSpace($targetEntityType)) {
                throw "$op requires empty target_entity_type"
            }

            $typedValue = $target
            switch ($op) {
                'SET_INTEGER' {
                    if ($target -notmatch '^-?\d+$') {
                        throw "invalid integer lexical form '$target'"
                    }
                    $parsed = [int64]0
                    if (-not [int64]::TryParse(
                        $target,
                        [Globalization.NumberStyles]::Integer,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$parsed)) {
                        throw "integer out of range '$target'"
                    }
                    $typedValue = $parsed
                }
                'SET_REAL' {
                    if ($target -notmatch '^-?(?:\d+\.\d+|\d+|\.\d+)$') {
                        throw "invalid real lexical form '$target'"
                    }
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
                'SET_BOOLEAN' {
                    if ($target -ceq 'true') {
                        $typedValue = $true
                    } elseif ($target -ceq 'false') {
                        $typedValue = $false
                    } else {
                        throw "invalid boolean lexical form '$target'"
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
