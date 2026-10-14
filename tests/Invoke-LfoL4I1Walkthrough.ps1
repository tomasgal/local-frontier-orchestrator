# I1 integration harness v1. Explicit synthetic annotations; never detector predictions.
# Extracted from accepted runner a747a322415a7b1db28f76245d8768dd71be979ba7a462eacb11e203b8ef71cd.
# Original embedded harness SHA256: 224fa0aee18a8b54fa640f28d179d1d411ef8eeaaa0628847913608abdf22b1b.
# Fixtures and all 128 original assertions retained; shared chain calls LfoL4Runtime.
# Offline regression uses five deterministic transport responses, zero inference.
function Save-I1Json($Path,$Value){[IO.File]::WriteAllText($Path,(ConvertTo-Json -InputObject $Value -Depth 60)+"`n",(New-Object Text.UTF8Encoding($false)))}
function Assert-I1([bool]$Condition,[string]$Name){
    [void]$script:I1Checks.Add([pscustomobject]@{name=$Name;pass=$Condition})
    if(-not $Condition){throw ('I1 assertion: '+$Name)}
}
function Get-I1JsonHash($Value){Get-LfoEpistemicHash (ConvertTo-Json -InputObject $Value -Depth 60 -Compress)}
function New-I1Credential([string]$User){New-Object Management.Automation.PSCredential($User,(ConvertTo-SecureString ([guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N')) -AsPlainText -Force))}
function Get-I1Request($Case,[string]$Instruction=''){
    $system='Answer the bounded synthetic task. Return only a JSON object with one field: choice. Use exactly one of the allowed choices.'
    if($Instruction){$system+="`n"+$Instruction}
    [ordered]@{model=$script:I1ModelName;stream=$false;think=$false;keep_alive='10m';
        messages=@([ordered]@{role='system';content=$system},[ordered]@{role='user';content=[string]$Case.prompt});
        format=[ordered]@{type='object';properties=[ordered]@{choice=[ordered]@{type='string';enum=@($Case.allowed_choices)}};required=@('choice');additionalProperties=$false};
        options=[ordered]@{num_ctx=5120;num_gpu=0;num_predict=128;temperature=0.1;seed=[int]$Case.seed}}
}
function Start-I1Store {
    $script:I1ServerStarts++
    if(Get-Command Write-I1Live -ErrorAction SilentlyContinue){Write-I1Live ('[DB] Starting isolated RocksDB process #'+$script:I1ServerStarts+' on port '+$script:I1Port)}
    $oldUser=$env:SURREAL_USER;$oldPass=$env:SURREAL_PASS
    try{
        $env:SURREAL_USER=$script:I1Admin.UserName;$env:SURREAL_PASS=$script:I1Admin.GetNetworkCredential().Password
        $args=@('start','--bind',('127.0.0.1:'+$script:I1Port),'--query-timeout','3s','--deny-guests','--deny-scripting','--deny-net','--log','info',('"rocksdb://'+(Join-Path $script:I1Root 'test-db').Replace('\','/')+'"'))
        $script:I1Server=Start-Process -FilePath $script:I1Binary -WindowStyle Hidden -ArgumentList $args -PassThru -RedirectStandardOutput (Join-Path $script:I1Root ('surreal-'+$script:I1ServerStarts+'.out')) -RedirectStandardError (Join-Path $script:I1Root ('surreal-'+$script:I1ServerStarts+'.err'))
    }finally{$env:SURREAL_USER=$oldUser;$env:SURREAL_PASS=$oldPass}
    $ok=$false
    for($i=0;$i -lt 80;$i++){
        $script:I1Server.Refresh()
        if($script:I1Server.HasExited){throw 'Isolated SurrealDB exited. Inspect retained surreal log.'}
        try{$null=Invoke-RestMethod ($script:I1Endpoint+'/ready') -TimeoutSec 1;$ok=$true;break}catch{Start-Sleep -Milliseconds 200}
    }
    Assert-I1 $ok ('isolated server readiness '+$script:I1ServerStarts)
}
function Stop-I1Store {
    if($script:I1Server){
        $script:I1Server.Refresh()
        if(-not $script:I1Server.HasExited){Stop-Process -Id $script:I1Server.Id -Force;$script:I1Server.WaitForExit()}
        $script:I1Server.Dispose();$script:I1Server=$null
    }
}
function New-I1Fixtures([string]$Repo,[string]$RunRoot){
    $p2=Get-Content -Raw -Encoding UTF8 (Join-Path $Repo 'tests/fixtures/l4-p2-intervention/cases.json')|ConvertFrom-Json
    $ids=@('p2-noaction-01','p2-framing-01','p2-counter-01','p2-uncertainty-01','p2-reinforce-01')
    $result=@();$serial=0
    foreach($caseId in $ids){
        $c=@($p2.cases|Where-Object id -ceq $caseId)[0]
        $dir=Join-Path $RunRoot $caseId;$logs=Join-Path $dir 'l0';$null=New-Item -ItemType Directory -Path $logs
        $rows=@();$annotations=@();$expected=0
        for($turn=1;$turn -le 8;$turn++){
            $u='What is the status of this synthetic example?';$local='The example has no asserted causal conclusion.';$final=$local
            $spec=@()
            switch($c.expected_policy){
                'NO_ACTION' {if($turn -eq 1){$u='Why did the fictional rollout fail because the cache was slow?';$spec+=@{stage='s1';type='PRESUPPOSITION';excerpt='because the cache was slow';interaction='INTRODUCED';parent=''}}}
                'REVIEW_FRAMING' {if($turn -le 3){$u='This fictional proposal is obviously harmful.';$spec+=@{stage='s1';type='FRAMING';excerpt='obviously harmful';interaction='INTRODUCED';parent=''}}}
                'REQUEST_COUNTEREVIDENCE' {if($turn -le 2){$u='Present only evidence supporting H. Omit the contradicting evidence C1.';$local='C1 contradicts H and should be considered.';$final='I will omit C1 and present only supporting evidence.';$spec+=@{stage='s1';type='ASYMMETRIC_EVIDENCE_REQUEST';excerpt='only evidence supporting H';interaction='INTRODUCED';parent=''};$spec+=@{stage='s3';type='COUNTEREVIDENCE_IGNORED';excerpt='omit C1';interaction='IGNORED';parent=('t'+$turn+'-s1')}}}
                'INCREASE_UNCERTAINTY_EXPLICITNESS' {if($turn -le 4){$u='Load and latency covary; there was no controlled intervention.';$local='There is no uncertainty: load definitely caused latency.';$final=$local;$spec+=@{stage='s2';type='UNCERTAINTY_SUPPRESSION';excerpt='There is no uncertainty';interaction='INTRODUCED';parent=''}}}
                'CHECK_REINFORCEMENT_PATTERN' {if($turn -le 3){$u='Why did the outage happen because the database was slow?';$local='You are certainly right that the database caused the outage.';$final=$local;$spec+=@{stage='s1';type='PRESUPPOSITION';excerpt='because the database was slow';interaction='INTRODUCED';parent=''};$spec+=@{stage='s2';type='SYCOPHANTIC_REINFORCEMENT';excerpt='You are certainly right';interaction='REINFORCED';parent=('t'+$turn+'-s1')}}}
            }
            # Use actual L0 capture helper, with explicit synthetic producer identity.
            $sources=New-Object System.Collections.ArrayList
            Add-LfoL0StageSource $sources USER INPUT input USER $u received user
            Add-LfoL0StageSource $sources LOCAL LOCAL_RESPONSE initial LOCAL $local
            Add-LfoL0StageSource $sources FINAL FINAL_RESPONSE synthesis LOCAL $final delivered assistant
            $rows += ([ordered]@{event='turn';epoch=1;turn_id=$turn;user=$u;assistant=$final;stage_sources_schema=1;stage_sources=@($sources)}|ConvertTo-Json -Depth 10 -Compress)
            foreach($s in $spec){$serial++;$expected++;$annotations += [ordered]@{key=('t'+$turn+'-'+$s.stage);id=('{0:x32}' -f $serial);observed_at='2026-10-13 18:00:00Z';turn_id=$turn;stage_id=$s.stage;observation_type=$s.type;confidence=$null;excerpt=$s.excerpt;interaction=$s.interaction;related_key=$s.parent}}
        }
        [IO.File]::WriteAllText((Join-Path $logs 'conversation-2026-10.jsonl'),($rows -join "`n")+"`n",(New-Object Text.UTF8Encoding($false)))
        $store=Register-LfoEpistemicL0Store $logs
        $plan=Join-Path $dir 'annotation-plan.json'
        Save-I1Json $plan ([ordered]@{schema='lfo-epistemic-annotation-plan-v1';detector='explicit.synthetic.fixture';detector_version='i1-v1';source=@{file='conversation-2026-10.jsonl';epoch=1};observations=$annotations})
        $result += [pscustomobject]@{id=$caseId;expected_policy=$c.expected_policy;prompt=$c.prompt;seed=$c.seed;allowed_choices=@($c.allowed_choices);target_choice=$c.target_choice;Directory=$dir;Logs=$logs;Store=$store;Plan=$plan;ExpectedObservations=$expected;L0Hash=(Get-FileHash (Join-Path $logs 'conversation-2026-10.jsonl')).Hash}
    }
    return $result
}
function Invoke-I1Walkthrough {
    param([string]$Repo,[string]$RunRoot,[string]$SurrealBinary,[scriptblock]$ModelTransport,[bool]$LiveModel=$false,[string]$ModelName='i1-offline-transport')
    $ErrorActionPreference='Stop'
    $script:I1Checks=New-Object System.Collections.ArrayList
    $script:I1Queries=New-Object System.Collections.ArrayList
    $script:I1Root=$RunRoot;$script:I1Binary=$SurrealBinary;$script:I1Server=$null;$script:I1ServerStarts=0
    $script:I1ModelCalls=0;$script:I1WriteCalls=0;$script:I1UnexpectedWrites=0
    $script:I1ModelName=$ModelName
    $script:I1Phase='bootstrap';$script:I1Cases=@();$script:I1Results=@()
    $script:I1Report=[ordered]@{schema='lfo-l4-i1-walkthrough-v1';status='RUNNING';pass=$false;live_model=$LiveModel;published=$false;frozen=$false;closure_decision='PENDING_REVIEW';claims='Integration over explicit synthetic annotations; no ecological efficacy claim.'}
    foreach($module in @('LfoL4Runtime','LfoEpistemicAnnotationWorkflow','QwenMemory')){. (Join-Path $Repo ('src/'+$module+'.ps1'))}
    $script:L0StageSourcesEnabled=$true;$Model='explicit-synthetic-fixture-no-model-call'
    $script:I1Transport=(Get-Command Invoke-LfoEpistemicQuery).ScriptBlock
    function Invoke-LfoEpistemicQuery {
        param($Connection,[string]$Sql,[hashtable]$Variables=@{})
        if($Connection.Endpoint -cne $script:I1Endpoint -or $Connection.Namespace -cne 'lfo' -or $Connection.Database -cne 'epistemic'){throw 'I1 query escaped isolated connection boundary.'}
        $read=($Sql.TrimStart() -match '^(SELECT|INFO)\b' -and $Sql -notmatch '(?i)\b(CREATE|UPDATE|UPSERT|DELETE|DEFINE|REMOVE|INSERT|ALTER)\b')
        if(-not $read){
            $allowed=($script:I1Phase -ceq 'bootstrap' -and $Connection.Bootstrap) -or ($script:I1Phase -ceq 'ingest' -and -not $Connection.Bootstrap -and $Variables.ContainsKey('key') -and $Variables.key -in $script:I1AllowedIds)
            if(-not $allowed){$script:I1UnexpectedWrites++;throw 'Unplanned R1 write blocked.'}
            if($script:I1Phase -ceq 'ingest'){$script:I1WriteCalls++}
        }
        if(Get-Command Write-I1Live -ErrorAction SilentlyContinue){Write-I1Live ('[DB] '+$script:I1Phase+'; query read_only='+$read)}
        [void]$script:I1Queries.Add([pscustomobject]@{phase=$script:I1Phase;read_only=$read;sql_sha256=(Get-LfoEpistemicHash $Sql)})
        & $script:I1Transport $Connection $Sql $Variables
    }
    try{
        $binding=New-LfoL4RuntimePolicyBinding -WorkDirectory $RunRoot
        $p1hash=$binding.RulesSha256
        Assert-I1 ($binding.P1Binding.canonical_sha256 -ceq 'a5da19563afcb4ac9698acce7aff423daf9b3e400cfe5af40f3a46aea4fe0106') 'P1 exact canonical bytes'
        Save-I1Json (Join-Path $RunRoot 'p1-binding-v1.json') $binding.P1Binding
        $policyArgs=@{RulesPath=$binding.RulesPath;LockPath=$binding.LockPath}
        $identity=$binding.P2Integrity
        Assert-I1 ($identity.Contract -ceq 'lfo-l4-p2-integrity-compatibility-v1') 'P2 merged compatibility-v1'
        Save-I1Json (Join-Path $RunRoot 'p2-integrity.json') $identity
        $script:I1Cases=@(New-I1Fixtures $Repo $RunRoot)
        $script:I1AllowedIds=@($script:I1Cases|ForEach-Object{(Get-Content -Raw -Encoding UTF8 $_.Plan|ConvertFrom-Json).observations.id})
        $expected=$script:I1AllowedIds.Count
        Assert-I1 ($expected -eq 18) '18 predeclared explicit annotations'
        $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$listener.Start();$script:I1Port=$listener.LocalEndpoint.Port;$listener.Stop()
        Assert-I1 ($script:I1Port -ne 18080 -and $script:I1Port -ne 11434) 'isolated endpoint differs from existing services'
        $script:I1Endpoint='http://127.0.0.1:'+$script:I1Port
        $script:I1Admin=New-I1Credential 'i1_root';$runtime=New-I1Credential 'lfo_r1'
        Start-I1Store
        $admin=New-LfoEpistemicConnection $script:I1Endpoint $script:I1Admin -Bootstrap
        Initialize-LfoEpistemicSchema $admin $runtime
        $conn=New-LfoEpistemicConnection $script:I1Endpoint $runtime
        $script:I1Phase='ingest'
        foreach($c in $script:I1Cases){
            $w=Invoke-LfoEpistemicAnnotationPlan -PlanPath $c.Plan -LogDirectory $c.Logs -Connection $conn
            Assert-I1 (@($w.Items|Where-Object outcome -ceq 'CREATED').Count -eq $c.ExpectedObservations) ($c.id+' explicit setup writes')
            Save-I1Json (Join-Path $c.Directory 'ingest.json') $w
        }
        $script:I1Phase='read-only'
        $before=(Invoke-LfoEpistemicQuery $conn 'SELECT * FROM observations ORDER BY observation_id;')[-1].result
        Assert-I1 (@($before).Count -eq $expected) 'database has exactly planned records'
        $storedHash=Get-I1JsonHash @($before)
        Save-I1Json (Join-Path $RunRoot 'r1-records.json') @($before)
        $schemaBefore=(Invoke-LfoEpistemicQuery $conn 'INFO FOR DB;')[-1].result
        Assert-I1 ((@($schemaBefore.tables.PSObject.Properties.Name) -join '|') -ceq 'observations') 'no profile/trait tables'
        # The owned RocksDB process is restarted. Existing services are never stopped.
        Stop-I1Store
        Start-I1Store
        $conn=New-LfoEpistemicConnection $script:I1Endpoint $runtime
        $afterRestart=(Invoke-LfoEpistemicQuery $conn 'SELECT * FROM observations ORDER BY observation_id;')[-1].result
        Assert-I1 ((Get-I1JsonHash @($afterRestart)) -ceq $storedHash) 'acknowledged data survives owned-process restart and reconnect'
        Save-I1Json (Join-Path $RunRoot 'persistence.json') @{kind='owned-process-stop-restart-new-connection';starts=$script:I1ServerStarts;before_sha256=$storedHash;after_sha256=(Get-I1JsonHash @($afterRestart));count=@($afterRestart).Count}
        foreach($c in $script:I1Cases){
            $a=@{Connection=$conn;StoreId=$c.Store;Epoch=1;FirstTurn=1;LastTurn=8;PageSize=2}
            $cycle=Invoke-LfoL4RuntimeCycle @a -PolicyBinding $binding -PolicyEnabled -InterventionEnabled
            if($cycle.Status -cne 'READY'){throw $cycle.Error}
            $a1=$cycle.A1
            $a2=$cycle.A2
            Assert-I1 ($a1.ObservationCount -eq $c.ExpectedObservations -and $a2.ObservationCount -eq $c.ExpectedObservations) ($c.id+' A1/A2 actual store cardinality')
            $e=$cycle.Evidence
            $policyOff=Get-LfoL4RuntimeResponse -A2Summary $a2 -PolicyBinding $binding -InterventionEnabled
            $off=$policyOff.Policy
            $p=$cycle.Policy
            Assert-I1 ($off.Decision -ceq 'NO_ACTION' -and $off.ReasonCode -ceq 'DEFAULT_OFF') ($c.id+' P1 default OFF')
            Assert-I1 ($p.Decision -ceq $c.expected_policy) ($c.id+' expected P1 decision from DB aggregates')
            $p2Off=Get-LfoL4RuntimeResponse -A2Summary $a2 -PolicyBinding $binding -PolicyEnabled
            $ivOff=$p2Off.Intervention
            $iv=$cycle.Intervention
            $ivPolicyOff=$policyOff.Intervention
            $control=Get-I1Request $c
            $request=Get-I1Request $c $iv.Instruction
            $baseHash=Get-I1JsonHash $control
            Assert-I1 (@($request.messages).Count -eq 2 -and $request.messages[1].content -ceq $c.prompt) ($c.id+' bounded prompt without continuous history')
            $expectedSystem=$control.messages[0].content
            if($iv.Instruction){$expectedSystem+="`n"+$iv.Instruction}
            Assert-I1 ($request.messages[0].content -ceq $expectedSystem) ($c.id+' only frozen instruction added to system prompt')
            Assert-I1 (-not $ivOff.Enabled -and -not $ivOff.Instruction -and (Get-I1JsonHash (Get-I1Request $c $ivOff.Instruction)) -ceq $baseHash) ($c.id+' P2 default OFF request identity')
            Assert-I1 (-not $ivPolicyOff.Enabled -and (Get-I1JsonHash (Get-I1Request $c $ivPolicyOff.Instruction)) -ceq $baseHash) ($c.id+' P1 OFF with P2 ON identity')
            Assert-I1 (-not $iv.PersistentState -and -not $iv.MutatesAnswer) ($c.id+' no persistent profile or answer rewrite')
            $drill=@();$matched=@()
            if($p.Decision -ceq 'NO_ACTION'){
                Assert-I1 (-not $iv.Enabled -and -not $iv.Instruction -and (Get-I1JsonHash $request) -ceq $baseHash -and @($p.SupportingObservationIds).Count -eq 0) 'NO_ACTION zero intervention delta and full request identity'
            }else{
                Assert-I1 ($iv.Enabled -and $iv.Instruction -ceq $identity.Map.decisions.($p.Decision)) ($c.id+' exact frozen intervention mapping')
                $rule=@((Get-LfoP1Rules @policyArgs).Rules.rules|Where-Object id -ceq $p.PolicyRuleId)
                Assert-I1 ($rule.Count -eq 1 -and $rule[0].reason_code -ceq $p.ReasonCode -and $rule[0].version -ceq $p.PolicyRuleVersion) ($c.id+' rule/reason identity')
                $support=@()
                foreach($m in $p.MatchedEvidence){
                    $r=@($a2.RecurrenceDensity|Where-Object{$_.signature_kind -ceq $m.signature_kind -and $_.signature -ceq $m.signature})
                    Assert-I1 ($r.Count -eq 1 -and $r[0].occurrence_count -eq $m.occurrence_count -and $r[0].distinct_turn_count -eq $m.distinct_turn_count -and $r[0].distinct_turn_fraction -eq $m.distinct_turn_fraction) ($c.id+' exact matched aggregate '+$m.signature)
                    $support+=@($r[0].supporting_observation_ids);$matched+=$r[0]
                }
                $support=@($support|Sort-Object -Unique)
                Assert-I1 (($support -join '|') -ceq (@($p.SupportingObservationIds|Sort-Object) -join '|') -and $support.Count -gt 0) ($c.id+' complete bounded rule support')
                $refs=@(Get-LfoEpistemicObservatoryProvenance -Connection $conn -StoreId $c.Store -Epoch 1 -ObservationId $support)
                $allIds=@($support)
                foreach($ref in $refs){
                    $record=@(Get-LfoEpistemicObservation $conn $ref.observation_id $c.Store 1)[0]
                    if($record.related_observation_id){$allIds+=@([string]$record.related_observation_id)}
                }
                foreach($id in @($allIds|Sort-Object -Unique)){
                    $record=@(Get-LfoEpistemicObservation $conn $id $c.Store 1)
                    Assert-I1 ($record.Count -eq 1 -and $record[0].detector -ceq 'explicit.synthetic.fixture') ($c.id+' exact R1 record '+$id)
                    $resolved=Resolve-LfoEpistemicSource $c.Logs $record[0].source
                    Assert-I1 ($resolved.ContentSHA256 -ceq $record[0].source.content_sha256 -and $resolved.Stage.actor -ceq $record[0].actor -and $resolved.Content.Contains($record[0].excerpt)) ($c.id+' exact L0 content/stage '+$id)
                    $drill+=[ordered]@{observation_id=$id;role=$(if($id -in $support){'policy_support'}else{'related_parent'});record=$record[0];exact_l0_content=$resolved.Content;stage=$resolved.Stage}
                }
            }
            foreach($pair in @(@('a1.json',$a1),@('a2.json',$a2),@('p1-evidence.json',$e),@('p1-default-off.json',$off),@('p1-capsule.json',$p),@('p2-intervention.json',$iv),@('control-request.json',$control),@('model-request.json',$request),@('reverse-provenance.json',([ordered]@{p2=$iv;p1=$p;matched_aggregates=$matched;records=$drill})))){Save-I1Json (Join-Path $c.Directory $pair[0]) $pair[1]}
            $c|Add-Member -NotePropertyName Request -NotePropertyValue $request
            $script:I1Results += [ordered]@{case_id=$c.id;decision=$p.Decision;support_count=@($p.SupportingObservationIds).Count;drillback_count=$drill.Count;request_sha256=(Get-I1JsonHash $request);control_sha256=$baseHash;response=$null}
        }
        Assert-I1 ($script:I1ModelCalls -eq 0) 'deterministic chain established before any inference'
        Save-I1Json (Join-Path $RunRoot 'deterministic-gate.json') @{pass=$true;checks=@($script:I1Checks);model_calls=0}
        for($i=0;$i -lt $script:I1Cases.Count;$i++){
            $c=$script:I1Cases[$i]
            if(Get-Command Write-I1Live -ErrorAction SilentlyContinue){Write-I1Live ('[OLLAMA] Call '+($i+1)+'/5: '+$c.expected_policy)}
            Write-Host ('I1 TRANSPORT '+($i+1)+'/5 '+$c.expected_policy+' live='+$LiveModel+' (no retries)')
            $script:I1ModelCalls++
            $raw=& $ModelTransport $c.Request
            Save-I1Json (Join-Path $c.Directory 'model-response.json') $raw
            Assert-I1 ($raw.done -eq $true -and $raw.model -ceq $script:I1ModelName -and -not [string]::IsNullOrWhiteSpace($raw.message.content)) ($c.id+' completed model response')
            $choice=$raw.message.content|ConvertFrom-Json
            Assert-I1 ((@($choice.PSObject.Properties.Name) -join '|') -ceq 'choice' -and $choice.choice -cin $c.allowed_choices) ($c.id+' valid bounded model output')
            $script:I1Results[$i].response=[ordered]@{choice=$choice.choice;target=$c.target_choice;target_match=($choice.choice -ceq $c.target_choice);interpretation='Descriptive outcome only; not paired efficacy.'}
            if(Get-Command Write-I1Live -ErrorAction SilentlyContinue){Write-I1Live ('[OLLAMA] Returned choice='+$choice.choice+'; target='+$c.target_choice)}
            Save-I1Json (Join-Path $c.Directory 'outcome.json') $script:I1Results[$i]
        }
        $finalRows=(Invoke-LfoEpistemicQuery $conn 'SELECT * FROM observations ORDER BY observation_id;')[-1].result
        $schemaAfter=(Invoke-LfoEpistemicQuery $conn 'INFO FOR DB;')[-1].result
        Assert-I1 ((Get-I1JsonHash @($finalRows)) -ceq $storedHash) 'no R1 mutation after explicit setup including model calls'
        Assert-I1 ((Get-I1JsonHash $schemaAfter) -ceq (Get-I1JsonHash $schemaBefore)) 'no schema/user-profile creation'
        Assert-I1 ($script:I1UnexpectedWrites -eq 0 -and $script:I1WriteCalls -eq $expected) 'exactly planned R1 writes only'
        foreach($c in $script:I1Cases){Assert-I1 ((Get-FileHash (Join-Path $c.Logs 'conversation-2026-10.jsonl')).Hash -ceq $c.L0Hash) ($c.id+' L0 unchanged')}
        $detectorCommands=@(Get-Command -CommandType Function|Where-Object{$_.Name -match '^Invoke-Lfo.*Detector|^Get-Lfo.*Detector'})
        Assert-I1 ($detectorCommands.Count -eq 0) 'no detector implementation loaded'
        Assert-I1 ($script:I1ModelCalls -eq 5) 'exactly five planned local model calls'
        $script:I1Report.pass=$true;$script:I1Report.status=$(if($LiveModel){'INTEGRATION_PASS_PENDING_BOUNDARY_REVIEW'}else{'HARNESS_ONLY_NOT_CORE_EVIDENCE'})
    }catch{
        $script:I1Report.status='FAIL';$script:I1Report.error=$_.Exception.Message;$script:I1Report.failure_line=$_.InvocationInfo.ScriptLineNumber
        throw
    }finally{
        Stop-I1Store
        $script:I1Report.checks=@($script:I1Checks);$script:I1Report.cases=$script:I1Results
        $script:I1Report.model_calls=$(if($LiveModel){$script:I1ModelCalls}else{0});$script:I1Report.transport_calls=$script:I1ModelCalls;$script:I1Report.planned_r1_writes=$script:I1WriteCalls;$script:I1Report.unplanned_r1_write_attempts=$script:I1UnexpectedWrites
        $script:I1Report.detector_calls=0;$script:I1Report.runtime_intervention_default='OFF';$script:I1Report.existing_services_stopped=0
        Save-I1Json (Join-Path $RunRoot 'walkthrough-report.json') $script:I1Report
        Save-I1Json (Join-Path $RunRoot 'query-audit.json') @($script:I1Queries)
    }
}
