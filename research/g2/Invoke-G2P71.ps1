[CmdletBinding()]
param([string]$ExportRoot='C:\Transfer\Export\LFO')
$ErrorActionPreference='Stop'
# Experimental deterministic specialist. Inputs are explicitly oracle-bound by
# the test harness; text, bindings and scope are not authenticated by this code.
# This is a narrow comparison adapter, not an automatic text extractor or CES operator.
function New-P71Result([string]$State,[string]$Reason,$Witness){
    [pscustomobject]@{specialist='CPU.NUMERIC_COMPARISON';contract='p71-0.1';state=$State;reason=$Reason;witness=$Witness;scope='Conditional comparison of bound supplied values; no independent verification';purpose='RESEARCH'}
}
function Resolve-P71Operand($Operand,$Sources){
    if($null -eq $Operand){return $null}
    foreach($k in @('source_id','entity','metric','unit','scope','lexeme')){
        if($Operand[$k] -isnot [string] -or [string]::IsNullOrWhiteSpace($Operand[$k])){return $null}
    }
    $src=@($Sources|Where-Object {$_.id -ceq $Operand.source_id})
    if($src.Count -ne 1 -or $src[0].role -cne 'EVIDENCE' -or $src[0].text -isnot [string]){return $null}
    if($Operand.start -isnot [int] -or $Operand.length -isnot [int] -or $Operand.start -lt 0 -or $Operand.length -lt 1 -or $Operand.start -gt $src[0].text.Length -or $Operand.length -gt ($src[0].text.Length-$Operand.start)){return $null}
    $literal=$src[0].text.Substring($Operand.start,$Operand.length)
    if($literal -cne $Operand.lexeme){return $null}
    # Explicit invariant decimal contract; no implicit locale or unit conversion.
    if($literal -cnotmatch '^[+-]?[0-9]+(?:\.[0-9]+)?$'){return $null}
    $digits=($literal -replace '[^0-9]','').Length
    if($digits -gt 28){return $null}
    $number=[decimal]0
    $style=[Globalization.NumberStyles]::AllowLeadingSign -bor [Globalization.NumberStyles]::AllowDecimalPoint
    if(-not [decimal]::TryParse($literal,$style,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)){return $null}
    [pscustomobject]@{source_id=$Operand.source_id;start=$Operand.start;length=$Operand.length;literal=$literal;value=$number;entity=$Operand.entity;metric=$Operand.metric;unit=$Operand.unit;scope=$Operand.scope}
}
function Invoke-P71Specialist($Case,[switch]$OracleBinding){
    if(-not $OracleBinding){return (New-P71Result 'UNKNOWN' 'UNTRUSTED_BINDING' $null)}
    $c=$Case.claim
    if($null -eq $c){return (New-P71Result 'UNKNOWN' 'MISSING_CLAIM' $null)}
    if($c.modality -cin @('QUOTE','FICTION','HYPOTHETICAL')){return (New-P71Result 'NOT_APPLICABLE' 'PROTECTED_MODALITY' $null)}
    if($c.modality -cnotin @('ASSERTED','REQUESTED')){return (New-P71Result 'UNKNOWN' 'UNKNOWN_MODALITY' $null)}
    if($c.relation -cnotin @('GT','LT','EQ','GE','LE','NE')){return (New-P71Result 'UNKNOWN' 'UNSUPPORTED_RELATION' $null)}
    $a=Resolve-P71Operand $Case.a $Case.sources
    $b=Resolve-P71Operand $Case.b $Case.sources
    if($null -eq $a -or $null -eq $b){return (New-P71Result 'UNKNOWN' 'MISSING_OR_INVALID_EVIDENCE_BINDING' $null)}
    if($a.entity -cne $c.left -or $b.entity -cne $c.right -or $a.entity -ceq $b.entity){return (New-P71Result 'UNKNOWN' 'ENTITY_BINDING_MISMATCH' $null)}
    if($a.metric -cne $b.metric -or $a.metric -cne $c.metric -or $a.unit -cne $b.unit -or $a.unit -cne $c.unit -or $a.scope -cne $b.scope -or $a.scope -cne $c.scope){return (New-P71Result 'UNKNOWN' 'NOT_COMPARABLE' $null)}
    if($a.source_id -ceq $b.source_id -and $a.start -lt ($b.start+$b.length) -and $b.start -lt ($a.start+$a.length)){return (New-P71Result 'UNKNOWN' 'OVERLAPPING_BINDINGS' $null)}
    $ok=switch -CaseSensitive ($c.relation){
        'GT'{ $a.value -gt $b.value }
        'LT'{ $a.value -lt $b.value }
        'EQ'{ $a.value -eq $b.value }
        'GE'{ $a.value -ge $b.value }
        'LE'{ $a.value -le $b.value }
        'NE'{ $a.value -ne $b.value }
    }
    $actual=if($a.value -gt $b.value){'GT'}elseif($a.value -lt $b.value){'LT'}else{'EQ'}
    $w=[ordered]@{left=$a;right=$b;requested_relation=$c.relation;actual_relation=$actual;modality=$c.modality}
    if($ok){return (New-P71Result 'CLEAR' 'RELATION_SUPPORTED' $w)}
    return (New-P71Result 'DEFECT' 'RELATION_CONTRADICTED' $w)
}
function New-P71Case([string]$Id,[string]$A,[string]$B,[string]$Relation,[string]$Gold,[string]$Reason){
    $left='A scored '+$A+' points.';$right='B scored '+$B+' points.'
    @{
        id=$Id;gold=$Gold;reason=$Reason;oracle=$true
        sources=@(@{id='S1';role='EVIDENCE';text=$left},@{id='S2';role='EVIDENCE';text=$right})
        a=@{source_id='S1';start=9;length=$A.Length;lexeme=$A;entity='A';metric='score';unit='point';scope='round1'}
        b=@{source_id='S2';start=9;length=$B.Length;lexeme=$B;entity='B';metric='score';unit='point';scope='round1'}
        claim=@{left='A';right='B';metric='score';unit='point';scope='round1';relation=$Relation;modality='ASSERTED'}
    }
}
$cases=@(
 (New-P71Case 'D01' '61' '84' 'GT' 'DEFECT' 'RELATION_CONTRADICTED'),
 (New-P71Case 'D02' '8' '8' 'NE' 'DEFECT' 'RELATION_CONTRADICTED'),
 (New-P71Case 'D03' '3.02' '3.01' 'LE' 'DEFECT' 'RELATION_CONTRADICTED'),
 (New-P71Case 'D04' '-5' '-2' 'GE' 'DEFECT' 'RELATION_CONTRADICTED'),
 (New-P71Case 'C01' '84' '61' 'GT' 'CLEAR' 'RELATION_SUPPORTED'),
 (New-P71Case 'C02' '3.010' '3.01' 'EQ' 'CLEAR' 'RELATION_SUPPORTED'),
 (New-P71Case 'C03' '-5' '-2' 'LT' 'CLEAR' 'RELATION_SUPPORTED'),
 (New-P71Case 'C04' '8' '8' 'GE' 'CLEAR' 'RELATION_SUPPORTED'),
 (New-P71Case 'U01' '61' '84' 'GT' 'UNKNOWN' 'MISSING_OR_INVALID_EVIDENCE_BINDING'),
 (New-P71Case 'U02' '61' '84' 'GT' 'UNKNOWN' 'NOT_COMPARABLE'),
 (New-P71Case 'U03' '61' '84' 'GT' 'UNKNOWN' 'NOT_COMPARABLE'),
 (New-P71Case 'U04' '61' '84' 'GT' 'UNKNOWN' 'NOT_COMPARABLE'),
 (New-P71Case 'U05' '61' '84' 'GT' 'UNKNOWN' 'ENTITY_BINDING_MISMATCH'),
 (New-P71Case 'U06' '61' '84' 'GT' 'UNKNOWN' 'MISSING_OR_INVALID_EVIDENCE_BINDING'),
 (New-P71Case 'U07' '61' '84' 'GT' 'UNKNOWN' 'UNTRUSTED_BINDING'),
 (New-P71Case 'U08' '1,5' '2' 'GT' 'UNKNOWN' 'MISSING_OR_INVALID_EVIDENCE_BINDING'),
 (New-P71Case 'U09' '61' '84' 'GT' 'UNKNOWN' 'UNSUPPORTED_RELATION'),
 (New-P71Case 'U10' '61' '84' 'GT' 'UNKNOWN' 'OVERLAPPING_BINDINGS'),
 (New-P71Case 'U11' '61' '84' 'GT' 'UNKNOWN' 'MISSING_OR_INVALID_EVIDENCE_BINDING'),
 (New-P71Case 'U12' '123456789012345678901234567890' '84' 'GT' 'UNKNOWN' 'MISSING_OR_INVALID_EVIDENCE_BINDING'),
 (New-P71Case 'N01' '61' '84' 'GT' 'NOT_APPLICABLE' 'PROTECTED_MODALITY'),
 (New-P71Case 'N02' '61' '84' 'GT' 'NOT_APPLICABLE' 'PROTECTED_MODALITY'),
 (New-P71Case 'N03' '61' '84' 'GT' 'NOT_APPLICABLE' 'PROTECTED_MODALITY')
)
$cases[0].claim.modality='REQUESTED'
$cases[8].b=$null
$cases[9].b.unit='percent'
$cases[10].b.scope='round2'
$cases[11].b.metric='cost'
$cases[12].claim.left='C'
$cases[13].a.lexeme='62'
$cases[14].oracle=$false
$cases[16].claim.relation='APPROX'
$cases[17].b.source_id='S1';$cases[17].b.lexeme='61'
$cases[18].sources[0].role='CLAIM'
$cases[20].claim.modality='QUOTE'
$cases[21].claim.modality='FICTION'
$cases[22].claim.modality='HYPOTHETICAL'
$rows=@(foreach($c in $cases){
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $result=Invoke-P71Specialist $c -OracleBinding:([bool]$c.oracle)
    $sw.Stop()
    $correct=$result.state -ceq $c.gold -and $result.reason -ceq $c.reason
    [pscustomobject]@{id=$c.id;gold=$c.gold;gold_reason=$c.reason;state=$result.state;reason=$result.reason;correct=$correct;ms=$sw.Elapsed.TotalMilliseconds;result=$result}
})
$bad=@($rows|Where-Object {-not $_.correct})
$utf8=New-Object Text.UTF8Encoding($false)
$null=New-Item -ItemType Directory -Force -Path $ExportRoot
$dir=Join-Path $ExportRoot ('P71-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Force -Path $dir
[IO.File]::WriteAllText((Join-Path $dir 'results.json'),($rows|ConvertTo-Json -Depth 20),$utf8)
$rows|Select-Object id,gold,state,reason,correct,ms|Format-Table -AutoSize
Write-Host "P71 correct=$($rows.Count-$bad.Count)/$($rows.Count); NPU=0; GPU=0; DB=0; oracle bindings only"
Write-Host "RESULTS $dir"
if($bad.Count -ne 0){throw 'P71 contract failed.'}
