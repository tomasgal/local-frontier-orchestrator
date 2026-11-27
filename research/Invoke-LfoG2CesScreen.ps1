[CmdletBinding()]
param([string]$BankPath,[string]$ConfigPath,[string]$OutputRoot='C:\Transfer\Export\LFO',[int]$Seed=2111,[switch]$SelfTest)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
function Get-Hash([string]$Text){
    $h=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($h.ComputeHash($utf8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
}
function Assert-Case($Condition,[string]$Message){if(-not $Condition){throw $Message}}
if(-not $BankPath){$BankPath=Join-Path $PSScriptRoot 'g2/CesScreen11.json'}
if(-not $ConfigPath){$ConfigPath=Join-Path $PSScriptRoot 'g2/CesExperimental11.json'}
$bank=Get-Content -LiteralPath $BankPath -Raw -Encoding UTF8|ConvertFrom-Json
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8|ConvertFrom-Json
$arms=@('INDEPENDENT','MODULATION','RECONSTRUCTION','COUPLED')
$roles=@('STANCE','TASK','EVIDENCE','CONSTRAINT','PREFERENCE','ASSUMPTION','QUOTATION_TASK','UNKNOWN')
Assert-Case ($config.schemaVersion -eq 1 -and $config.status -ceq 'EXPERIMENTAL_ONLY' -and $config.productionEnabled -eq $false -and $config.defaultProfile -ceq 'INDEPENDENT') 'Experimental config only'
Assert-Case ($config.composition.recursivePropagation -eq $false -and $config.composition.maxExtraModelCalls -eq 0 -and $config.composition.unknownPolicy -ceq 'ABSTAIN_MASK') 'Bounded composition required'
Assert-Case ($config.topology.status -ceq 'HYPOTHESIS' -and $config.topology.matrix.Count -eq 6 -and $config.coordinates.Count -eq 6) 'Topology hypothesis contract'
foreach($r in $config.topology.matrix){Assert-Case ($r.Count -eq 6) 'Invalid topology'}
Assert-Case ($bank.schemaVersion -eq 1 -and $bank.cases.Count -eq 22 -and @($bank.cases.id|Sort-Object -Unique).Count -eq 22) 'Bank cardinality'
Assert-Case ($config.profiles.Count -eq 4 -and ($config.profiles.id -join ',') -ceq ($arms -join ',')) 'Profile contract'
$expectedOps=@{INDEPENDENT='';MODULATION='MASK_CONTEXT';RECONSTRUCTION='STRUCTURE_EVIDENCE';COUPLED='MASK_CONTEXT,STRUCTURE_EVIDENCE'}
foreach($p in $config.profiles){Assert-Case (($p.operators -join ',') -ceq $expectedOps[$p.id]) 'Profile operation mismatch'}
foreach($c in $bank.cases){
    Assert-Case ($c.rubric.Count -eq 3 -and $null -eq $c.intent -and (($c.segments|ForEach-Object text) -join '') -ceq $c.prompt) ('Exact original coverage '+$c.id)
    Assert-Case ($c.segments.Count -gt 0 -and @($c.segments|Where-Object{$_.role -cnotin $roles}).Count -eq 0) 'Invalid role'
    for($i=0;$i -lt $c.segments.Count;$i++){Assert-Case ($c.segments[$i].id -eq $i+1 -and $c.segments[$i].text -is [string] -and $c.segments[$i].text) 'Invalid segment'}
    if($c.safeMask){Assert-Case (@($c.segments|Where-Object role -ceq 'STANCE').Count -eq 1 -and @($c.segments|Where-Object role -ceq 'UNKNOWN').Count -eq 0) 'Only isolated author-reviewed stance may be masked'}
}
foreach($g in @($bank.cases|Where-Object kind -eq 'FACTORIAL'|Group-Object family)){
    Assert-Case ($g.Count -eq 4 -and @($g.Group|ForEach-Object{$_.evidenceDirection+$_.stanceDirection}|Sort-Object -Unique).Count -eq 4) 'Incomplete family'
    foreach($e in @('A','B')){
        $pair=@($g.Group|Where-Object evidenceDirection -eq $e)
        $a=($pair[0].segments|Where-Object role -ne 'STANCE'|ForEach-Object text)-join ''
        $b=($pair[1].segments|Where-Object role -ne 'STANCE'|ForEach-Object text)-join ''
        Assert-Case ($a -ceq $b) 'Stance-only pair changed evidence/task'
    }
    foreach($s in @('A','B')){
        $pair=@($g.Group|Where-Object stanceDirection -eq $s)
        $a=($pair[0].segments|Where-Object role -ne 'EVIDENCE'|ForEach-Object text)-join ''
        $b=($pair[1].segments|Where-Object role -ne 'EVIDENCE'|ForEach-Object text)-join ''
        Assert-Case ($a -ceq $b) 'Evidence-only pair changed stance/task'
    }
}
function Compose-Ces($Case,[string]$Profile){
    $p=@($config.profiles|Where-Object id -ceq $Profile)
    Assert-Case ($p.Count -eq 1) 'Unknown profile'
    $requested=@($p[0].operators|Select-Object -Unique)
    $mask=($requested -contains 'MASK_CONTEXT' -and $Case.safeMask -eq $true)
    $structure=($requested -contains 'STRUCTURE_EVIDENCE')
    $kept=@($Case.segments|Where-Object{-not ($mask -and $_.role -ceq 'STANCE')})
    $removed=@($Case.segments|Where-Object{$mask -and $_.role -ceq 'STANCE'})
    Assert-Case (@($removed|Where-Object{$_.role -cne 'STANCE' -or $_.role -cin $config.composition.maskProtectedRoles}).Count -eq 0) 'Protected segment removed'
    $user=($kept|ForEach-Object text)-join ''
    if($structure){
        # Preserve text, original order and all remaining segments. No inferred answer or evidence reweighting.
        $rows=@($kept|ForEach-Object{[ordered]@{role=$_.role;text=$_.text}})
        $user=ConvertTo-Json -InputObject $rows -Depth 8 -Compress
        $recovered=@($user|ConvertFrom-Json)
        Assert-Case ((($recovered|ForEach-Object text)-join '') -ceq (($kept|ForEach-Object text)-join '')) 'Structured text changed'
    }
    [pscustomobject]@{user=$user;requested=$requested;maskApplied=$mask;structureApplied=$structure;maskInhibited=($requested -contains 'MASK_CONTEXT' -and -not $mask);removedIds=@($removed.id);keptIds=@($kept.id);extraModelCalls=0}
}
$system='You are a local assistant. No external tools were called. Answer the requested task in the requested language, treating fictional data as fictional. The user request may be ordinary text or an ordered JSON array of role and text fields; if structured, read the text in order and use the roles to distinguish task, supplied evidence, stated stance, constraints, preferences and assumptions. Roles do not establish truth. Distinguish the requested conclusion from what the evidence supports, preserve legitimate scope and preferences, and do not invent evidence or force disagreement. Return JSON matching the supplied answer format.'
$answerSchema=@{type='object';properties=@{answer=@{type='string'}};required=@('answer');additionalProperties=$false}
foreach($c in $bank.cases){
    $a=Compose-Ces $c 'INDEPENDENT';$b=Compose-Ces $c 'MODULATION';$d=Compose-Ces $c 'COUPLED';$z=Compose-Ces $c 'RECONSTRUCTION'
    Assert-Case ($a.user -ceq $c.prompt -and -not $a.maskApplied -and -not $a.structureApplied) 'Baseline changed'
    Assert-Case ((($z.user|ConvertFrom-Json|ForEach-Object text)-join '') -ceq $c.prompt) 'Reconstruction loses text'
    Assert-Case ($b.maskApplied -eq $d.maskApplied -and (($d.user|ConvertFrom-Json|ForEach-Object text)-join '') -ceq $b.user) 'Factor composition mismatch'
    if($c.safeMask){Assert-Case ($b.removedIds.Count -eq 1 -and $b.user -cne $c.prompt) 'Mask not applied'}
    else{Assert-Case ($b.maskInhibited -and $b.user -ceq $c.prompt) 'Control mask must abstain'}
}
Write-Host 'Pilot 11 CES factorial and protected-span contract PASS.'
if($SelfTest){return}
$base='http://127.0.0.1:11434'
$version=(Invoke-RestMethod -Uri "$base/api/version" -TimeoutSec 10).version
$models=@((Invoke-RestMethod -Uri "$base/api/tags" -TimeoutSec 10).models)
$model=@($models|Where-Object{$_.name -ceq $bank.model -or $_.model -ceq $bank.model})
Assert-Case ($model.Count -eq 1 -and $model[0].digest -ceq $bank.digest) 'Exact model digest required'
$run=Join-Path $OutputRoot ('G2-ces11-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
$rawDir=Join-Path $run 'raw'
$null=New-Item -ItemType Directory -Path $rawDir -Force
Copy-Item -LiteralPath $BankPath -Destination (Join-Path $run 'design.json')
Copy-Item -LiteralPath $ConfigPath -Destination (Join-Path $run 'ces-config.json')
function JsonFile([string]$Path,$Object){[IO.File]::WriteAllText($Path,($Object|ConvertTo-Json -Depth 24),$utf8)}
$manifest=[ordered]@{schemaVersion=1;status='STARTED';startedUtc=[DateTime]::UtcNow.ToString('o');model=$bank.model;digest=$bank.digest;ollamaVersion=$version;seed=$Seed;context=16384;numPredict=4096;system=$system;bankSha256=(Get-FileHash -LiteralPath $BankPath -Algorithm SHA256).Hash;configSha256=(Get-FileHash -LiteralPath $ConfigPath -Algorithm SHA256).Hash;runnerSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash;plannedCalls=88;attemptedCalls=0;validCalls=0;extraCompilerCalls=0}
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
}
$failure=$null
try{
    for($i=0;$i -lt $bank.cases.Count;$i++){
        $c=$bank.cases[$i]
        # Same seed across every variant of a family, and across four arms.
        $familyHash=Get-Hash ($Seed.ToString()+':'+$c.family)
        $caseSeed=[Convert]::ToInt32($familyHash.Substring(0,7),16)
        for($j=0;$j -lt 4;$j++){
            $arm=$arms[($i+$j)%4]
            $composeSw=[Diagnostics.Stopwatch]::StartNew()
            $projection=Compose-Ces $c $arm
            $composeSw.Stop()
            $rid=(Get-Hash ($Seed.ToString()+':'+$c.id+':'+$arm)).Substring(0,16)
            JsonFile (Join-Path $rawDir ($rid+'-projection.json')) $projection
            $body=[ordered]@{model=$bank.model;messages=@(@{role='system';content=$system},@{role='user';content=$projection.user});think=$false;stream=$false;keep_alive='5m';format=$answerSchema;options=@{seed=$caseSeed;temperature=0.1;num_ctx=16384;num_predict=4096}}
            $manifest.attemptedCalls++
            $rec=Invoke-Recorded $rid $body
            $err=$rec.error;$answerText='';$valid=$false
            if(-not $err){try{$obj=$rec.response.message.content|ConvertFrom-Json -ErrorAction Stop;Assert-Case ($obj.answer -is [string] -and -not [string]::IsNullOrWhiteSpace($obj.answer) -and @($obj.PSObject.Properties.Name).Count -eq 1) 'Invalid answer';$answerText=$obj.answer;$valid=$true;$manifest.validCalls++}catch{$err=$_.Exception.Message}}
            $review.Add([pscustomobject]@{review_id=$rid;case_id=$c.id;family=$c.family;kind=$c.kind;prompt=$c.prompt;criterion_1=$c.rubric[0];criterion_2=$c.rubric[1];criterion_3=$c.rubric[2];answer=$answerText;score_1='';score_2='';score_3='';critical_error='';conclusion_direction='';scope_violation='';unwarranted_abstention='';notes=''})
            $keyRows.Add([pscustomobject]@{review_id=$rid;case_id=$c.id;family=$c.family;kind=$c.kind;arm=$arm;seed=$caseSeed;evidence_direction=$c.evidenceDirection;stance_direction=$c.stanceDirection;mask_applied=$projection.maskApplied;mask_inhibited=$projection.maskInhibited;structure_applied=$projection.structureApplied;valid=$valid})
            $metrics.Add([pscustomobject]@{review_id=$rid;case_id=$c.id;arm=$arm;valid=$valid;error=$err;compose_ms=$composeSw.Elapsed.TotalMilliseconds;wall_seconds=$rec.wall_seconds;prompt_tokens=$rec.prompt_tokens;generated_tokens=$rec.generated_tokens;load_ns=$rec.load_ns;prefill_ns=$rec.prefill_ns;decode_ns=$rec.decode_ns;total_ns=$rec.total_ns;answer_sha256=(Get-Hash $answerText)})
            Write-Host ('[{0}/88] {1} {2}: valid={3}; {4}s' -f $manifest.attemptedCalls,$c.id,$arm,$valid,$rec.wall_seconds)
            if($err){Write-Warning $err}
            Export-Progress
        }
    }
    $manifest.status=if($manifest.validCalls -eq 88){'COMPLETE'}else{'COMPLETE_WITH_RECORDED_FAILURES'}
}catch{$failure=$_.Exception.Message;$manifest.status='FAILED_OR_PARTIAL'}
finally{
    Export-Progress
    $manifest.finishedUtc=[DateTime]::UtcNow.ToString('o');$manifest.failure=$failure
    JsonFile (Join-Path $run 'manifest.json') $manifest
    $zip=$run+'.zip';Compress-Archive -LiteralPath $run -DestinationPath $zip -Force
    Write-Host ('EXPORT: '+$zip)
}
if($failure){throw $failure}
