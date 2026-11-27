# Reuse frozen L4 T1, without inventing a second classifier.
function Get-LfoG2ConfirmationSeeking {
    param($Context,[string]$Sensitivity)
    $kind=Get-LfoL4TurnObservationType ([string]$Context.Text)
    if($kind -ceq 'ASYMMETRIC_EVIDENCE_REQUEST'){return 'OBSERVED_SIGNAL'}
    if($Sensitivity -eq 'HIGH' -and $kind -ceq 'FRAMING'){return 'OBSERVED_SIGNAL'}
    return 'ABSTAIN'
}
