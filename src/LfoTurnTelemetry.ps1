# v9.4-dev4 phase-level telemetry. One bounded, in-memory list per turn.
# No extra model calls, database reads, files, or raw user content.

function Start-LfoTurnTelemetry {
    $script:LfoTurnPhases = New-Object 'System.Collections.Generic.List[object]'
}

function Add-LfoTurnPhase {
    param(
        [Parameter(Mandatory=$true)][string]$Phase,
        [Parameter(Mandatory=$true)][double]$WallSeconds,
        [string]$Kind = 'model',
        $Response = $null,
        [bool]$Success = $true,
        [Nullable[int]]$InputChars = $null
    )

    if ($null -eq $script:LfoTurnPhases) { return }

    $promptTokens = $null
    $generatedTokens = $null
    $prefill = $null
    $decode = $null
    $unattributed = $null

    if ($null -ne $Response) {
        if ($null -ne $Response.prompt_eval_count) {
            $promptTokens = [int64]$Response.prompt_eval_count
        }
        if ($null -ne $Response.eval_count) {
            $generatedTokens = [int64]$Response.eval_count
        }
        if ($null -ne $Response.prompt_eval_duration) {
            $prefill = [Math]::Round(([double]$Response.prompt_eval_duration / 1e9), 4)
        }
        if ($null -ne $Response.eval_duration) {
            $decode = [Math]::Round(([double]$Response.eval_duration / 1e9), 4)
        }
        if ($null -ne $prefill -and $null -ne $decode) {
            $unattributed = [Math]::Round($WallSeconds - $prefill - $decode, 4)
        }
    }

    [void]$script:LfoTurnPhases.Add([pscustomobject][ordered]@{
        phase = $Phase
        kind = $Kind
        success = $Success
        wall_seconds = [Math]::Round($WallSeconds, 4)
        prompt_eval_count = $promptTokens
        eval_count = $generatedTokens
        prompt_eval_seconds = $prefill
        decode_seconds = $decode
        other_seconds = $unattributed
        input_chars = $InputChars
    })
}

function Get-LfoTurnPhases {
    if ($null -eq $script:LfoTurnPhases) { return @() }
    return @($script:LfoTurnPhases.ToArray())
}
