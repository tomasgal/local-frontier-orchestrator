param(
    [Parameter(Mandatory)][string]$SurrealBinary,
    [string]$RunRoot=(Join-Path ([IO.Path]::GetTempPath()) ('lfo-i1-gate1-'+[guid]::NewGuid().ToString('N'))),
    [string]$BaselineRoot=''
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if(Test-Path -LiteralPath $RunRoot){throw 'Use a fresh RunRoot.'}
$null=New-Item -ItemType Directory -Path $RunRoot
. (Join-Path $PSScriptRoot 'Invoke-LfoL4I1Walkthrough.ps1')
$modelName='i1-offline-transport'
if($BaselineRoot){$modelName=(Get-Content -Raw (Join-Path $BaselineRoot 'p2-noaction-01/control-request.json')|ConvertFrom-Json).model}
Invoke-I1Walkthrough -Repo $repo -RunRoot $RunRoot -SurrealBinary $SurrealBinary -ModelName $modelName -LiveModel $false -ModelTransport {
    param($Request)
    [pscustomobject]@{done=$true;model=$Request.model;message=[pscustomobject]@{content=(@{choice=$Request.format.properties.choice.enum[0]}|ConvertTo-Json -Compress)}}
}
$report=Get-Content -Raw (Join-Path $RunRoot 'walkthrough-report.json')|ConvertFrom-Json
$gate=Get-Content -Raw (Join-Path $RunRoot 'deterministic-gate.json')|ConvertFrom-Json
if(-not $report.pass -or $report.checks.Count -ne 128 -or $gate.checks.Count -ne 108){throw 'Original I1 check set did not pass.'}
if($report.model_calls -ne 0 -or $report.transport_calls -ne 5){throw 'Offline transport contract failed.'}

$script:adapterChecks=0
function Assert-Adapter([bool]$Condition,[string]$Name){
    if(-not $Condition){throw ('Gate 1 adapter: '+$Name)}
    $script:adapterChecks++
}
. (Join-Path $repo 'src/LfoL4Runtime.ps1')
$binding=New-LfoL4RuntimePolicyBinding -WorkDirectory $RunRoot
$a1=Get-Content -Raw (Join-Path $RunRoot 'p2-framing-01/a1.json')|ConvertFrom-Json
$a2=Get-Content -Raw (Join-Path $RunRoot 'p2-framing-01/a2.json')|ConvertFrom-Json
$argsCycle=@{Connection=[pscustomobject]@{};StoreId=$a2.StoreId;Epoch=1;FirstTurn=1;LastTurn=8;PolicyBinding=$binding;PolicyEnabled=$true;InterventionEnabled=$true}
# The response phase must work from an existing A2 summary without store reads.
& {
    function Invoke-LfoEpistemicQuery {throw 'Response attempted store I/O.'}
    $off=Get-LfoL4RuntimeResponse -A2Summary $a2 -PolicyBinding $binding
    Assert-Adapter ($off.Status -ceq 'READY' -and $off.Policy.ReasonCode -ceq 'DEFAULT_OFF' -and -not $off.Intervention.Enabled) 'both defaults OFF; response does not read R1'
    $on=Get-LfoL4RuntimeResponse -A2Summary $a2 -PolicyBinding $binding -PolicyEnabled -InterventionEnabled
    Assert-Adapter ($on.Status -ceq 'READY' -and $on.Policy.Decision -ceq 'REVIEW_FRAMING' -and $on.Intervention.Enabled) 'prior summary drives explicit ON without store I/O'
}
foreach($stage in @('R1','A1','A2','P1','P2')) {
    & {
        if($stage -ne 'R1'){
            function Get-LfoEpistemicObservatoryWindow {return $a1}
            function Get-LfoEpistemicInteractionAnalytics {return $a2}
        }
        $target=switch($stage){
            'R1' {'Invoke-LfoEpistemicQuery'}
            'A1' {'Get-LfoEpistemicObservatoryWindow'}
            'A2' {'Get-LfoEpistemicInteractionAnalytics'}
            'P1' {'Get-LfoEpistemicPolicyCapsule'}
            'P2' {'Get-LfoEpistemicIntervention'}
        }
        Set-Item -Path ('Function:\local:'+$target) -Value {throw 'injected-component-failure'}
        $failed=Invoke-LfoL4RuntimeCycle @argsCycle
        Assert-Adapter ($failed.Status -ceq 'FAILED_ISOLATED' -and $failed.Error -ceq 'injected-component-failure' -and $null -eq $failed.Intervention -and $null -eq $failed.Policy) ($stage+' failure leaves no active policy/intervention')
    }
}
& {
    $script:seenBounds=@()
    function Get-LfoEpistemicObservatoryWindow {
        param($Connection,$StoreId,$Epoch,$FirstTurn,$LastTurn,$PageSize,$MaxRecords,$SupportLimit)
        $script:seenBounds+=@("$FirstTurn/$LastTurn/$PageSize/$MaxRecords/$SupportLimit")
        return $a1
    }
    function Get-LfoEpistemicInteractionAnalytics {
        param($Connection,$StoreId,$Epoch,$FirstTurn,$LastTurn,$PageSize,$MaxRecords,$SupportLimit)
        $script:seenBounds+=@("$FirstTurn/$LastTurn/$PageSize/$MaxRecords/$SupportLimit")
        return $a2
    }
    $bounded=Invoke-LfoL4RuntimeCycle @argsCycle -PageSize 2 -MaxRecords 18 -SupportLimit 12
    Assert-Adapter ($bounded.Status -ceq 'READY' -and ($script:seenBounds -join '|') -ceq '1/8/2/18/12|1/8/2/18/12') 'both frozen readers receive exact bounds'
}

$parityFiles=0
if($BaselineRoot){
    $baseline=Get-Content -Raw (Join-Path $BaselineRoot 'walkthrough-report.json')|ConvertFrom-Json
    Assert-Adapter ($baseline.pass -and (($baseline.checks|ConvertTo-Json -Depth 10 -Compress) -ceq ($report.checks|ConvertTo-Json -Depth 10 -Compress))) 'all original assertions identical'
    # Store identities, capture/recording times and the store-bound payload hash
    # are generated per isolated fixture (R1 validates the latter on write).
    # Compare every other field, including exact source text/hashes, support,
    # decisions, instructions and complete model/control requests.
    function Normalize-I1Artifact($Value,[string]$Store){
        if($null -eq $Value){return $null}
        if($Value -is [string]){return $Value.Replace($Store,'STORE_ID')}
        if($Value -is [System.Array]){return ,@($Value|ForEach-Object{Normalize-I1Artifact $_ $Store})}
        if($Value -is [pscustomobject]){
            $out=[ordered]@{}
            foreach($prop in @($Value.PSObject.Properties|Sort-Object Name)){
                if($prop.Name -cnotin @('captured_at','recorded_at','payload_sha256')){$out[$prop.Name]=Normalize-I1Artifact $prop.Value $Store}
            }
            return $out
        }
        return $Value
    }
    foreach($case in $report.cases){
        $old=Join-Path $BaselineRoot $case.case_id;$new=Join-Path $RunRoot $case.case_id
        $oldStore=(Get-Content -Raw (Join-Path $old 'l0/l4-source-identity.json')|ConvertFrom-Json).store_id
        $newStore=(Get-Content -Raw (Join-Path $new 'l0/l4-source-identity.json')|ConvertFrom-Json).store_id
        foreach($file in @('a1.json','a2.json','p1-evidence.json','p1-default-off.json','p1-capsule.json','p2-intervention.json','control-request.json','model-request.json','reverse-provenance.json')){
            $x=Normalize-I1Artifact (Get-Content -Raw (Join-Path $old $file)|ConvertFrom-Json) $oldStore
            $y=Normalize-I1Artifact (Get-Content -Raw (Join-Path $new $file)|ConvertFrom-Json) $newStore
            Assert-Adapter (($x|ConvertTo-Json -Depth 60 -Compress) -ceq ($y|ConvertTo-Json -Depth 60 -Compress)) ($case.case_id+'/'+$file+' baseline parity')
            $parityFiles++
        }
    }
}
Save-I1Json (Join-Path $RunRoot 'gate1-result.json') ([ordered]@{pass=$true;i1_checks=$report.checks.Count;pre_inference_checks=$gate.checks.Count;adapter_checks=$script:adapterChecks;parity_files=$parityFiles;model_calls=0;transport_calls=5;observations=$report.planned_r1_writes;d1_calls=0})
Write-Host ("GATE1 PASS: I1={0}/128; pre-inference={1}/108; adapter={2}; parity files={3}; model calls=0; observations=18; D1=0; evidence={4}" -f $report.checks.Count,$gate.checks.Count,$script:adapterChecks,$parityFiles,$RunRoot)
