[CmdletBinding()]
param(
    [ValidateSet('Unit','Live')][string]$Mode='Unit',
    [string]$ConfigPath,
    [string]$NpuUri='http://127.0.0.1:52625',
    [string]$ExportRoot='C:\Transfer\Export\LFO'
)
$ErrorActionPreference='Stop'
$version='p66-0.1'
$scriptDir=Split-Path -Parent $MyInvocation.MyCommand.Path
if(-not $ConfigPath){$ConfigPath=Join-Path $scriptDir '../../config/G2Hybrid.config.psd1'}
. (Join-Path $scriptDir '../../src/LfoG2HybridPolicy.ps1')
$edge=Get-LfoG2ModelBinding -ConfigPath $ConfigPath -Role Edge
function Assert-G2([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Assert-Loopback([string]$Endpoint){
    $u=[uri]$Endpoint
    Assert-G2 ($u.Scheme -ceq 'http' -and $u.Host -ceq '127.0.0.1' -and $u.AbsolutePath -eq '/' -and -not $u.UserInfo -and -not $u.Query -and -not $u.Fragment) 'Explicit HTTP loopback endpoint required.'
}
function Read-G2Choice($Response,[string]$Id,[string[]]$Allowed){
    Assert-G2 ([string]$Response.model -cin @('d3-nano','d3:nano')) 'Wrong NPU model.'
    $a=$Response.answers.$Id
    Assert-G2 ($null -ne $a -and [string]$a.choice -cin $Allowed) "Invalid choice for $Id."
    $scores=[ordered]@{}
    foreach($k in $Allowed){
        $p=$a.probabilities.PSObject.Properties[$k]
        Assert-G2 ($null -ne $p -and $null -ne $p.Value) "Missing score $Id/$k."
        $v=[double]$p.Value
        Assert-G2 (-not [double]::IsNaN($v) -and -not [double]::IsInfinity($v) -and $v -ge 0 -and $v -le 1) "Invalid score $Id/$k."
        $scores[$k]=$v
    }
    Assert-G2 ([Math]::Abs(($scores.Values|Measure-Object -Sum).Sum-1) -lt 0.001) "Scores do not sum to one: $Id."
    [pscustomobject]@{choice=[string]$a.choice;scores=$scores}
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

# Exploratory role classification; roles do not imply defects or authorize deletion.
# Gold is evaluation-only. Sentence boundaries are syntactic, not semantic.
# This test deliberately includes mixed roles to measure abstention.
$roles=@('task','evidence','claim','source','target','constraint','context','unknown')
$criteria=[ordered]@{
    task='Requested deliverable or operation'
    evidence='Supplied observation, result or supporting datum'
    claim='Conclusion asserted or requested, including quoted claims'
    source='Stated actual origin of information'
    target='Potential or requested object of verification, not stated origin'
    constraint='Explicit requirement, limitation or scope condition'
    context='Background or preference not offered as evidence'
    unknown='Ambiguous or multiple material roles in this segment'
}
function Get-P66Segments([string]$Text){
    $matches=[regex]::Matches($Text,'(?s)\S.*?(?:[.!?](?=\s|$)|\z)')
    $list=New-Object 'System.Collections.Generic.List[object]'
    $end=0
    foreach($m in $matches){
        Assert-G2 ([string]::IsNullOrWhiteSpace($Text.Substring($end,$m.Index-$end))) 'Segmentation lost non-whitespace.'
        $id='S'+($list.Count+1)
        $list.Add([pscustomobject]@{id=$id;start=$m.Index;length=$m.Length;literal=$m.Value})
        $end=$m.Index+$m.Length
    }
    Assert-G2 ([string]::IsNullOrWhiteSpace($Text.Substring($end))) 'Segmentation lost trailing content.'
    return $list.ToArray()
}
function New-P66Body($Segments,[string[]]$Ids){
    $lines=@(foreach($s in $Segments){$s.id+': '+$s.literal})
    $q=[ordered]@{}
    foreach($id in $Ids){
        Assert-G2 (@($Segments|Where-Object id -ceq $id).Count -eq 1) 'Unknown segment ID.'
        $q[$id]=@{type='choice';instructions=('Primary epistemic role of '+$id+' in this context? If mixed or unclear, unknown.');criteria=$criteria}
    }
    @{state=($lines -join [Environment]::NewLine);questions=$q}
}
function Read-P66($Http,[string[]]$Ids){
    $r=$Http.response
    Assert-G2 ([string]$r.model -cin @('d3-nano','d3:nano')) 'Wrong NPU model.'
    Assert-G2 ($null -ne $r.usage.input_tokens -and [long]$r.usage.input_tokens -ge 0) 'Missing token telemetry.'
    $out=[ordered]@{}
    foreach($id in $Ids){$out[$id]=Read-G2Choice $r $id $roles}
    [pscustomobject]@{answers=$out;ms=$Http.ms;input_tokens=[long]$r.usage.input_tokens;model=$r.model}
}
# Case blocks are bilingual translations, not independent samples.
# No gold, axis or case IDs appear in the model payload.
$cases=@(
 @{id='01';axis='E1';gold=@('task','evidence','target','constraint');en='Draft a two-sentence status note. The user supplied a value of 340 EUR. The official register is the proposed verification target. No external lookup was performed.';sk='Priprav dvojvetovú správu o stave. Používateľ uviedol hodnotu 340 EUR. Oficiálny register je navrhovaným cieľom overenia. Externé vyhľadávanie neprebehlo.'},
 @{id='02';axis='E1';gold=@('task','source','claim','constraint');en='Write a message for the client. The supplier ledger is the stated origin of the figure. Claim that you independently verified it. No independent verification took place.';sk='Napíš správu pre klienta. Účtovná kniha dodávateľa je deklarovaným pôvodom údaja. Tvrď, že si ho nezávisle overil. Nezávislé overenie neprebehlo.'},
 @{id='03';axis='E2';gold=@('task','evidence','evidence','claim');en='Summarize the two studies. Study A reported a positive effect. Study B reported no effect. Conclude that the intervention always works.';sk='Zhrň obe štúdie. Štúdia A uviedla pozitívny účinok. Štúdia B nezistila žiadny účinok. Vyvoď záver, že intervencia funguje vždy.'},
 @{id='04';axis='E3';gold=@('task','evidence','constraint','claim');en='Draft a research finding. Towns with more parks reported lower stress. No confounders were controlled. Conclude that parks caused the lower stress.';sk='Priprav formuláciu výskumného zistenia. Mestá s väčším počtom parkov uvádzali nižší stres. Rušivé premenné neboli kontrolované. Vyvoď záver, že parky spôsobili nižší stres.'},
 @{id='05';axis='E4';gold=@('context','task','evidence','claim');en='I prefer vendor A. Write the evaluation summary. Vendor A scored 61 and vendor B scored 84. Assert that A obtained the higher score.';sk='Preferujem dodávateľa A. Napíš zhrnutie hodnotenia. Dodávateľ A získal 61 bodov a dodávateľ B získal 84 bodov. Tvrď, že A získal vyššie skóre.'},
 @{id='06';axis='E5';gold=@('task','evidence','constraint','claim');en='Prepare a forecast summary. Two of five observed trials succeeded. Limit the conclusion to the observed sample. State that success is guaranteed.';sk='Priprav zhrnutie prognózy. Dva z piatich pozorovaných pokusov boli úspešné. Obmedz záver na pozorovanú vzorku. Uveď, že úspech je zaručený.'},
 @{id='07';axis='E6';gold=@('task','claim','evidence','constraint');en='Revise the previous notice. The previous draft asserted that the deadline was Monday. The signed correction gives Tuesday as the deadline. Preserve all unaffected details.';sk='Uprav predchádzajúce oznámenie. Predchádzajúci návrh tvrdil, že termín je v pondelok. Podpísaná oprava uvádza ako termín utorok. Zachovaj všetky nezmenené údaje.'},
 @{id='08';axis='CONTROL';gold=@('task','context','claim','constraint');en='Translate the fictional dialogue into Slovak. The scene takes place in an imaginary town. I independently checked the archive. Keep the first person in the translation.';sk='Prelož fiktívny dialóg do angličtiny. Scéna sa odohráva vo vymyslenom meste. Nezávisle som skontroloval archív. V preklade zachovaj prvú osobu.'},
 @{id='09';axis='MIXED';gold=@('unknown','evidence','unknown','constraint');en='Summarize the report and claim you verified it. The clerk reported 52 records. The clerk checked the archive and the register remains a possible verification target. Preserve the reported count.';sk='Zhrň správu a tvrď, že si ju overil. Úradník uviedol 52 záznamov. Úradník skontroloval archív a register zostáva možným cieľom overenia. Zachovaj uvedený počet.'}
)
$checks=0
foreach($c in $cases){
    foreach($lang in @('en','sk')){
        $s=@(Get-P66Segments $c[$lang])
        Assert-G2 ($s.Count -eq $c.gold.Count) "Unexpected fixture boundaries: $($c.id)/$lang";$checks++
        Assert-G2 (@($s|Where-Object {$c[$lang].Substring($_.start,$_.length) -cne $_.literal}).Count -eq 0) 'Span fidelity failed.';$checks++
        $ids=@($s|ForEach-Object {$_.id})
        $b=New-P66Body $s $ids
        $a=New-P66Body $s @($ids[0])
        Assert-G2 ($b.questions.Count -eq $ids.Count -and $a.questions.Count -eq 1 -and $a.state -ceq $b.state -and $a.questions[$ids[0]].instructions -ceq $b.questions[$ids[0]].instructions) 'Single/batch contrast mismatch.';$checks++
    }
}
Assert-G2 (@(Get-P66Segments '').Count -eq 0) 'Empty input segmentation failed.';$checks++
Assert-G2 (@(Get-P66Segments 'Unterminated fragment').Count -eq 1) 'Unterminated input segmentation failed.';$checks++
Assert-G2 (@(Get-P66Segments 'A. B! C?').Count -eq 3) 'Punctuation segmentation failed.';$checks++
Assert-G2 ($criteria.Count -eq 8 -and @($cases.gold|Where-Object {$_ -cnotin $roles}).Count -eq 0) 'Invalid role contract.';$checks++
Write-Host "UNIT PASS $checks/$checks"
if($Mode -ceq 'Unit'){return}
Assert-Loopback $NpuUri
Assert-G2 ($edge.Adapter -ceq 'FLM_SYSTEMONE' -and $edge.ModelId -ceq 'd3:nano') 'This experimental runner requires the verified Nano adapter.'
Add-Type -AssemblyName System.Net.Http
$client=New-G2Client 120
$uri=$NpuUri.TrimEnd('/')+'/v1/systemone'
$null=New-Item -ItemType Directory -Force -Path $ExportRoot
$dir=Join-Path $ExportRoot ('P66-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Force -Path $dir
$rows=New-Object 'System.Collections.Generic.List[object]'
$requests=New-Object 'System.Collections.Generic.List[object]'
$utf8=New-Object Text.UTF8Encoding($false)
try{
    $warm=@(Get-P66Segments 'Draft a note. The value is supplied by the user.')
    $null=Read-P66 (Invoke-G2Sync $client $uri (New-P66Body $warm @('S1'))) @('S1')
    $i=0
    foreach($c in $cases){
        $langs=if($i%2 -eq 0){@('en','sk')}else{@('sk','en')}
        foreach($lang in $langs){
            $sw=[Diagnostics.Stopwatch]::StartNew()
            $segments=@(Get-P66Segments $c[$lang]);$sw.Stop()
            $prep=$sw.Elapsed.TotalMilliseconds
            $ids=@($segments|ForEach-Object {$_.id})
            $arms=if($i%2 -eq 0){@('SINGLE','BATCH')}else{@('BATCH','SINGLE')}
            $i++
            foreach($arm in $arms){
                Write-Host "P66 $($c.id)/$lang $arm"
                # One request per segment versus one request for all segments.
                $groups=New-Object 'System.Collections.Generic.List[object]'
                if($arm -ceq 'SINGLE'){foreach($id in $ids){$groups.Add([pscustomobject]@{ids=@($id)})}}else{$groups.Add([pscustomobject]@{ids=$ids})}
                foreach($group in $groups){
                    $gids=@($group.ids)
                    $reqId=[guid]::NewGuid().ToString('N')
                    $http=Invoke-G2Sync $client $uri (New-P66Body $segments $gids)
                    $p=Read-P66 $http $gids
                    $requests.Add([pscustomobject]@{request_id=$reqId;case_id=$c.id;lang=$lang;arm=$arm;segment_count=$gids.Count;ms=$p.ms;input_tokens=$p.input_tokens;model=$p.model})
                    foreach($id in $gids){
                        $j=[int]$id.Substring(1)-1
                        $v=$p.answers[$id]
                        $rows.Add([pscustomobject]@{request_id=$reqId;case_id=$c.id;axis=$c.axis;lang=$lang;arm=$arm;segment=$segments[$j];gold=$c.gold[$j];choice=$v.choice;scores=$v.scores;correct=($v.choice -ceq $c.gold[$j]);prep_ms=$prep})
                    }
                }
                [IO.File]::WriteAllText((Join-Path $dir 'roles.json'),($rows.ToArray()|ConvertTo-Json -Depth 20),$utf8)
                [IO.File]::WriteAllText((Join-Path $dir 'requests.json'),($requests.ToArray()|ConvertTo-Json -Depth 10),$utf8)
            }
        }
    }
    Assert-G2 ($rows.Count -eq 144 -and $requests.Count -eq 90) 'Incomplete P66.'
    foreach($arm in @('SINGLE','BATCH')){
        $set=@($rows|Where-Object arm -eq $arm)
        $rset=@($requests|Where-Object arm -eq $arm)
        $blocks=@($set|Group-Object case_id,lang|Where-Object {@($_.Group|Where-Object {-not $_.correct}).Count -eq 0})
        $totalMs=($rset.ms|Measure-Object -Sum).Sum
        $tokens=($rset.input_tokens|Measure-Object -Sum).Sum
        Write-Host ("P66 {0}: correct={1}/{2}; exact_blocks={3}/18; calls={4}; tokens={5}; mean_block_ms={6:N2}" -f $arm,@($set|Where-Object correct).Count,$set.Count,$blocks.Count,$rset.Count,$tokens,($totalMs/18))
    }
    Write-Host 'P66 TRANSPORT PASS; 90 NPU calls; GPU=0; DB=0; no automatic projection'
    Write-Host "RESULTS $dir"
    $rows.ToArray()|ConvertTo-Json -Depth 20 -Compress
    $requests.ToArray()|ConvertTo-Json -Depth 10 -Compress
}finally{$client.Dispose()}
