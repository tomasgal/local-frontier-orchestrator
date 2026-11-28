# Research-only CPU runtime witness. No text classification, I/O or model calls.
# Envelope completeness and claim binding are explicit caller attestations, not model data.
function Resolve-LfoG2RuntimeProvenance {
    [CmdletBinding()]
    param($Runtime,$Claim,[switch]$TrustedRuntime,[switch]$TrustedBinding)
    $out=[ordered]@{contract='g2-runtime-provenance-v1';state='UNKNOWN';reason='UNVERIFIED_RUNTIME';matched_events=@();scope='Only the asserted successful operation in the bound turn, actor and target; no verification of substantive claims or external facts.'}
    if(-not $TrustedRuntime){return [pscustomobject]$out}
    if(-not $TrustedBinding){$out.reason='UNVERIFIED_CLAIM_BINDING';return [pscustomobject]$out}
    try{
        if($null -eq $Runtime -or $Runtime.turn_id -isnot [string] -or [string]::IsNullOrWhiteSpace($Runtime.turn_id) -or $Runtime.complete -isnot [bool] -or $null -eq $Runtime.events){throw 'Invalid runtime envelope'}
        $ids=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($e in $Runtime.events){
            foreach($k in @('event_id','turn_id','actor','operation','target')){
                if($e.$k -isnot [string] -or [string]::IsNullOrWhiteSpace($e.$k)){throw ('Invalid event '+$k)}
            }
            if($e.turn_id -cne $Runtime.turn_id -or -not $ids.Add($e.event_id) -or $e.status -cnotin @('SUCCEEDED','FAILED','PENDING')){throw 'Invalid event identity or status'}
            if($e.status -ceq 'SUCCEEDED' -and ($e.receipt_ref -isnot [string] -or [string]::IsNullOrWhiteSpace($e.receipt_ref))){throw 'Successful event missing receipt reference'}
        }
        if($null -eq $Claim -or $Claim.kind -cnotin @('SUCCESS_ASSERTION','NOT_APPLICABLE','UNKNOWN')){throw 'Invalid claim kind'}
        if($Claim.kind -ceq 'NOT_APPLICABLE'){$out.state='NOT_APPLICABLE';$out.reason='NO_CURRENT_SUCCESS_ASSERTION';return [pscustomobject]$out}
        if($Claim.kind -ceq 'UNKNOWN'){$out.reason='UNRESOLVED_CLAIM';return [pscustomobject]$out}
        foreach($k in @('turn_id','actor','operation','target')){
            if($Claim.$k -isnot [string] -or [string]::IsNullOrWhiteSpace($Claim.$k)){throw ('Invalid claim '+$k)}
        }
        if($Claim.turn_id -cne $Runtime.turn_id){$out.reason='TURN_SCOPE_MISMATCH';return [pscustomobject]$out}
        $matches=@($Runtime.events|Where-Object {$_.actor -ceq $Claim.actor -and $_.operation -ceq $Claim.operation -and $_.target -ceq $Claim.target})
        $out.matched_events=@(foreach($e in $matches){[ordered]@{event_id=$e.event_id;status=$e.status;receipt_ref=$e.receipt_ref}})
        if(@($matches|Where-Object status -ceq 'SUCCEEDED').Count -gt 0){$out.state='SUPPORTED_OPERATION';$out.reason='MATCHED_SUCCESS_RECEIPT';return [pscustomobject]$out}
        if(@($matches|Where-Object status -ceq 'PENDING').Count -gt 0){$out.reason='OPERATION_PENDING';return [pscustomobject]$out}
        if(-not $Runtime.complete){$out.reason='INCOMPLETE_RUNTIME_COVERAGE';return [pscustomobject]$out}
        $out.state='CONTRADICTED';$out.reason='NO_MATCHED_SUCCESS_IN_COMPLETE_RUNTIME'
    }catch{
        $out.state='INVALID';$out.reason=$_.Exception.Message;$out.matched_events=@()
    }
    return [pscustomobject]$out
}
