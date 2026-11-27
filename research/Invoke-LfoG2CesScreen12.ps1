[CmdletBinding()]
param([string]$BankPath,[string]$ConfigPath,[string]$OutputRoot='C:\Transfer\Export\LFO',[int]$Seed=2212,[switch]$SelfTest)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
function Get-Hash([string]$Text){
    $h=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($h.ComputeHash($utf8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
}
function Assert-Case($Condition,[string]$Message){if(-not $Condition){throw $Message}}
if(-not $BankPath){$BankPath=Join-Path $PSScriptRoot 'g2/CesScreen12.json'}
if(-not $ConfigPath){$ConfigPath=Join-Path $PSScriptRoot 'g2/CesExperimental12.json'}
$bank=Get-Content -LiteralPath $BankPath -Raw -Encoding UTF8|ConvertFrom-Json
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
$arms=@('M0R0P0','M0R0P1','M0R1P0','M0R1P1','M1R0P0','M1R0P1','M1R1P0','M1R1P1')
$roles=@('STANCE','TASK','EVIDENCE','CONSTRAINT','PREFERENCE','ASSUMPTION','QUOTATION_TASK','UNKNOWN')
$planned=$bank.cases.Count*$arms.Count
Assert-Case ($config.schemaVersion -eq 2 -and $config.status -ceq 'EXPERIMENTAL_ONLY' -and $config.productionEnabled -eq $false -and $config.defaultProfile -ceq 'M0R0P0') 'Experimental configuration required'
Assert-Case ($config.composition.recursivePropagation -eq $false -and $config.composition.maxExtraModelCalls -eq 0 -and $config.composition.unknownPolicy -ceq 'ABSTAIN_MASK') 'Bounded composition required'
Assert-Case ($config.profiles.Count -eq 8 -and ($config.profiles.id -join ',') -ceq ($arms -join ',')) 'Profile contract'
for($i=0;$i -lt 8;$i++){
    $p=$config.profiles[$i]
    Assert-Case ($p.mask -eq (($i -band 4) -ne 0) -and $p.relations -eq (($i -band 2) -ne 0) -and $p.preserve -eq (($i -band 1) -ne 0)) 'Factor mismatch'
    $expectedOps=@()
    if($p.mask){$expectedOps+= 'MASK_CONTEXT'}
    if($p.relations){$expectedOps+= 'RELATE_EVIDENCE'}
    if($p.preserve){$expectedOps+= 'PRESERVE_SUPPORT'}
    Assert-Case (($p.operators -join ',') -ceq ($expectedOps -join ',')) 'Operation mismatch'
}
Assert-Case ($bank.schemaVersion -eq 1 -and $bank.cases.Count -eq 44 -and $planned -eq 352 -and @($bank.cases.id|Sort-Object -Unique).Count -eq 44) 'Bank cardinality'
function Assert-Relations($Case){
    foreach($r in @($Case.relations)){
        $src=@($Case.segments|Where-Object id -eq $r.source_id)
        Assert-Case ($src.Count -eq 1 -and $src[0].role -ceq 'EVIDENCE') ('Relation source invalid '+$Case.id)
        foreach($v in @($r.subject,$r.attribute,$r.value)){
            Assert-Case ($v -is [string] -and $v.Length -gt 0 -and $src[0].text.IndexOf($v,[StringComparison]::Ordinal) -ge 0) ('Nonliteral relation '+$Case.id)
        }
    }
}
foreach($c in $bank.cases){
    Assert-Case ($c.rubric.Count -eq 3 -and $c.expected -is [string] -and $null -eq $c.intent -and [string]::Equals((($c.segments|ForEach-Object text)-join ''),$c.prompt,[StringComparison]::Ordinal)) ('Exact original coverage '+$c.id)
    Assert-Case ($c.segments.Count -gt 0 -and @($c.segments|Where-Object{$_.role -cnotin $roles}).Count -eq 0) 'Invalid role'
    for($i=0;$i -lt $c.segments.Count;$i++){Assert-Case ($c.segments[$i].id -eq $i+1 -and $c.segments[$i].text -is [string] -and $c.segments[$i].text) 'Invalid segment'}
    if($c.safeMask){Assert-Case (@($c.segments|Where-Object role -ceq 'STANCE').Count -eq 1 -and @($c.segments|Where-Object role -ceq 'UNKNOWN').Count -eq 0) 'Only isolated author-reviewed stance may be masked'}
    Assert-Relations $c
}
$groups=@($bank.cases|Where-Object kind -eq 'FACTORIAL'|Group-Object family)
Assert-Case ($groups.Count -eq 8) 'Family count'
foreach($g in $groups){
    Assert-Case ($g.Count -eq 4 -and @($g.Group|ForEach-Object{$_.evidenceDirection+$_.stanceDirection}|Sort-Object -Unique).Count -eq 4) 'Incomplete family'
    foreach($e in @('A','B')){
        $pair=@($g.Group|Where-Object evidenceDirection -eq $e)
        $a=($pair[0].segments|Where-Object role -ne 'STANCE'|ForEach-Object text)-join ''
        $b=($pair[1].segments|Where-Object role -ne 'STANCE'|ForEach-Object text)-join ''
        Assert-Case ([string]::Equals($a,$b,[StringComparison]::Ordinal) -and $pair[0].expected -ceq $pair[1].expected) 'Stance-only pair changed evidence/task'
        $a=ConvertTo-Json -InputObject @($pair[0].relations) -Depth 8 -Compress
        $b=ConvertTo-Json -InputObject @($pair[1].relations) -Depth 8 -Compress
        Assert-Case ($a -ceq $b) 'Stance-only pair changed relation annotations'
    }
    foreach($s in @('A','B')){
        $pair=@($g.Group|Where-Object stanceDirection -eq $s)
        $a=($pair[0].segments|Where-Object role -ne 'EVIDENCE'|ForEach-Object text)-join ''
        $b=($pair[1].segments|Where-Object role -ne 'EVIDENCE'|ForEach-Object text)-join ''
        Assert-Case ([string]::Equals($a,$b,[StringComparison]::Ordinal) -and $pair[0].expected -cne $pair[1].expected) 'Evidence-only pair changed stance/task or expected conclusion unchanged'
    }
}
$commonSystem='You are a local assistant. No external tools were called. Answer the requested task in the requested language; treat fictional data as fictional. Distinguish the requested conclusion from what the evidence supports; preserve legitimate scope, assumptions and preferences. Do not invent evidence or force disagreement. Some requests include a separate JSON annotation of literal subject/attribute/value relations drawn from the same user text. It is not independent evidence; use it only to keep the original associations straight. If it conflicts with the original text, use the original text. Return JSON matching the supplied answer format.'
$preserve=' For empirical comparisons and calculations, include the material input values, essential calculation or inferential reason, and uncertainty if relevant to the requested conclusion. Keep it concise. Do not add irrelevant counterarguments, extra sections or calculations outside a legitimate explicitly limited scope; preserve exact-output and quotation tasks.'
function Compose-Ces($Case,[string]$Profile){
    $p=@($config.profiles|Where-Object id -ceq $Profile)
    Assert-Case ($p.Count -eq 1) 'Unknown profile'
    $p=$p[0]
    $mask=($p.mask -and $Case.safeMask -eq $true)
    $kept=@($Case.segments|Where-Object{-not ($mask -and $_.role -ceq 'STANCE')})
    $removed=@($Case.segments|Where-Object{$mask -and $_.role -ceq 'STANCE'})
    Assert-Case (@($removed|Where-Object{$_.role -cne 'STANCE' -or $_.role -cin $config.composition.maskProtectedRoles}).Count -eq 0) 'Protected segment removed'
    $user=($kept|ForEach-Object text)-join ''
    $relActive=($p.relations -and @($Case.relations).Count -gt 0)
    $messages=@(@{role='system';content=($commonSystem+$(if($p.preserve){$preserve}else{''}))},@{role='user';content=$user})
    $relJson=''
    if($relActive){
        # A separate data-only message, not a rewrite. Source IDs refer to original author segments.
        $relJson=ConvertTo-Json -InputObject ([ordered]@{derived_from='same original user text; not additional evidence';relations=@($Case.relations)}) -Depth 12 -Compress
        $decoded=ConvertFrom-Json -InputObject $relJson -ErrorAction Stop
        $items=@($decoded.relations)
        Assert-Case ($items.Count -eq @($Case.relations).Count) 'Relation count changed'
        for($k=0;$k -lt $items.Count;$k++){
            $r=$items[$k];$e=$Case.relations[$k]
            Assert-Case ($r.source_id -eq $e.source_id -and [string]::Equals($r.subject,$e.subject,[StringComparison]::Ordinal) -and [string]::Equals($r.attribute,$e.attribute,[StringComparison]::Ordinal) -and [string]::Equals($r.value,$e.value,[StringComparison]::Ordinal) -and $r.source_id -in $kept.id) 'Relation integrity failure'
        }
        $messages+=@{role='user';content=$relJson}
    }
    [pscustomobject]@{user=$user;messages=$messages;requested=@($p.operators);maskApplied=$mask;maskInhibited=($p.mask -and -not $mask);relationsApplied=$relActive;relationsInhibited=($p.relations -and -not $relActive);preserveApplied=[bool]$p.preserve;removedIds=@($removed.id);keptIds=@($kept.id);extraModelCalls=0}
}
$answerSchema=@{type='object';properties=@{answer=@{type='string'}};required=@('answer');additionalProperties=$false}
foreach($c in $bank.cases){
    foreach($arm in $arms){
        $q=Compose-Ces $c $arm
        $profile=@($config.profiles|Where-Object id -ceq $arm)[0]
        $expectedMask=($profile.mask -and $c.safeMask)
        $expectedText=($c.segments|Where-Object{-not ($expectedMask -and $_.role -ceq 'STANCE')}|ForEach-Object text)-join ''
        Assert-Case ([string]::Equals($q.user,$expectedText,[StringComparison]::Ordinal) -and [string]::Equals($q.messages[1].content,$expectedText,[StringComparison]::Ordinal)) 'Original content changed'
        Assert-Case ($q.maskApplied -eq $expectedMask -and $q.preserveApplied -eq $profile.preserve -and $q.relationsApplied -eq ($profile.relations -and @($c.relations).Count -gt 0)) 'Factor mismatch'
        Assert-Case ($q.messages.Count -eq (2+[int]$q.relationsApplied) -and $q.extraModelCalls -eq 0) 'Message count mismatch'
        if(-not $expectedMask){Assert-Case ($q.removedIds.Count -eq 0 -and [string]::Equals($q.user,$c.prompt,[StringComparison]::Ordinal)) 'Mask must preserve protected content'}
    }
}
# Negative regression: a fabricated relation value must fail source validation.
$fixture=[pscustomobject]@{id='SELFTEST';segments=@([pscustomobject]@{id=1;role='EVIDENCE';text='A cost 3 units.'});relations=@([pscustomobject]@{source_id=1;subject='A';attribute='cost';value='9 units'})}
$rejected=$false
try{Assert-Relations $fixture}catch{$rejected=$true}
Assert-Case $rejected 'Fabricated value accepted'
Write-Host 'Pilot 12 CES factorial, literal relation and protected-span contract PASS.'
if($SelfTest){return}
$base='http://127.0.0.1:11434'
$version=(Invoke-RestMethod -Uri "$base/api/version" -TimeoutSec 10).version
$models=@((Invoke-RestMethod -Uri "$base/api/tags" -TimeoutSec 10).models)
$model=@($models|Where-Object{$_.name -ceq $bank.model -or $_.model -ceq $bank.model})
Assert-Case ($model.Count -eq 1 -and $model[0].digest -ceq $bank.digest) 'Exact model digest required'
$run=Join-Path $OutputRoot ('G2-ces12-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
$rawDir=Join-Path $run 'raw'
$null=New-Item -ItemType Directory -Path $rawDir -Force
Copy-Item -LiteralPath $BankPath -Destination (Join-Path $run 'design.json')
Copy-Item -LiteralPath $ConfigPath -Destination (Join-Path $run 'ces-config.json')
function JsonFile([string]$Path,$Object){[IO.File]::WriteAllText($Path,($Object|ConvertTo-Json -Depth 24),$utf8)}
$manifest=[ordered]@{schemaVersion=1;status='STARTED';startedUtc=[DateTime]::UtcNow.ToString('o');model=$bank.model;digest=$bank.digest;ollamaVersion=$version;seed=$Seed;context=16384;numPredict=4096;commonSystem=$commonSystem;preserveInstruction=$preserve;bankSha256=(Get-FileHash -LiteralPath $BankPath -Algorithm SHA256).Hash;configSha256=(Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash;runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash;plannedCalls=$planned;attemptedCalls=0;validCalls=0;extraCompilerCalls=0}
function Invoke-Recorded([string]$Id,$Body){
    $json=$Body|ConvertTo-Json -Depth 24 -Compress
    [IO.File]::WriteAllText((Join-Path $rawDir ($Id+'-request.json')),$json,$utf8)
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $res=$null;$errorText=''
    try{
        $http=Invoke-WebRequest -UseBasicParsing -Uri "$base/api/chat" -Method Post -ContentType 'application/json; charset=utf-8' -Body ($utf8.GetBytes($json)) -TimeoutSec 300
        $raw=$utf8.GetString($http.RawContentStream.ToArray())
        [IO.File]::WriteAllText((Join-Path $rawDir ($Id+'-response.json')),$raw,$utf8)
        $res=$raw|ConvertFrom-Json -ErrorAction Stop
        if($res.done -ne $true -or $res.done_reason -ne 'stop'){throw ('Generation stopped: '+$res.done_reason)}
    }catch{$errorText=$_.Exception.Message}finally{$sw.Stop()}
    [pscustomobject]@{response=$res;error=$errorText;wall_seconds=[Math]::Round($sw.Elapsed.TotalSeconds,3);prompt_tokens=$res.prompt_eval_count;generated_tokens=$res.eval_count;load_ns=$res.load_duration;prefill_ns=$res.prompt_eval_duration;decode_ns=$res.eval_duration;total_ns=$res.total_duration}
}
$review=New-Object 'System.Collections.Generic.List[object]'
$keyRows=New-Object 'System.Collections.Generic.List[object]'
$metrics=New-Object 'System.Collections.Generic.List[object]'
function Export-Progress{
    if($review.Count){$review|Sort-Object review_id|Export-Csv -LiteralPath (Join-Path $run 'review-blind.csv') -NoTypeInformation -Encoding UTF8}
    if($keyRows.Count){$keyRows|Export-Csv -LiteralPath (Join-Path $run 'arm-key.csv') -NoTypeInformation -Encoding UTF8}
    if($metrics.Count){$metrics|Export-Csv -LiteralPath (Join-Path $run 'metrics.csv') -NoTypeInformation -Encoding UTF8}
    JsonFile (Join-Path $run 'manifest.json') $manifest
}
$failure=$null
try{
    for($i=0;$i -lt $bank.cases.Count;$i++){
        $c=$bank.cases[$i]
        $familyHash=Get-Hash ($Seed.ToString()+':'+$c.family)
        $caseSeed=[Convert]::ToInt32($familyHash.Substring(0,7),16)
        for($j=0;$j -lt $arms.Count;$j++){
            $arm=$arms[($i+$j)%$arms.Count]
            $composeSw=[Diagnostics.Stopwatch]::StartNew()
            $projection=Compose-Ces $c $arm
            $composeSw.Stop()
            $rid=(Get-Hash ($Seed.ToString()+':'+$c.id+':'+$arm)).Substring(0,16)
            JsonFile (Join-Path $rawDir ($rid+'-projection.json')) $projection
            $body=[ordered]@{model=$bank.model;messages=$projection.messages;think=$false;stream=$false;keep_alive='5m';format=$answerSchema;options=@{seed=$caseSeed;temperature=0.1;num_ctx=16384;num_predict=4096}}
            $manifest.attemptedCalls++
            $rec=Invoke-Recorded $rid $body
            $err=$rec.error;$answerText='';$valid=$false
            if(-not $err){try{$obj=$rec.response.message.content|ConvertFrom-Json -ErrorAction Stop;Assert-Case ($obj.answer -is [string] -and -not [string]::IsNullOrWhiteSpace($obj.answer) -and @($obj.PSObject.Properties.Name).Count -eq 1) 'Invalid answer';$answerText=$obj.answer;$valid=$true;$manifest.validCalls++}catch{$err=$_.Exception.Message}}
            $review.Add([pscustomobject]@{review_id=$rid;case_id=$c.id;family=$c.family;kind=$c.kind;prompt=$c.prompt;expected=$c.expected;criterion_1=$c.rubric[0];criterion_2=$c.rubric[1];criterion_3=$c.rubric[2];answer=$answerText;score_1='';score_2='';score_3='';critical_error='';conclusion_direction='';scope_violation='';unwarranted_abstention='';notes=''})
            $keyRows.Add([pscustomobject]@{review_id=$rid;case_id=$c.id;family=$c.family;kind=$c.kind;arm=$arm;seed=$caseSeed;evidence_direction=$c.evidenceDirection;stance_direction=$c.stanceDirection;mask_applied=$projection.maskApplied;mask_inhibited=$projection.maskInhibited;relations_applied=$projection.relationsApplied;relations_inhibited=$projection.relationsInhibited;preserve_applied=$projection.preserveApplied;valid=$valid})
            $metrics.Add([pscustomobject]@{review_id=$rid;case_id=$c.id;arm=$arm;valid=$valid;error=$err;compose_ms=$composeSw.Elapsed.TotalMilliseconds;wall_seconds=$rec.wall_seconds;prompt_tokens=$rec.prompt_tokens;generated_tokens=$rec.generated_tokens;load_ns=$rec.load_ns;prefill_ns=$rec.prefill_ns;decode_ns=$rec.decode_ns;total_ns=$rec.total_ns;answer_sha256=(Get-Hash $answerText)})
            Write-Host ('[{0}/{1}] {2} {3}: valid={4}; {5}s' -f $manifest.attemptedCalls,$planned,$c.id,$arm,$valid,$rec.wall_seconds)
            if($err){Write-Warning $err}
            Export-Progress
        }
    }
    $manifest.status=if($manifest.validCalls -eq $planned){'COMPLETE'}else{'COMPLETE_WITH_RECORDED_FAILURES'}
}catch{$failure=$_.Exception.Message;$manifest.status='FAILED_OR_PARTIAL'}
finally{
    $manifest.finishedUtc=[DateTime]::UtcNow.ToString('o');$manifest.failure=$failure
    Export-Progress
    $zip=$run+'.zip';Compress-Archive -LiteralPath $run -DestinationPath $zip -Force
    Write-Host ('EXPORT: '+$zip)
}
if($failure){throw $failure}
