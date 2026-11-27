@{
    SchemaVersion = 1
    Axes = @{
        E1 = 'Integrity'
        E2 = 'Selection'
        E3 = 'Inference'
        E4 = 'Independence'
        E5 = 'Calibration'
        E6 = 'Revision'
    }
    Detectors = @(
        @{ Id='verification-claim'; Version='2.1.0'; Axis='E1'; Stage='FINAL'; Module='VerificationClaim.ps1'; Function='Get-LfoG2VerificationClaim' }
        @{ Id='confirmation-seeking'; Version='2.1.0'; Axis='E4'; Stage='USER'; Module='ConfirmationSeeking.ps1'; Function='Get-LfoG2ConfirmationSeeking' }
        @{ Id='response-stance'; Version='1.0.0'; Axis='E4'; Stage='INTERACTION'; Module='ResponseStance.ps1'; Function='Get-LfoG2ResponseStance' }
    )
}
