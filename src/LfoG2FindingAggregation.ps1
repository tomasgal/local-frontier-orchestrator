# CES-C09: research-only aggregation of typed, scope-bound findings.
# No inference, I/O, automatic revision or promotion. Confidence is not aggregated.
# VERIFIED means a bound invariant was verified by the trusted caller, not world truth.
function Merge-LfoG2Findings {
    [CmdletBinding()]
    param([string]$ScopeId,[object[]]$Findings=@(),[switch]$TrustedEnvelope)
    $out=[ordered]@{contract='g2-findings-v1';state='ABSTAIN';reason='UNTRUSTED_ENVELOPE';groups=@();duplicate_count=0;input_count=$Findings.Count}
    if(-not $TrustedEnvelope){return [pscustomobject]$out}
    if([string]::IsNullOrWhiteSpace($ScopeId)){$out.reason='MISSING_SCOPE';return [pscustomobject]$out}
    try{
        $groups=New-Object 'System.Collections.Generic.List[object]'
        $unique=New-Object 'System.Collections.Generic.List[object]'
        foreach($f in $Findings){
            if($null -eq $f){throw 'Null finding'}
            foreach($k in @('scope_id','target_ref','invariant','source_ref','producer','version')){
                if($f.$k -isnot [string] -or [string]::IsNullOrWhiteSpace($f.$k)){throw ('Missing finding '+$k)}
            }
            if($f.scope_id -cne $ScopeId){throw 'Scope mismatch'}
            if($f.state -cnotin @('CONTRADICTED','SUPPORTED','UNKNOWN','NOT_APPLICABLE') -or $f.status -cnotin @('VERIFIED','PROVISIONAL')){throw 'Invalid finding state/status'}
            # A provisional semantic observation cannot make an invariant verified.
            $row=[pscustomobject][ordered]@{scope_id=$ScopeId;target_ref=$f.target_ref;invariant=$f.invariant;source_ref=$f.source_ref;producer=$f.producer;version=$f.version;state=$f.state;status=$f.status}
            $same=@($unique|Where-Object {$_.target_ref -ceq $row.target_ref -and $_.invariant -ceq $row.invariant -and $_.source_ref -ceq $row.source_ref -and $_.producer -ceq $row.producer -and $_.version -ceq $row.version -and $_.state -ceq $row.state -and $_.status -ceq $row.status})
            if($same.Count -gt 0){$out.duplicate_count++;continue}
            $unique.Add($row)
            $matches=@($groups|Where-Object {$_.target_ref -ceq $row.target_ref -and $_.invariant -ceq $row.invariant})
            if($matches.Count -eq 0){
                $g=[pscustomobject]@{target_ref=$row.target_ref;invariant=$row.invariant;findings=(New-Object 'System.Collections.Generic.List[object]')}
                $groups.Add($g)
            }else{$g=$matches[0]}
            $g.findings.Add($row)
        }
        $merged=New-Object 'System.Collections.Generic.List[object]'
        foreach($g in $groups){
            $rows=$g.findings.ToArray()
            $verified=@($rows|Where-Object status -ceq 'VERIFIED')
            $d=@($verified|Where-Object state -ceq 'CONTRADICTED').Count -gt 0
            $s=@($verified|Where-Object state -ceq 'SUPPORTED').Count -gt 0
            $na=@($verified|Where-Object state -ceq 'NOT_APPLICABLE').Count -gt 0
            $state='UNKNOWN';$reason='NO_VERIFIED_DECISION';$eligibility='INHIBIT'
            if(($d -and $s) -or ($na -and ($d -or $s))){
                $state='CONFLICT';$reason='INCOMPATIBLE_VERIFIED_FINDINGS'
            }elseif($na){
                $state='NOT_APPLICABLE';$reason='VERIFIED_SCOPE_EXCLUSION'
            }elseif($d){
                # Conflicting provisional evidence is retained but not given veto power.
                $state='CONTRADICTED';$reason='VERIFIED_BOUND_CONTRADICTION';$eligibility='REVIEW_FOR_INTERVENTION'
            }elseif($s){
                $state='SUPPORTED';$reason='VERIFIED_BOUND_SUPPORT'
            }
            $merged.Add([pscustomobject][ordered]@{target_ref=$g.target_ref;invariant=$g.invariant;state=$state;reason=$reason;eligibility=$eligibility;findings=$rows})
        }
        $out.groups=$merged.ToArray()
        $out.state='AGGREGATED';$out.reason='NO_AUTOMATIC_PROPAGATION'
    }catch{
        $out.state='ABSTAIN';$out.reason=$_.Exception.Message;$out.groups=@();$out.duplicate_count=0
    }
    return [pscustomobject]$out
}
