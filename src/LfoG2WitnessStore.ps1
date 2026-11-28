# Research-only SQLite working store. Not L2 factual memory or L4 observations.
. (Join-Path $PSScriptRoot 'LfoMemoryStore.ps1')
. (Join-Path $PSScriptRoot 'LfoG2DeterministicWitness.ps1')
function Get-LfoG2WitnessHash([string]$Text){
    $h=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
}
function Open-LfoG2WitnessStore([string]$Path){
    if([IO.Path]::GetFileName($Path) -cne 'g2-witness.db'){throw 'Use a separate g2-witness.db; never open L2 or L3 here.'}
    $db=Open-LfoSqliteDatabase $Path
    try{
        Invoke-LfoSqliteExec $db @'
CREATE TABLE IF NOT EXISTS g2_witness_v1 (
    id TEXT PRIMARY KEY,
    scope_id TEXT NOT NULL,
    source_ref TEXT NOT NULL,
    contract TEXT NOT NULL,
    operation TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
'@
        return $db
    }catch{Close-LfoSqliteDatabase $db;throw}
}
function Save-LfoG2Witness {
    param($Connection,$Case,[string]$ScopeId,[string]$SourceRef,[switch]$TrustedBinding)
    # Scope and source reference are provided by the trusted caller. This does not authenticate L0.
    $w=Invoke-LfoG2DeterministicWitness $Case -TrustedBinding:$TrustedBinding
    if($w.state -cne 'COMPUTED'){return [pscustomobject]@{stored=$false;id=$null;witness=$w}}
    if([string]::IsNullOrWhiteSpace($ScopeId) -or [string]::IsNullOrWhiteSpace($SourceRef)){throw 'Missing source scope/reference'}
    $bindings=@(foreach($b in ($w.inputs|Sort-Object name)){
        $src=@($Case.segments|Where-Object {$_.id -ceq $b.source_id})[0]
        [ordered]@{name=$b.name;source_id=$b.source_id;source_sha256=(Get-LfoG2WitnessHash $src.text);start=$b.start;length=$b.length;literal=$b.literal}
    })
    # Store literals as text so the SQLite REAL conversion cannot truncate exact decimal operands.
    $record=[ordered]@{schema='g2-witness-store-v1';purpose='PROCESSING';status='PROVISIONAL';scope_id=$ScopeId;source_ref=$SourceRef;contract=$w.contract;operation=$w.operation;scope=$w.scope;inputs=$bindings;results=$w.results}
    $json=$record|ConvertTo-Json -Depth 15 -Compress
    $id=Get-LfoG2WitnessHash $json
    Invoke-LfoSqliteNonQuery $Connection 'INSERT OR IGNORE INTO g2_witness_v1(id,scope_id,source_ref,contract,operation,payload_json) VALUES(?,?,?,?,?,?);' @($id,$ScopeId,$SourceRef,$w.contract,$w.operation,$json)
    $row=@(Invoke-LfoSqliteQuery $Connection 'SELECT payload_json FROM g2_witness_v1 WHERE id=?;' @($id))
    if($row.Count -ne 1 -or $row[0].payload_json -cne $json){throw 'Witness store roundtrip mismatch'}
    [pscustomobject]@{stored=$true;id=$id;witness=$w}
}
