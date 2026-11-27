[CmdletBinding()]
param(
    [string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'LFO'),
    [string]$RepositoryRoot,
    [string]$OutputRoot,
    [string]$ExpectedSource,
    [switch]$OfflineOnly,
    [switch]$Pilot2,
    [switch]$Pilot3,
    [switch]$Pilot4
)
$ErrorActionPreference='Stop'
if(@(@($Pilot2,$Pilot3,$Pilot4)|Where-Object{$_}).Count -gt 1){throw 'Choose one pilot.'}
$state=$null
if(-not $RepositoryRoot){
    $state=Get-Content -LiteralPath (Join-Path $InstallRoot 'config/install-state.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $RepositoryRoot=[string]$state.AppRoot
}
if(-not $OfflineOnly -and $null -eq $state){throw 'Live pilot requires installed state, not -RepositoryRoot.'}
if($ExpectedSource -and ($null -eq $state -or $state.SourceCommit -cne $ExpectedSource)){throw 'Installed source does not match -ExpectedSource.'}
if(-not $OutputRoot){$OutputRoot=if($state -and $state.LFO.ExportDirectory){[string]$state.LFO.ExportDirectory}else{Join-Path ([IO.Path]::GetTempPath()) 'lfo-g2-pilot'}}
$run=Join-Path $OutputRoot ('G2-pilot-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
$null=New-Item -ItemType Directory -Path $run -Force
$utf8=New-Object Text.UTF8Encoding($false)
function JsonFile($path,$obj){[IO.File]::WriteAllText($path,($obj|ConvertTo-Json -Depth 20),$utf8)}
# The runner can be downloaded alone; the reviewed corpus comes from its own directory.
$bankPath=Join-Path $PSScriptRoot $(if($Pilot3){'g2/PilotCases03.json'}else{'g2/PilotCases.json'})
$livePath=Join-Path $PSScriptRoot $(if($Pilot3 -or $Pilot4){'g2/LivePrompts03.json'}else{'g2/LivePrompts.json'})
$frozenPath=Join-Path $PSScriptRoot 'g2/FrozenInteractions03.json'
$frozenHash=$null
if($Pilot3 -or $Pilot4){
    $frozenBank=Get-Content -LiteralPath $frozenPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($frozenBank.schemaVersion -ne 1){throw 'Frozen interaction schema mismatch.'}
    Copy-Item -LiteralPath $frozenPath -Destination (Join-Path $run 'frozen-interactions.json')
    $frozenHash=(Get-FileHash -LiteralPath $frozenPath -Algorithm SHA256).Hash
}
$bank=Get-Content -LiteralPath $bankPath -Raw -Encoding UTF8|ConvertFrom-Json
$liveBank=Get-Content -LiteralPath $livePath -Raw -Encoding UTF8|ConvertFrom-Json
Copy-Item -LiteralPath $bankPath -Destination (Join-Path $run 'pilot-cases.json')
$extensionHash=$null
if($Pilot2 -or $Pilot4){
    $extensionPath=Join-Path $PSScriptRoot 'g2/PilotCases02.json'
    $extension=Get-Content -LiteralPath $extensionPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($extension.schemaVersion -ne 1){throw 'Unknown extension schema.'}
    $bank.cases=@($bank.cases)+@($extension.cases)
    Copy-Item -LiteralPath $extensionPath -Destination (Join-Path $run 'pilot-cases02.json')
    $extensionHash=(Get-FileHash -LiteralPath $extensionPath -Algorithm SHA256).Hash
}
Copy-Item -LiteralPath $livePath -Destination (Join-Path $run 'live-prompts.json')
$challengeHash=$null;$stanceHash=$null
if($Pilot4){
    $challengePath=Join-Path $PSScriptRoot 'g2/PilotCases03.json'
    $challenge=Get-Content -LiteralPath $challengePath -Raw -Encoding UTF8|ConvertFrom-Json
    $bank.cases=@($bank.cases)+@($challenge.cases)
    Copy-Item -LiteralPath $challengePath -Destination (Join-Path $run 'pilot-cases03.json')
    $challengeHash=(Get-FileHash -LiteralPath $challengePath -Algorithm SHA256).Hash
    $stancePath=Join-Path $PSScriptRoot 'g2/FrozenStance04.json'
    $stanceBank=Get-Content -LiteralPath $stancePath -Raw -Encoding UTF8|ConvertFrom-Json
    $frozenBank.cases=@($frozenBank.cases)+@($stanceBank.cases)
    Copy-Item -LiteralPath $stancePath -Destination (Join-Path $run 'frozen-stance04.json')
    $stanceHash=(Get-FileHash -LiteralPath $stancePath -Algorithm SHA256).Hash
    $schedule=@()
    for($rep=1;$rep -le 3;$rep++){
        $items=@($liveBank.prompts)
        if($rep -eq 2){[array]::Reverse($items)}
        foreach($item in $items){$schedule+=[pscustomobject]@{id=($item.id+'-R'+$rep);pair=$item.pair;condition=$item.condition;claim=$item.claim;text=$item.text;repetition=$rep}}
    }
    $liveBank.prompts=$schedule
    JsonFile (Join-Path $run 'live-schedule.json') $schedule
}
$sourceFiles=@('LFO.ps1','src/QwenChat.ps1','src/QwenMemory.ps1','src/LfoEpistemicController.ps1','src/epistemic/VerificationClaim.ps1','src/epistemic/ConfirmationSeeking.ps1','src/LfoEvidenceProvenance.ps1','src/LfoL4Runtime.ps1','config/EpistemicRegistry.psd1')
if($Pilot4){$sourceFiles+='src/epistemic/ResponseStance.ps1'}
$hashes=[ordered]@{}
foreach($file in $sourceFiles){$hashes[$file]=(Get-FileHash -LiteralPath (Join-Path $RepositoryRoot $file) -Algorithm SHA256).Hash}
$manifest=[ordered]@{schemaVersion=1;purpose='G2 exploratory detector and integration pilot';sourceCommit=if($state){$state.SourceCommit}else{'CI checkout'};sourceHashes=$hashes;runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash;bankSha256=(Get-FileHash -LiteralPath $bankPath -Algorithm SHA256).Hash;liveBankSha256=(Get-FileHash -LiteralPath $livePath -Algorithm SHA256).Hash;powerShell=$PSVersionTable.PSVersion.ToString();startedUtc=[DateTime]::UtcNow.ToString('o');offlineOnly=[bool]$OfflineOnly;pilot=if($Pilot4){4}elseif($Pilot3){3}elseif($Pilot2){2}else{1};extensionSha256=$extensionHash;frozenBankSha256=$frozenHash;challengeSha256=$challengeHash;stanceBankSha256=$stanceHash;model=$null;context=$null;ollamaVersion=$null;modelDigest=$null;status='STARTED'}
$offline=New-Object Collections.Generic.List[object]
$live=New-Object Collections.Generic.List[object]
$frozenResults=New-Object Collections.Generic.List[object]
$review=New-Object Collections.Generic.List[object]
$failure=$null
try{
    foreach($m in @('LfoEvidenceProvenance','LfoL4Runtime','LfoEpistemicController')){. (Join-Path $RepositoryRoot ('src/'+$m+'.ps1'))}
    $profiles=@{}
    foreach($level in @('LOW','MEDIUM','HIGH')){
        $profile=[ordered]@{schemaVersion=1;mode='OBSERVE';axes=[ordered]@{E1=$level;E2='OFF';E3='OFF';E4=$level;E5='OFF';E6='OFF'};detectors=[ordered]@{'verification-claim'=$true;'confirmation-seeking'=$true}}
        if($Pilot4){$profile.detectors['response-stance']=$true}
        $path=Join-Path $run ('profile-'+$level+'.json')
        JsonFile $path $profile
        $profiles[$level]=$path
    }
    foreach($level in @('LOW','MEDIUM','HIGH')){
        $c=Initialize-LfoG2Controller $RepositoryRoot $profiles[$level]
        $i=0
        foreach($case in $bank.cases){
            $i++
            $u=if($case.detector -eq 'confirmation-seeking'){[string]$case.text}else{'Explain the result.'}
            $a=if($case.detector -eq 'verification-claim'){[string]$case.text}else{'Fixture answer.'}
            $row=[pscustomobject]@{user=$u;assistant=$a;route='LOCAL';external_evidence_status=$case.evidence;runtime_annotation='';epoch=1;turn_id=$i;stage_sources_schema=1;stage_sources=@(
                [pscustomobject]@{actor='USER';source_field='user';stage_id='s1';producer='USER'}
                [pscustomobject]@{actor='FINAL';source_field='assistant';stage_id='s2';producer='LOCAL'}
            )}
            # Synthetic external metadata is deliberate. No external operation or inference occurs.
            $observations=@(Invoke-LfoG2Controller $c $row 'conversation-2026-11.jsonl'|Where-Object detector -eq $case.detector)
            if($observations.Count -ne 1 -or $observations[0].assessment -eq 'FAILED_ISOLATED'){throw ('Detector execution failed: '+$case.id+' '+$level)}
            $o=$observations[0]
            $offline.Add([pscustomobject]@{id=$case.id;detector=$case.detector;sensitivity=$level;label=$case.label;assessment=$o.assessment;reference_scope=$case.reference_scope;detector_version=$o.detector_version;phenomenon=$o.phenomenon;rule_id=$o.rule_id;claim_scope=$o.claim_scope;evidence_start=$o.evidence_start;evidence_length=$o.evidence_length;evidence=$case.evidence;elapsed_ms=$o.elapsed_ms;additional_model_calls=$o.additional_model_calls})
        }
    }
    $offline|Export-Csv -LiteralPath (Join-Path $run 'offline-results.csv') -NoTypeInformation -Encoding UTF8
    $summary=@(foreach($g in ($offline|Group-Object detector,sensitivity,label,assessment)){[pscustomobject]@{detector=$g.Group[0].detector;sensitivity=$g.Group[0].sensitivity;label=$g.Group[0].label;assessment=$g.Group[0].assessment;count=$g.Count}})
    $summary|Export-Csv -LiteralPath (Join-Path $run 'offline-confusion.csv') -NoTypeInformation -Encoding UTF8
    Write-Host ('Offline replay: '+$offline.Count+' detector evaluations; classifications are exploratory.') -ForegroundColor Cyan
    if($Pilot3 -or $Pilot4){
        $expectedEvents=if($Pilot4){3}else{2}
        foreach($level in @('LOW','MEDIUM','HIGH')){
            $c=Initialize-LfoG2Controller $RepositoryRoot $profiles[$level]
            if($Pilot3 -and @($c.Modules.Values|Where-Object{$_.Descriptor.Version -ne '2.0.0'}).Count){throw 'Pilot 03 requires unchanged detector version 2.0.0.'}
            $i=0
            foreach($case in $frozenBank.cases){
                $i++
                $row=[pscustomobject]@{user=[string]$case.user;assistant=[string]$case.assistant;route='LOCAL';external_evidence_status=$case.external_evidence_status;runtime_annotation='';epoch=1;turn_id=$i;stage_sources_schema=1;stage_sources=@(
                    [pscustomobject]@{actor='USER';source_field='user';stage_id='s1';producer='USER'}
                    [pscustomobject]@{actor='FINAL';source_field='assistant';stage_id='s2';producer='LOCAL'}
                )}
                $events=@(Invoke-LfoG2Controller $c $row 'conversation-2026-11.jsonl')
                if($events.Count -ne $expectedEvents -or @($events|Where-Object{$_.assessment -eq 'FAILED_ISOLATED' -or $_.additional_model_calls -ne 0}).Count){throw ('Frozen replay execution failed: '+$case.id)}
                foreach($o in $events){
                    $frozenResults.Add([pscustomobject]@{id=$case.id;pair=$case.pair;response_label=$case.response_label;expected_stance=$case.expected_stance;sensitivity=$level;detector=$o.detector;assessment=$o.assessment;phenomenon=$o.phenomenon;rule_id=$o.rule_id;claim_scope=$o.claim_scope;content_sha256=$o.content_sha256;linked_user_sha256=$o.linked_user_sha256;linked_user_stage_id=$o.linked_user_stage_id;elapsed_ms=$o.elapsed_ms;additional_model_calls=$o.additional_model_calls})
                }
            }
        }
        $frozenResults|Export-Csv -LiteralPath (Join-Path $run 'frozen-results.csv') -NoTypeInformation -Encoding UTF8
        foreach($group in ($frozenResults|Where-Object detector -eq 'confirmation-seeking'|Group-Object pair,sensitivity)){
            if(@($group.Group|ForEach-Object{($_.assessment+'|'+$_.phenomenon+'|'+$_.rule_id+'|'+$_.content_sha256)}|Sort-Object -Unique).Count -ne 1){throw ('User-only E4 changed across fixed-prompt response variants: '+$group.Name)}
        }
        Write-Host ('Frozen interactions: '+$frozenResults.Count+' detector events; fixed-user E4 invariance checked.') -ForegroundColor Cyan
    }
    if(-not $OfflineOnly){
        $expectedEvents=if($Pilot4){3}else{2}
        $manifest.model=[string]$state.Ollama.UMAModel
        $manifest.context=[int]$state.Ollama.UMAContext
        if(-not $manifest.model -or $manifest.context -lt 1024){throw 'UMA model/context missing from installed state.'}
        $uri=([string]$state.Ollama.BaseUri).TrimEnd('/')
        $parsed=[uri]$uri
        if(-not $parsed.IsLoopback){throw 'Live pilot requires a loopback Ollama endpoint.'}
        $version=Invoke-RestMethod -Uri ($uri+'/api/version') -TimeoutSec 5
        $manifest.ollamaVersion=$version.version
        $tags=Invoke-RestMethod -Uri ($uri+'/api/tags') -TimeoutSec 5
        $match=@($tags.models|Where-Object name -eq $manifest.model)
        if($match.Count -ne 1){throw 'Provisioned UMA model alias is unavailable.'}
        $manifest.modelDigest=$match[0].digest
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepositoryRoot 'LFO.ps1'),[ref]$tokens,[ref]$errors)
        if($errors.Count){throw 'Launcher parse failed.'}
        $fn=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'New-LfoQwen963Adapter'})
        if($fn.Count -ne 1){throw 'Expected one existing runtime adapter function.'}
        . ([scriptblock]::Create($fn[0].Extent.Text))
        $adapter=Join-Path $RepositoryRoot ('src/QwenChat.g2pilot-'+[guid]::NewGuid().ToString('N')+'.ps1')
        $envNames=@('LFO_INSTALL_ROOT','LFO_RUNTIME_BATCH','LFO_RUNTIME_DEVICE','LFO_L4_ENABLED','LFO_L4_ENDPOINT','LFO_L4_RUNTIME_CREDENTIAL','LFO_L4_OBSERVABILITY','LFO_EPISTEMIC_PROFILE')
        $saved=@{};foreach($n in $envNames){$saved[$n]=[Environment]::GetEnvironmentVariable($n,'Process')}
        try{
            $null=New-LfoQwen963Adapter (Join-Path $RepositoryRoot 'src/QwenChat.ps1') $adapter
            $code=[IO.File]::ReadAllText($adapter)
            $anchor='$script:LfoRouteMode = ''AUTO'''
            if(([regex]::Matches($code,[regex]::Escape($anchor))).Count -ne 1){throw 'Cannot apply isolated LOCAL session switch.'}
            $code=$code.Replace($anchor,'$script:LfoRouteMode = ''LOCAL''')
            [IO.File]::WriteAllText($adapter,$code,(New-Object Text.UTF8Encoding($true)))
            $manifest.adapterSha256=(Get-FileHash -LiteralPath $adapter -Algorithm SHA256).Hash
            $manifest.livePolicy='Interactive policy (LFO_RUNTIME_BATCH=0), harness-fed single prompt, forced LOCAL, THINK OFF, OBSERVE MEDIUM, legacy L4 OFF, each case fresh process and isolated data root. No production config overlay.'
            Remove-Item Env:LFO_INSTALL_ROOT -ErrorAction SilentlyContinue
            $env:LFO_RUNTIME_BATCH='0';$env:LFO_RUNTIME_DEVICE='UMA';$env:LFO_L4_ENABLED='0';$env:LFO_L4_OBSERVABILITY='0'
            Remove-Item Env:LFO_L4_ENDPOINT,Env:LFO_L4_RUNTIME_CREDENTIAL -ErrorAction SilentlyContinue
            $env:LFO_EPISTEMIC_PROFILE=$profiles['MEDIUM']
            # No production logs or SQLite/Surreal state are copied. Each synthetic case starts fresh.
            foreach($case in $liveBank.prompts){
                $dir=Join-Path $run ('live-'+$case.id);$null=New-Item -ItemType Directory -Path $dir
                $inputFile=Join-Path $dir 'input.json'
                JsonFile $inputFile @{prompts=@(@{text=$case.text;clear_before=$false})}
                $dataDir=Join-Path $dir 'isolated-memory'
                Write-Host ('Live '+$case.id+' / '+$liveBank.prompts.Count+': '+$case.text) -ForegroundColor Cyan
                $oldPref=$ErrorActionPreference
                try{
                    $ErrorActionPreference='Continue'
                    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $adapter -Model $manifest.model -ConfigPath ([string]$state.LFO.ConfigPath) -ContextLengthHint $manifest.context -BaseUriOverride $uri -DataDirectoryOverride $dataDir -BatchInputPath $inputFile -BatchLocalOnly 2>&1 | Tee-Object -FilePath (Join-Path $dir 'console.txt') | Out-Host
                    $exitCode=$LASTEXITCODE
                }finally{$ErrorActionPreference=$oldPref}
                $logDir=Join-Path $dataDir 'logs'
                $turns=@(Get-ChildItem -LiteralPath $logDir -Filter 'conversation-*.jsonl' -File -ErrorAction SilentlyContinue|ForEach-Object{Get-Content -LiteralPath $_.FullName -Encoding UTF8|ForEach-Object{$_|ConvertFrom-Json}}|Where-Object event -eq 'turn')
                $events=@(Get-ChildItem -LiteralPath $logDir -Filter 'epistemic-*.jsonl' -File -ErrorAction SilentlyContinue|ForEach-Object{Get-Content -LiteralPath $_.FullName -Encoding UTF8|ForEach-Object{$_|ConvertFrom-Json}})
                $hashOK=$false
                if($turns.Count -eq 1 -and $events.Count -eq $expectedEvents){
                    $t=$turns[0]
                    $hashOK=@($events|Where-Object{
                        $raw=if($_.actor -eq 'USER'){[string]$t.user}else{[string]$t.assistant}
                        $_.content_sha256 -cne (Get-LfoEpistemicHash $raw) -or $_.epoch -ne $t.epoch -or $_.turn_id -ne $t.turn_id -or ($_.actor -eq 'INTERACTION' -and ($_.linked_user_sha256 -cne (Get-LfoEpistemicHash ([string]$t.user)) -or $_.linked_user_stage_id -cne (@($t.stage_sources|Where-Object actor -eq 'USER')[0].stage_id)))
                    }).Count -eq 0
                }
                $pass=($exitCode -eq 0 -and $turns.Count -eq 1 -and $events.Count -eq $expectedEvents -and $hashOK -and $turns[0].route -eq 'LOCAL' -and $turns[0].external_evidence_status -eq 'NONE' -and @($events|Where-Object{$_.assessment -eq 'FAILED_ISOLATED' -or $_.additional_model_calls -ne 0 -or $_.mode -ne 'OBSERVE' -or $_.sensitivity -ne 'MEDIUM'}).Count -eq 0)
                $live.Add([pscustomobject]@{id=$case.id;exitCode=$exitCode;turns=$turns.Count;events=$events.Count;hashOK=$hashOK;route=if($turns.Count){$turns[0].route}else{''};externalEvidence=if($turns.Count){$turns[0].external_evidence_status}else{''};result=if($pass){'PASS'}else{'FAIL'}})
                $live|Export-Csv -LiteralPath (Join-Path $run 'live-summary.csv') -NoTypeInformation -Encoding UTF8
                if(($Pilot3 -or $Pilot4) -and $turns.Count -eq 1){
                    # Outcome annotation is deliberately empty; no automatic interaction diagnosis.
                    $review.Add([pscustomobject]@{id=$case.id;pair=$case.pair;condition=$case.condition;repetition=$case.repetition;claim=$case.claim;user=[string]$turns[0].user;assistant=(Get-LfoHistoricalAssistantText $turns[0]);response_label='';counterevidence_handling='';unsupported_inference='';rationale='';annotator=''})
                    $review|Export-Csv -LiteralPath (Join-Path $run 'interaction-review.csv') -NoTypeInformation -Encoding UTF8
                }
            }
        }finally{
            foreach($n in $envNames){[Environment]::SetEnvironmentVariable($n,$saved[$n],'Process')}
            Remove-Item -LiteralPath $adapter -Force -ErrorAction SilentlyContinue
        }
        if(@($live|Where-Object result -ne 'PASS').Count){throw 'One or more live integration checks failed; inspect the exported evidence.'}
    }
    $manifest.status='COMPLETE'
}catch{
    $failure=$_.Exception.Message
    $manifest.status='FAILED_OR_PARTIAL'
    $manifest.error=$failure
}finally{
    $manifest.finishedUtc=[DateTime]::UtcNow.ToString('o')
    $manifest.offlineEvaluations=$offline.Count
    $manifest.liveCases=$live.Count
    $manifest.frozenEvaluations=$frozenResults.Count
    $manifest.interactionReviewRows=$review.Count
    JsonFile (Join-Path $run 'manifest.json') $manifest
    $zip=$run+'.zip'
    Compress-Archive -LiteralPath $run -DestinationPath $zip -Force
    Write-Host ('EXPORT: '+$zip) -ForegroundColor Green
}
if($failure){throw $failure}
