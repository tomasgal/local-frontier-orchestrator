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
        streamed = $(if($null -ne $Response){[bool]$Response.lfo_streamed}else{$false})
        first_chunk_seconds = $(if($null -ne $Response -and $null -ne $Response.lfo_first_chunk_seconds){[Math]::Round([double]$Response.lfo_first_chunk_seconds,4)}else{$null})
        first_thinking_seconds = $(if($null -ne $Response -and $null -ne $Response.lfo_first_thinking_seconds){[Math]::Round([double]$Response.lfo_first_thinking_seconds,4)}else{$null})
        first_answer_seconds = $(if($null -ne $Response -and $null -ne $Response.lfo_first_answer_seconds){[Math]::Round([double]$Response.lfo_first_answer_seconds,4)}else{$null})
        first_visible_seconds = $(if($null -ne $Response -and $null -ne $Response.lfo_first_visible_seconds){[Math]::Round([double]$Response.lfo_first_visible_seconds,4)}else{$null})
    })
}

function Get-LfoTurnPhases {
    if ($null -eq $script:LfoTurnPhases) { return @() }
    return @($script:LfoTurnPhases.ToArray())
}


# Sum the answer-generation phases only. Memory work follows the visible
# answer and is deliberately excluded. Preserve legacy per-response metrics.
function Get-LfoAnswerGenerationTotals([object[]]$Phases){
    $modelPhases=@($Phases|Where-Object {$_.kind -eq 'model' -and $_.phase -in @('local_generation','answer_recovery','frontier_synthesis','g2_revision_1','g2_revision_2')})
    $prompt=[long]0;$generated=[long]0;$decode=[double]0
    $promptKnown=$true;$generatedKnown=$true;$decodeKnown=$true
    foreach($phase in $modelPhases){
        if($null -eq $phase.prompt_eval_count){$promptKnown=$false}else{$prompt+=[long]$phase.prompt_eval_count}
        if($null -eq $phase.eval_count){$generatedKnown=$false}else{$generated+=[long]$phase.eval_count}
        if($null -eq $phase.decode_seconds){$decodeKnown=$false}else{$decode+=[double]$phase.decode_seconds}
    }
    return [pscustomobject]@{
        calls=$modelPhases.Count
        prompt_tokens=$(if($promptKnown -and $modelPhases.Count){$prompt}else{$null})
        generated_tokens=$(if($generatedKnown -and $modelPhases.Count){$generated}else{$null})
        decode_tokens_per_second=$(if($generatedKnown -and $decodeKnown -and $decode -gt 0){[Math]::Round($generated/$decode,2)}else{$null})
    }
}
