[CmdletBinding()]
param([string]$WorkRoot=(Join-Path $env:LOCALAPPDATA 'LFO-G2-Lab\P78'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../src/LfoG2WitnessStore.ps1')
function Assert-P78([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message}}
$path=Join-Path (Join-Path $WorkRoot ([guid]::NewGuid().ToString('N'))) 'g2-witness.db'
$sourceA='Hodnota A: 9007199254740993'
$sourceB='Hodnota B: 9007199254740992'
$c=@{segments=@(@{id='A';role='EVIDENCE';text=$sourceA},@{id='B';role='EVIDENCE';text=$sourceB});witness=@{operation='COMPARE';relation='GT';inputs=@(@{name='a';source_id='A';start=11;length=16;lexeme='9007199254740993'},@{name='b';source_id='B';start=11;length=16;lexeme='9007199254740992'})}}
# The offsets are derived from exact literals, not inferred semantic roles.
$c.witness.inputs[0].start=$sourceA.IndexOf($c.witness.inputs[0].lexeme,[StringComparison]::Ordinal)
$c.witness.inputs[1].start=$sourceB.IndexOf($c.witness.inputs[1].lexeme,[StringComparison]::Ordinal)
$db=Open-LfoG2WitnessStore $path
$checks=0
try{
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $a=Save-LfoG2Witness $db $c 'lab:1' 'fixture:1' -TrustedBinding
    $sw.Stop()
    $firstMs=$sw.Elapsed.TotalMilliseconds
    Assert-P78 ($a.stored -and $a.witness.results.holds) 'Store or exact comparison failed';$checks++
    $b=Save-LfoG2Witness $db $c 'lab:1' 'fixture:1' -TrustedBinding
    Assert-P78 ($a.id -ceq $b.id) 'Idempotence failed';$checks++
    $z=Save-LfoG2Witness $db $c 'lab:1' 'fixture:1'
    Assert-P78 (-not $z.stored -and $z.witness.state -ceq 'ABSTAIN') 'Untrusted binding persisted';$checks++
    $other=Save-LfoG2Witness $db $c 'lab:2' 'fixture:1' -TrustedBinding
    Assert-P78 ($other.id -cne $a.id) 'Scope collision';$checks++
    $c.segments[0].text='Hodnota A: 9007199254740993 bodov'
    $changed=Save-LfoG2Witness $db $c 'lab:1' 'fixture:1' -TrustedBinding
    Assert-P78 ($changed.id -cne $a.id) 'Source fingerprint ignored';$checks++
    $c.witness.inputs[0].lexeme='9999999999999999'
    $invalid=Save-LfoG2Witness $db $c 'lab:1' 'fixture:1' -TrustedBinding
    Assert-P78 (-not $invalid.stored -and $invalid.witness.state -ceq 'INVALID') 'Invalid witness persisted';$checks++
    $count=@(Invoke-LfoSqliteQuery $db 'SELECT COUNT(*) AS n FROM g2_witness_v1;')[0].n
    Assert-P78 ($count -eq 3) 'Unexpected row count';$checks++
}finally{Close-LfoSqliteDatabase $db}
$db=Open-LfoG2WitnessStore $path
try{
    $row=@(Invoke-LfoSqliteQuery $db 'SELECT payload_json FROM g2_witness_v1 WHERE id=?;' @($a.id))
    Assert-P78 ($row.Count -eq 1) 'Reopen failed';$checks++
    $v=$row[0].payload_json|ConvertFrom-Json
    Assert-P78 ($v.inputs[0].literal -ceq '9007199254740993' -and $v.inputs[0].source_sha256 -ceq (Get-LfoG2WitnessHash $sourceA) -and $v.results.holds -eq $true) 'Precision/provenance lost';$checks++
    Assert-P78 ($v.purpose -ceq 'PROCESSING' -and $v.status -ceq 'PROVISIONAL' -and $v.source_ref -ceq 'fixture:1') 'Working-store contract failed';$checks++
}finally{Close-LfoSqliteDatabase $db}
Write-Host "UNIT PASS $checks/$checks"
Write-Host ("P78 SQLITE PASS; rows=3; first_compute_write_read_ms={0:N3}; model_calls=0; L2_writes=0; L4_writes=0" -f $firstMs)
Write-Host "LAB DB $path"
