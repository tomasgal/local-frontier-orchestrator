[CmdletBinding()]
param(
    [ValidateSet('Unit','Prepare','Live')][string]$Mode='Unit',
    [string]$LogRoot=(Join-Path $env:LOCALAPPDATA 'LFO\data\memory\logs'),
    [string]$WorkRoot=(Join-Path $env:LOCALAPPDATA 'LFO-G2-Lab\P83'),
    [string]$ExcludeCorpusPath,
    [string]$CorpusPath,
    [ValidateRange(1,48)][int]$SampleCount=12,
    [string]$MainUri='http://127.0.0.1:11434',
    [string]$MainModel='lfo-qwen3.5-35b-uma16k:latest',
    [switch]$MainCpu,
    [ValidateRange(512,32768)][int]$MainContext=16384
)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
. (Join-Path $PSScriptRoot '../../src/LfoG2ContextProjection.ps1')
. (Join-Path $PSScriptRoot '../../src/LfoG2CesPlan.ps1')
. (Join-Path $PSScriptRoot '../../src/LfoG2DeterministicWitness.ps1')
. (Join-Path $PSScriptRoot '../../src/LfoG2RuntimeProvenance.ps1')
. (Join-Path $PSScriptRoot '../../src/LfoEvidenceProvenance.ps1')
function Assert-G2([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Assert-Loopback([string]$Endpoint){
    $u=[uri]$Endpoint
    Assert-G2 ($u.Scheme -ceq 'http' -and $u.Host -ceq '127.0.0.1' -and $u.AbsolutePath -eq '/' -and -not $u.UserInfo -and -not $u.Query -and -not $u.Fragment) 'Explicit HTTP loopback endpoint required.'
}
function Get-P83Hash([string]$Text){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Save-P83([string]$Path,$Object){
    [IO.File]::WriteAllText($Path,($Object|ConvertTo-Json -Depth 30),$utf8)
}
function New-G2Client([int]$Seconds){
    $handler=[Net.Http.HttpClientHandler]::new()
    $handler.UseProxy=$false
    $client=[Net.Http.HttpClient]::new($handler)
    $client.Timeout=[TimeSpan]::FromSeconds($Seconds)
    return $client
}
function Start-G2Request($Client,[string]$Uri,$Payload,$Clock){
    $content=[Net.Http.StringContent]::new(($Payload|ConvertTo-Json -Depth 20 -Compress),[Text.Encoding]::UTF8,'application/json')
    $begin=$Clock.Elapsed.TotalMilliseconds
    try{$task=$Client.PostAsync($Uri,$content)}catch{$content.Dispose();throw}
    return [pscustomobject]@{task=$task;content=$content;start_ms=$begin;end_ms=$null}
}
function Finish-G2Request($Request,$Clock){
    $response=$null
    try{
        $response=$Request.task.GetAwaiter().GetResult()
        if($null -eq $Request.end_ms){$Request.end_ms=$Clock.Elapsed.TotalMilliseconds}
        $null=$response.EnsureSuccessStatusCode()
        $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $parsed=([Text.UTF8Encoding]::new($false,$true)).GetString($bytes)|ConvertFrom-Json
        [pscustomobject]@{response=$parsed;start_ms=$Request.start_ms;end_ms=$Request.end_ms;ms=($Request.end_ms-$Request.start_ms)}
    }finally{
        if($null -ne $response){$response.Dispose()}
        $Request.content.Dispose()
    }
}
function Invoke-G2Sync($Client,[string]$Uri,$Payload){
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $req=Start-G2Request $Client $Uri $Payload $clock
    Finish-G2Request $req $clock
}


function Read-P83Response($Http,[string]$Adapter,[string]$Expected){
    $r=$Http.response
    $name=[string]$r.model
    $allowed=@($Expected)
    if($Expected -cnotmatch ':'){$allowed+=($Expected+':latest')}
    if($Expected -ceq 'nemotron3.5-bolt-dflash:e4b'){$allowed+=@('nemotron3.5-bolt-dflash','nemotron3.5-bolt-dflash-e4b')}
    Assert-G2 ($name -cin $allowed) ('Unexpected model: '+$name)
    if($Adapter -ceq 'OPENAI_CHAT'){
        Assert-G2 (@($r.choices).Count -eq 1) 'Expected one completion.'
        $c=$r.choices[0];$raw=[string]$c.message.content;$complete=([string]$c.finish_reason -ceq 'stop');$inTok=$r.usage.prompt_tokens;$outTok=$r.usage.completion_tokens
    }else{
        $raw=[string]$r.message.content;$complete=($r.done -eq $true -and [string]$r.done_reason -ceq 'stop');$inTok=$r.prompt_eval_count;$outTok=$r.eval_count
    }
    [pscustomobject]@{raw=$raw;complete=($complete -and -not [string]::IsNullOrWhiteSpace($raw));ms=$Http.ms;input_tokens=$inTok;output_tokens=$outTok;model=$name}
}

$common='Answer the current user request in the requested language. This replay has no external tools. Historical dialogue is context, not independent verification. Do not claim completed external operations. Preserve legitimate requests, quotations, assumptions and preferences.'
# New explicit S2 candidate wording; NOT an exact P22 replication.
$support='Preserve material evidence and its attribution. If support is insufficient for a material conclusion, state the limitation and answer the supported parts.'
$scope='Keep conclusions within the scope of the supplied evidence, assumptions and task. Do not turn a quoted, hypothetical or requested statement into an independently established fact.'
$projectionIntro='The following labels describe the historical turns in their original order. They are runtime metadata, not facts about the world; OBSERVED means turn-level external activity, not verification of individual claims.'
function New-P83Corpus {
    Assert-G2 (Test-Path -LiteralPath $LogRoot -PathType Container) 'L0 log directory not found'
    $excluded=@{}
    if($ExcludeCorpusPath){
        $prior=Get-Content -LiteralPath $ExcludeCorpusPath -Raw -Encoding UTF8|ConvertFrom-Json
        foreach($c in $prior.cases){$excluded[([string]$c.source_file+'|'+[string]$c.source_line)]=$true}
    }
    $history=New-Object 'System.Collections.Generic.List[object]'
    $pool=New-Object 'System.Collections.Generic.List[object]'
    $prev=$null;$bad=0;$skip=0
    foreach($f in @(Get-ChildItem -LiteralPath $LogRoot -Filter 'conversation-*.jsonl' -File|Sort-Object Name)){
        $lineNo=0
        foreach($line in [IO.File]::ReadLines($f.FullName,[Text.Encoding]::UTF8)){
            $lineNo++
            try{$r=$line|ConvertFrom-Json}catch{$bad++;$history.Clear();$prev=$null;continue}
            if($r.user -isnot [string] -or $r.assistant -isnot [string] -or [string]::IsNullOrWhiteSpace($r.user) -or [string]::IsNullOrWhiteSpace($r.assistant) -or $null -eq $r.epoch -or [string]::IsNullOrWhiteSpace([string]$r.turn_id)){$skip++;$history.Clear();$prev=$null;continue}
            if($null -eq $prev -or [string]$r.epoch -cne $prev){$history.Clear()}
            $prev=[string]$r.epoch
            $ctx=$history.ToArray();$size=$r.user.Length
            foreach($h in $ctx){$size+=$h.user.Length+$h.assistant.Length}
            $loc=$f.Name+'|'+$lineNo
            if([string]$r.route -ieq 'LOCAL' -and $size -le 10000 -and $ctx.Count -gt 0 -and -not $excluded.ContainsKey($loc)){
                $rank=Get-P83Hash ('p83-v1|'+$loc+'|'+$r.turn_id)
                $pool.Add([pscustomobject]@{id=$rank.Substring(0,16);rank=$rank;scope_id=('conversation:'+$prev);source_file=$f.Name;source_line=$lineNo;source_hash=(Get-P83Hash $line);context=$ctx;user=$r.user})
            }else{$skip++}
            $history.Add([pscustomobject]@{source_ref=$loc;source_hash=(Get-P83Hash $line);user=$r.user;assistant=$r.assistant;external_evidence_status=(Get-LfoExternalEvidenceStatus $r)})
            while($history.Count -gt 2){$history.RemoveAt(0)}
        }
    }
    # Exclude exact repeated current prompts within the selected sample, not paraphrases.
    $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $chosen=New-Object 'System.Collections.Generic.List[object]'
    foreach($c in @($pool|Sort-Object rank)){
        if($seen.Add($c.user)){$chosen.Add($c)}
        if($chosen.Count -ge $SampleCount){break}
    }
    Assert-G2 ($chosen.Count -gt 0) 'No eligible distinct current requests'
    $dir=Join-Path $WorkRoot ('Corpus-'+[guid]::NewGuid().ToString('N'))
    $null=New-Item -ItemType Directory -Force -Path $dir
    $path=Join-Path $dir 'corpus.json'
    Save-P83 $path ([ordered]@{schema='p83-corpus-v1';selection='LOCAL, prior L0 records, disjoint current source locations from supplied exclusion corpus, distinct exact current prompts';eligible=$pool.Count;excluded_locations=$excluded.Count;malformed=$bad;skipped=$skip;cases=$chosen.ToArray()})
    Write-Host "P83 PREPARE selected=$($chosen.Count); eligible=$($pool.Count); excluded_locations=$($excluded.Count); malformed=$bad; skipped=$skip"
    Write-Host "CORPUS $path"
    Write-Host 'Review locally before Live. Do not publish raw records.'
}
function New-P83Messages($Case,[string]$Arm){
    $hasProjection=$Arm -cin @('B','D')
    $hasShaping=$Arm -cin @('C','D')
    $items=@(foreach($h in $Case.context){
        # Keep full text in projector; rendering emits only metadata, no duplicated text.
        [pscustomobject]@{layer='L0';source_ref=$h.source_ref;scope_id=$Case.scope_id;text=(@{user=$h.user;assistant=$h.assistant}|ConvertTo-Json -Compress);external_evidence_status=$h.external_evidence_status}
    })
    $p=$null
    if($hasProjection){
        $p=New-LfoG2ContextProjection $Case.user $Case.scope_id $items -TrustedEnvelope
        Assert-G2 ($p.state -ceq 'PROJECTED' -and $p.items.Count -eq $items.Count) 'Projection unavailable or duplicate context; preserve original and abort rather than silently substitute'
    }
    $requested=if($hasShaping){'S2'}else{'S0'}
    $plan=New-LfoG2CesPlan -RequestedShape $requested -ScopeId $Case.scope_id -Eligibility @{MASK_CONTEXT=$false;PRESERVE_SUPPORT=$true;SCOPE_BIND=$true} -TrustedEnvelope
    Assert-G2 ($plan.state -ceq 'PLANNED' -and $plan.selected_shape -ceq $requested) 'Unexpected CES plan'
    $system=$common
    if($hasProjection){
        $labels=@(foreach($item in $p.items){[ordered]@{role=$item.role;external_evidence_status=$item.external_evidence_status}})
        $system+=' '+$projectionIntro+' '+($labels|ConvertTo-Json -Compress -Depth 5)
    }
    foreach($op in $plan.operators){
        switch -CaseSensitive ($op){
            'PRESERVE_SUPPORT'{$system+=' '+$support}
            'SCOPE_BIND'{$system+=' '+$scope}
            default{throw 'Unexpected active operator'}
        }
    }
    $messages=New-Object 'System.Collections.Generic.List[object]'
    $messages.Add(@{role='system';content=$system})
    foreach($h in $Case.context){$messages.Add(@{role='user';content=$h.user});$messages.Add(@{role='assistant';content=$h.assistant})}
    $messages.Add(@{role='user';content=$Case.user})
    [pscustomobject]@{messages=$messages.ToArray();shape=$plan.selected_shape;projection=$hasProjection;operators=$plan.operators}
}
# Verify component interoperability with a typed fixture only; not a claim about live semantic binding.
$fixture=@{segments=@(@{id='a';role='EVIDENCE';text='61'},@{id='b';role='EVIDENCE';text='84'});witness=@{operation='COMPARE';relation='GT';inputs=@(@{name='a';source_id='a';start=0;length=2;lexeme='61'},@{name='b';source_id='b';start=0;length=2;lexeme='84'})}}
$w=Invoke-LfoG2DeterministicWitness $fixture -TrustedBinding
Assert-G2 ($w.state -ceq 'COMPUTED' -and $w.results.holds -eq $false) 'Witness integration fixture failed'
$rt=Resolve-LfoG2RuntimeProvenance @{turn_id='t1';complete=$true;events=@()} @{kind='SUCCESS_ASSERTION';turn_id='t1';actor='assistant';operation='read';target='doc:1'} -TrustedRuntime -TrustedBinding
Assert-G2 ($rt.state -ceq 'CONTRADICTED') 'Runtime integration fixture failed'
$findings=@(@{scope_id='conversation:1';target_ref='t1#numeric';invariant='numeric_comparison';source_ref='fixture:w';producer='cpu';version='1';state='CONTRADICTED';status='VERIFIED'},@{scope_id='conversation:1';target_ref='t1#runtime';invariant='runtime_operation';source_ref='fixture:r';producer='cpu';version='1';state='CONTRADICTED';status='VERIFIED'})
$fp=New-LfoG2CesPlan -RequestedShape S2 -ScopeId 'conversation:1' -Findings $findings -Eligibility @{PRESERVE_SUPPORT=$true;SCOPE_BIND=$true} -TrustedEnvelope
Assert-G2 ($fp.review_targets.Count -eq 2 -and $fp.selected_shape -ceq 'S2') 'Finding integration fixture failed'
$c=@{id='fixture';scope_id='conversation:1';user='Current question';context=@(@{source_ref='fixture:1';user='Prior question';assistant='Prior answer';external_evidence_status='NONE'})}
$plans=@{}
foreach($arm in @('A','B','C','D')){
    $plans[$arm]=New-P83Messages $c $arm
    Assert-G2 ($plans[$arm].messages.Count -eq 4 -and $plans[$arm].messages[1].content -ceq 'Prior question' -and $plans[$arm].messages[2].content -ceq 'Prior answer' -and $plans[$arm].messages[3].content -ceq 'Current question') 'Raw dialogue changed'
}
Assert-G2 ($plans.A.shape -ceq 'S0' -and $plans.B.shape -ceq 'S0' -and $plans.C.shape -ceq 'S2' -and $plans.D.shape -ceq 'S2') 'Shape allocation failed'
Assert-G2 ($plans.B.messages[0].content.Contains('"NONE"') -and -not $plans.A.messages[0].content.Contains($projectionIntro) -and $plans.D.messages[0].content.Contains($support) -and -not $plans.B.messages[0].content.Contains($support)) 'Factor separation failed'
Write-Host 'UNIT PASS 9/9'
if($Mode -ceq 'Unit'){return}
if($Mode -ceq 'Prepare'){New-P83Corpus;return}
Assert-G2 (-not [string]::IsNullOrWhiteSpace($CorpusPath) -and (Test-Path -LiteralPath $CorpusPath -PathType Leaf)) 'Live requires reviewed corpus'
Assert-Loopback $MainUri
$corpus=Get-Content -LiteralPath $CorpusPath -Raw -Encoding UTF8|ConvertFrom-Json
Assert-G2 ($corpus.schema -ceq 'p83-corpus-v1' -and @($corpus.cases).Count -gt 0 -and @($corpus.cases).Count -le 48) 'Invalid corpus'
$ids=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach($c in $corpus.cases){
    Assert-G2 ($c.id -is [string] -and $ids.Add($c.id) -and $c.user -is [string] -and -not [string]::IsNullOrWhiteSpace($c.user) -and @($c.context).Count -ge 1 -and @($c.context).Count -le 2) 'Invalid case'
    $size=$c.user.Length
    foreach($h in $c.context){Assert-G2 ($h.user -is [string] -and $h.assistant -is [string] -and $h.source_ref -is [string] -and $h.external_evidence_status -cin @('NONE','REQUESTED','OBSERVED','UNKNOWN')) 'Invalid historical record';$size+=$h.user.Length+$h.assistant.Length}
    Assert-G2 ($size -le 10000) 'Oversized case'
}
Add-Type -AssemblyName System.Net.Http
$client=New-G2Client 300
$endpoint=$MainUri.TrimEnd('/')+'/api/chat'
$dir=Join-Path $WorkRoot ('P83-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Force -Path $dir
$rows=New-Object 'System.Collections.Generic.List[object]'
$reviews=New-Object 'System.Collections.Generic.List[object]'
$keys=New-Object 'System.Collections.Generic.List[object]'
Save-P83 (Join-Path $dir 'manifest.json') ([ordered]@{version='p83-v1';corpus_sha256=(Get-FileHash -LiteralPath $CorpusPath -Algorithm SHA256).Hash;model=$MainModel;cpu=[bool]$MainCpu;context=$MainContext;seed=83;common=$common;projection_intro=$projectionIntro;support=$support;scope=$scope;factor_a='L0 turn metadata labels';factor_b='new S2 wording, not exact P22';purpose='RESEARCH';status='PROVISIONAL';live_witness_binding=$false;live_runtime_claim_binding=$false;edge_calls=0})
try{
    $i=0
    # Balanced four-arm serial order. No independent hardware concurrency assumed.
    $orders=@(@('A','B','D','C'),@('B','C','A','D'),@('C','D','B','A'),@('D','A','C','B'))
    foreach($c in $corpus.cases){
        $order=$orders[$i%4];$i++;$answers=@{}
        foreach($arm in $order){
            $sw=[Diagnostics.Stopwatch]::StartNew()
            $plan=New-P83Messages $c $arm
            $sw.Stop()
            $opts=@{num_ctx=$MainContext;num_predict=4096;temperature=0;seed=83}
            if($MainCpu){$opts.num_gpu=0}
            $body=@{model=$MainModel;messages=$plan.messages;stream=$false;think=$false;options=$opts;keep_alive='10m'}
            $h=Invoke-G2Sync $client $endpoint $body
            $a=Read-P83Response $h 'OLLAMA_CHAT' $MainModel
            $answers[$arm]=[pscustomobject]@{answer=$a;compose_ms=$sw.Elapsed.TotalMilliseconds;shape=$plan.shape;projection=$plan.projection}
        }
        $rows.Add([pscustomobject]@{id=$c.id;order=$order;A=$answers.A;B=$answers.B;C=$answers.C;D=$answers.D})
        $blind=@(@('A','B','C','D')|Sort-Object {Get-P83Hash ('blind|'+$c.id+'|'+$_)})
        $review=[ordered]@{id=$c.id;context=@(foreach($h in $c.context){@{user=$h.user;assistant=$h.assistant}});user=$c.user}
        $key=[ordered]@{id=$c.id}
        for($j=0;$j -lt 4;$j++){
            $label='answer_'+($j+1);$review[$label]=$answers[$blind[$j]].answer.raw;$key[$label]=$blind[$j]
        }
        $reviews.Add([pscustomobject]$review);$keys.Add([pscustomobject]$key)
        Save-P83 (Join-Path $dir 'results.json') @{rows=$rows.ToArray()}
        Save-P83 (Join-Path $dir 'blind-review.json') @{schema='p83-review-v1';rubric='Rate task completion, evidential integrity, warranted uncertainty, protected scope and new material errors per answer independently; unknown if not assessable. No forced ranking.';cases=$reviews.ToArray()}
        Save-P83 (Join-Path $dir 'blind-key.json') @{cases=$keys.ToArray()}
        Write-Host ("P83 {0}/{1}; A={2:N1} B={3:N1} C={4:N1} D={5:N1} ms; complete={6}/{7}/{8}/{9}" -f $i,@($corpus.cases).Count,$answers.A.answer.ms,$answers.B.answer.ms,$answers.C.answer.ms,$answers.D.answer.ms,$answers.A.answer.complete,$answers.B.answer.complete,$answers.C.answer.complete,$answers.D.answer.complete)
    }
    Write-Host ("P83 TRANSPORT PASS; cases={0}; main_calls={1}; edge_calls=0; db_writes=0" -f $rows.Count,($rows.Count*4))
    Write-Host "RESULTS $dir"
    Write-Host 'No quality verdict before blind review.'
}finally{$client.Dispose()}
