# Turn-level runtime provenance. No inference, storage migration or tool calls.
# This describes external operations in one historical turn, not the truth
# of its assertions or the verification status of any individual L2 fact.
function Get-LfoExternalEvidenceStatus($Row){
    $status=[string]$Row.external_evidence_status
    if($status -cin @('NONE','REQUESTED','OBSERVED','UNKNOWN')){return $status}
    return 'UNKNOWN'
}

function Get-LfoHistoricalTurnLabel($Row){
    $route=[string]$Row.route
    if($route -cnotin @('LOCAL','FRONTIER')){$route='UNKNOWN'}
    return ('[route={0}; external_evidence={1}]' -f $route,(Get-LfoExternalEvidenceStatus $Row))
}
