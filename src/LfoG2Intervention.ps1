# Bounded deterministic intervention policy. Detector absence is not proof of quality.
# Only E1 CURRENT_TURN + NONE has a sufficiently concrete runtime contradiction today.
function Get-LfoG2E1Check {
    param($Controller,[string]$Answer,[string]$Evidence)
    $out=[ordered]@{assessment='ABSTAIN';rule=$null;start=$null;length=$null}
    if($null -eq $Controller -or $Controller.Axes.E1 -eq 'OFF'){return [pscustomobject]$out}
    $m=$Controller.Modules['verification-claim']
    if($null -eq $m -or -not $m.Enabled){return [pscustomobject]$out}
    try{
        $r=@(& $m.Run ([pscustomobject]@{Text=$Answer;ExternalEvidence=$Evidence;Stage='FINAL';Route='LOCAL'}) $Controller.Axes.E1)
        if($r.Count -ne 1){throw 'E1 cardinality'}
        if($r[0] -is [string]){
            if($r[0] -cne 'ABSTAIN'){throw 'E1 contract'}
        }else{
            $d=$r[0]
            if($d.Assessment -cnotin @('CONTRADICTED','INSUFFICIENT_EVIDENCE') -or $d.Start -isnot [int] -or $d.Length -isnot [int] -or $d.Start -lt 0 -or $d.Length -lt 1 -or ([long]$d.Start+$d.Length) -gt $Answer.Length){throw 'E1 span contract'}
            $out.assessment=$d.Assessment;$out.rule=$d.RuleId;$out.start=$d.Start;$out.length=$d.Length
            if($out.assessment -eq 'CONTRADICTED' -and ($Evidence -cne 'NONE' -or $d.Scope -cne 'CURRENT_TURN')){throw 'E1 contradiction scope'}
        }
    }catch{$out.assessment='CHECK_FAILED'}
    [pscustomobject]$out
}
function Get-LfoG2SafeInline {
    param([string]$Answer,$Check)
    if($Check.assessment -ne 'CONTRADICTED'){return $null}
    $span=$Answer.Substring($Check.start,$Check.length)
    $t=ConvertTo-LfoG2NormalizedText $span
    # Deliberately narrow: a standalone claim of a lookup, with no factual clause.
    $en='^i (?:checked|searched|verified) (?:the )?(?:web|internet|online sources?) (?:in this turn|for this answer|in this response|just now)[.!]?$'
    $sk='^(?:overil|overila|skontroloval|skontrolovala|vyhladal|vyhladala) som (?:to )?(?:na internete|na webe|online) (?:v tomto turne|v tejto odpovedi|prave)[.!]?$'
    $replacement=$null
    if($t -match $en){$replacement='No external lookup was performed in this turn.'}
    elseif($t -match $sk){$replacement='V tejto odpovedi neprebehlo externe vyhladavanie.'}
    if(-not $replacement){return $null}
    $leading=[regex]::Match($span,'^\s*').Value
    return $Answer.Substring(0,$Check.start)+$leading+$replacement+$Answer.Substring($Check.start+$Check.length)
}
function Invoke-LfoG2InterventionCascade {
    param($Controller,[string]$Answer,[string]$Evidence,[string]$Policy,[int]$MaxRevisionCalls=2,[scriptblock]$Revise,[scriptblock]$Notify)
    if($Policy -cnotin @('MINIMAL','STANDARD','CASCADE')){throw 'Invalid intervention policy'}
    $limit=[Math]::Min(2,[Math]::Max(0,$MaxRevisionCalls))
    $attempts=New-Object 'System.Collections.Generic.List[object]'
    $check=Get-LfoG2E1Check $Controller $Answer $Evidence
    $initialCheck=$check.assessment
    $selected=$Answer;$edited=$false;$calls=0;$status='NOT_TRIGGERED';$changedBy='NONE'
    if($check.assessment -eq 'CHECK_FAILED'){$status='CHECK_FAILED'}
    elseif($check.assessment -eq 'CONTRADICTED'){
        $attempts.Add([pscustomobject]@{phase='initial';answer=$Answer;raw='';assessment=$check.assessment;rule=$check.rule;start=$check.start;length=$check.length;valid=$true})
        if($Notify){& $Notify '[G2] E1: current-turn external verification claim conflicts with runtime provenance.'}
        $inline=Get-LfoG2SafeInline $Answer $check
        if($null -ne $inline){
            $selected=$inline;$edited=$true;$changedBy='INLINE'
            $check=Get-LfoG2E1Check $Controller $selected $Evidence
            $attempts.Add([pscustomobject]@{phase='inline';answer=$selected;raw='';assessment=$check.assessment;rule=$check.rule;start=$check.start;length=$check.length;valid=$true})
            if($Notify){& $Notify '[G2] Inline correction applied; only the recognized lookup claim was replaced.'}
        }
        if($check.assessment -eq 'ABSTAIN'){$status='SIGNAL_NOT_REDETECTED'}
        else{
            $status='UNRESOLVED'
            $candidate=$selected
            $feedback=$check
            if($Policy -eq 'CASCADE' -and $Revise){
                for($i=1;$i -le $limit;$i++){
                    $calls++
                    if($Notify){& $Notify ('[G2] E1 unresolved. Running corrective inference '+($i+1)+'/3.')}
                    $response=$null
                    try{$response=& $Revise $candidate $feedback $i}catch{}
                    $raw=if($response){[string]$response.Raw}else{''}
                    $new=if($response){[string]$response.Answer}else{''}
                    $valid=($response -and $response.Valid -eq $true -and -not [string]::IsNullOrWhiteSpace($new))
                    if($valid){
                        $next=Get-LfoG2E1Check $Controller $new $Evidence
                        $attempts.Add([pscustomobject]@{phase=('revision_'+$i);answer=$new;raw=$raw;assessment=$next.assessment;rule=$next.rule;start=$next.start;length=$next.length;valid=$true})
                        if($next.assessment -eq 'ABSTAIN'){
                            $selected=$new;$edited=$true;$changedBy='REVISION';$status='SIGNAL_NOT_REDETECTED';break
                        }
                        # Retain original usable candidate for fallback. Reconstruct only from original task and feedback.
                        $candidate=$new;$feedback=$next
                    }else{
                        $attempts.Add([pscustomobject]@{phase=('revision_'+$i);answer=$new;raw=$raw;assessment='INVALID_RESPONSE';rule=$null;start=$null;length=$null;valid=$false})
                    }
                }
            }
            if($status -eq 'UNRESOLVED' -and $Policy -eq 'CASCADE'){
                # Partial fallback: suppress recognized contradictory sentences only, never invent a correction.
                # If detector cannot re-check the remainder, make that limitation explicit.
                $partial=$selected
                for($j=0;$j -lt 16;$j++){
                    $pc=Get-LfoG2E1Check $Controller $partial $Evidence
                    if($pc.assessment -ne 'CONTRADICTED'){break}
                    $partial=$partial.Remove($pc.start,$pc.length)
                }
                $pc=Get-LfoG2E1Check $Controller $partial $Evidence
                if($pc.assessment -eq 'CONTRADICTED' -or $pc.assessment -eq 'CHECK_FAILED'){$partial=''}
                $selected=$partial.Trim()
                if($selected){$selected+=[Environment]::NewLine+[Environment]::NewLine}
                $selected+='[G2: Partial result. The detected external-verification problem could not be resolved reliably. No external lookup occurred. Please clarify the request or supply evidence. The remaining text is not independently verified.]'
                $edited=$true;$changedBy='PARTIAL';$status='UNRESOLVED_PARTIAL'
            }elseif($status -eq 'UNRESOLVED'){
                # No extra inference allowed. Preserve original text and flag it visibly.
                if($Notify){& $Notify '[G2] E1 remains unresolved. Do not rely on the external verification claim.'}
            }
        }
    }
    [pscustomobject]@{Answer=$selected;Edited=$edited;ChangedBy=$changedBy;Status=$status;InitialAssessment=$initialCheck;RevisionCalls=$calls;Attempts=@($attempts.ToArray());Policy=$Policy}
}
