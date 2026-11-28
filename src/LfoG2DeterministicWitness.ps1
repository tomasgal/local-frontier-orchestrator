# Research-only adapter for deterministic CES witnesses. No I/O, no model calls.
. (Join-Path $PSScriptRoot 'LfoCesWitness.ps1')
function Invoke-LfoG2DeterministicWitness {
    [CmdletBinding()]
    param($Case,[switch]$TrustedBinding)
    $contract='g2-witness-v1'
    $result=[ordered]@{contract=$contract;state='ABSTAIN';reason='NO_BINDING';operation=$null;inputs=@();results=$null;scope='Conditional computation over supplied bound values; not independent verification or a bias diagnosis.'}
    if($null -eq $Case -or $null -eq $Case.witness){return [pscustomobject]$result}
    $result.operation=[string]$Case.witness.operation
    if(-not $TrustedBinding){$result.reason='UNVERIFIED_SEMANTIC_BINDING';return [pscustomobject]$result}
    try {
        $spec=$Case.witness
        if($result.operation -cnotin @('UTILITY','STRATIFIED_RATES','PREDICTIVE_VALUE','INTERVAL_ZERO','RELATIVE_REDUCTION','MISSING_BOUNDS','PAIR_SUM','COST_PER_SUCCESS','COMPARE')){throw 'Unsupported operation'}
        $names=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $bound=New-Object 'System.Collections.Generic.List[object]'
        $numbers=@{}
        foreach($r in $spec.inputs){
            if($r.name -isnot [string] -or $r.name -cnotmatch '^[a-z][a-z0-9_]*$' -or -not $names.Add($r.name)){throw 'Invalid or duplicate binding name'}
            if($r.source_id -isnot [string] -or [string]::IsNullOrWhiteSpace($r.source_id) -or $r.lexeme -isnot [string]){throw 'Invalid binding type'}
            $src=@($Case.segments|Where-Object {$_.id -ceq $r.source_id})
            if($src.Count -ne 1 -or $src[0].role -cnotin @('EVIDENCE','TASK','CONSTRAINT') -or $src[0].text -isnot [string]){throw 'Invalid source'}
            if(($r.start -isnot [int] -and $r.start -isnot [long]) -or ($r.length -isnot [int] -and $r.length -isnot [long]) -or $r.start -lt 0 -or $r.length -lt 1 -or $r.start -gt $src[0].text.Length -or $r.length -gt ($src[0].text.Length-$r.start)){throw 'Invalid span'}
            $literal=$src[0].text.Substring([int]$r.start,[int]$r.length)
            if($literal -cne $r.lexeme -or $literal -cnotmatch '^[+-]?[0-9]+(?:\.[0-9]+)?$' -or ($literal -replace '[^0-9]','').Length -gt 28){throw 'Invalid numeric literal'}
            # Reject partial numeric tokens, e.g. 1 within 12 or 1,5.
            if($r.start -gt 0 -and $src[0].text[$r.start-1] -match '[\p{L}\d.,+-]'){throw 'Partial numeric token'}
            $end=$r.start+$r.length
            if($end -lt $src[0].text.Length -and $src[0].text[$end] -match '[\p{L}\d.,+-]'){throw 'Partial numeric token'}
            foreach($old in $bound){if($old.source_id -ceq $r.source_id -and $r.start -lt ($old.start+$old.length) -and $old.start -lt $end){throw 'Overlapping bindings'}}
            $v=[decimal]0
            $style=[Globalization.NumberStyles]::AllowLeadingSign -bor [Globalization.NumberStyles]::AllowDecimalPoint
            if(-not [decimal]::TryParse($literal,$style,[Globalization.CultureInfo]::InvariantCulture,[ref]$v)){throw 'Invalid decimal'}
            $numbers[$r.name]=$v
            $bound.Add([pscustomobject]@{name=$r.name;source_id=$r.source_id;start=$r.start;length=$r.length;literal=$literal})
        }
        if($result.operation -ceq 'COMPARE'){
            if($numbers.Count -ne 2 -or -not $numbers.ContainsKey('a') -or -not $numbers.ContainsKey('b') -or $spec.relation -cnotin @('GT','LT','EQ','GE','LE','NE')){throw 'Invalid comparison contract'}
            $a=$numbers.a;$b=$numbers.b
            $holds=switch -CaseSensitive ($spec.relation){'GT'{$a -gt $b};'LT'{$a -lt $b};'EQ'{$a -eq $b};'GE'{$a -ge $b};'LE'{$a -le $b};'NE'{$a -ne $b}}
            $actual=if($a -gt $b){'GT'}elseif($a -lt $b){'LT'}else{'EQ'}
            $result.results=[ordered]@{relation=$spec.relation;actual_relation=$actual;holds=$holds;arithmetic='DECIMAL'}
        }else{
            # Reuse frozen eight-operation module. Double arithmetic is approximate.
            # Do not silently round decimal inputs at the legacy conversion boundary.
            foreach($n in $numbers.Keys){if([decimal]([double]$numbers[$n]) -ne $numbers[$n]){throw 'Legacy precision boundary'}}
            $w=Get-LfoCesWitness $Case
            if($w.status -cne 'COMPUTED'){throw 'Legacy witness did not compute'}
            foreach($value in $w.results.Values){if($value -is [double] -and ([double]::IsNaN($value) -or [double]::IsInfinity($value))){throw 'Nonfinite result'}}
            $result.results=$w.results
        }
        $result.inputs=$bound.ToArray()
        $result.state='COMPUTED';$result.reason='BOUND_CONDITIONAL_COMPUTATION'
    }catch{
        $result.state='INVALID';$result.reason=$_.Exception.Message;$result.inputs=@();$result.results=$null
    }
    return [pscustomobject]$result
}
