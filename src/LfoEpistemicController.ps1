# Post-L0 G2 controller: no prompt injection, model calls or answer edits.
# Modules are trusted repository code, not user-provided executable profiles.
function ConvertTo-LfoG2NormalizedText([string]$Text){
    $b=New-Object Text.StringBuilder
    foreach($c in $Text.Normalize([Text.NormalizationForm]::FormD).ToCharArray()){
        if([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark){[void]$b.Append($c)}
    }
    return $b.ToString().ToLowerInvariant().Trim()
}
function Initialize-LfoG2Controller {
    param([string]$RepositoryRoot,[string]$ProfilePath)
    $ErrorActionPreference='Stop'
    $registry=Import-PowerShellDataFile -LiteralPath (Join-Path $RepositoryRoot 'config/EpistemicRegistry.psd1')
    if($registry.SchemaVersion -ne 1){throw 'Unsupported G2 registry version.'}
    if(-not $ProfilePath){$ProfilePath=Join-Path $RepositoryRoot 'config/EpistemicProfile.json'}
    $p=Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8|ConvertFrom-Json
    if($p.schemaVersion -ne 1 -or $p.mode -cnotin @('OFF','OBSERVE','ADVISE') -or $null -eq $p.axes -or $null -eq $p.detectors){throw 'Invalid G2 profile or mode.'}
    $axes=@{}
    foreach($key in $registry.Axes.Keys){
        if($key -cnotmatch '^E[1-9][0-9]*$'){throw 'Invalid axis ID.'}
        $prop=$p.axes.PSObject.Properties[$key]
        $level=if($null -eq $prop){'OFF'}else{[string]$prop.Value}
        if($level -cnotin @('OFF','LOW','MEDIUM','HIGH')){throw 'Invalid axis sensitivity.'}
        $axes[$key]=$level
    }
    foreach($prop in $p.axes.PSObject.Properties){if(-not $axes.ContainsKey($prop.Name)){throw 'Unknown profile axis.'}}
    $modules=@{}
    foreach($d in $registry.Detectors){
        if($d.Id -cnotmatch '^[a-z0-9-]{1,60}$' -or $modules.ContainsKey($d.Id) -or
           -not $axes.ContainsKey($d.Axis) -or $d.Stage -cnotin @('USER','FINAL','INTERACTION') -or
           $d.Module -cnotmatch '^[A-Za-z0-9-]+\.ps1$' -or $d.Function -cnotmatch '^Get-LfoG2[A-Za-z0-9]+$' -or
           $d.Version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+$'){throw 'Invalid G2 detector descriptor.'}
        . (Join-Path (Join-Path $RepositoryRoot 'src/epistemic') $d.Module)
        $fn=Get-Command $d.Function -CommandType Function -ErrorAction Stop
        $prop=$p.detectors.PSObject.Properties[$d.Id]
        if($null -ne $prop -and $prop.Value -isnot [bool]){throw 'Detector enabled must be boolean.'}
        $modules[$d.Id]=[pscustomobject]@{Descriptor=$d;Run=$fn.ScriptBlock;Enabled=($null -ne $prop -and $prop.Value -eq $true)}
    }
    foreach($prop in $p.detectors.PSObject.Properties){if(-not $modules.ContainsKey($prop.Name)){throw 'Unknown profile detector.'}}
    [pscustomobject]@{Mode=[string]$p.mode;Axes=$axes;Modules=$modules;Registry=$registry;ProfilePath=$ProfilePath}
}
function Invoke-LfoG2Controller {
    param($Controller,$Row,[string]$SourceFile)
    if($null -eq $Controller -or $Controller.Mode -eq 'OFF'){return}
    if($Row.stage_sources_schema -ne 1 -or $Row.epoch -lt 1 -or $Row.turn_id -lt 1 -or $SourceFile -cnotmatch '^conversation-[0-9]{4}-[0-9]{2}\.jsonl$'){return}
    $keys=@($Controller.Modules.Keys|Sort-Object)
    $orderedKeys=@($keys|Where-Object{$Controller.Modules[$_].Descriptor.Stage -ne 'INTERACTION'})+@($keys|Where-Object{$Controller.Modules[$_].Descriptor.Stage -eq 'INTERACTION'})
    $userSignal=$null
    foreach($key in $orderedKeys){
        $m=$Controller.Modules[$key];$d=$m.Descriptor;$s=$Controller.Axes[$d.Axis]
        if(-not $m.Enabled -or $s -eq 'OFF'){continue}
        $field=if($d.Stage -eq 'USER'){'user'}else{'assistant'}
        $sourceActor=if($d.Stage -eq 'INTERACTION'){'FINAL'}else{$d.Stage}
        $stages=@($Row.stage_sources|Where-Object{$_.actor -ceq $sourceActor -and $_.source_field -ceq $field})
        if($stages.Count -ne 1){continue}
        $stage=$stages[0];$raw=[string]$Row.$field
        $text=if($sourceActor -eq 'FINAL'){Get-LfoHistoricalAssistantText $Row}else{$raw}
        $linkedUser=$null
        if($d.Stage -eq 'INTERACTION'){
            $userStages=@($Row.stage_sources|Where-Object{$_.actor -ceq 'USER' -and $_.source_field -ceq 'user'})
            if($userStages.Count -ne 1 -or -not $userStages[0].stage_id -or -not $stage.stage_id){continue}
            $linkedUser=$userStages[0]
        }
        $status=Get-LfoExternalEvidenceStatus $Row
        $ctx=[pscustomobject]@{Text=$text;ExternalEvidence=$status;Route=[string]$Row.route;Stage=$d.Stage;UserText=if($linkedUser){[string]$Row.user}else{$null};UserSignal=if($linkedUser){$userSignal}else{$null}}
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $outcome='FAILED_ISOLATED';$detail=$null
        try {
            if($sourceActor -eq 'FINAL' -and $stage.producer -eq 'WRAPPER'){$outcome='ABSTAIN'}
            else{
                $result=@(& $m.Run $ctx $s)
                if($result.Count -ne 1){throw 'Detector result violates contract.'}
                $r=$result[0]
                $assessment=if($r -is [string]){$r}else{[string]$r.Assessment}
                if($assessment -cnotin @('ABSTAIN','OBSERVED_SIGNAL','CONTRADICTED','INSUFFICIENT_EVIDENCE')){throw 'Detector assessment violates contract.'}
                if($r -isnot [string]){
                    if($r.Phenomenon -cnotmatch '^[A-Z_]{1,80}$' -or $r.RuleId -cnotmatch '^[A-Z0-9_]{1,80}$' -or $r.Scope -cnotmatch '^[A-Z_]{1,40}$' -or $r.Start -isnot [int] -or $r.Length -isnot [int] -or $r.Start -lt 0 -or $r.Length -lt 1 -or ([long]$r.Start+$r.Length) -gt $text.Length){throw 'Detector evidence span violates contract.'}
                    $detail=$r
                }
                $outcome=$assessment
            }
        }catch{$outcome='FAILED_ISOLATED'}
        $sw.Stop()
        if($d.Id -ceq 'confirmation-seeking' -and $outcome -ceq 'OBSERVED_SIGNAL' -and $detail){$userSignal=$detail.Phenomenon}
        [pscustomobject][ordered]@{
            schema_version=1;detector=$d.Id;detector_version=$d.Version;axis=$d.Axis;sensitivity=$s;mode=$Controller.Mode
            actor=$d.Stage;producer=[string]$stage.producer;assessment=$outcome;route=[string]$Row.route;external_evidence_status=$status
            source_file=$SourceFile;epoch=[int]$Row.epoch;turn_id=[int]$Row.turn_id;stage_id=[string]$stage.stage_id
            content_sha256=(Get-LfoEpistemicHash $raw);elapsed_ms=[Math]::Round($sw.Elapsed.TotalMilliseconds,3)
            phenomenon=if($detail){$detail.Phenomenon}else{$null};rule_id=if($detail){$detail.RuleId}else{$null};claim_scope=if($detail){$detail.Scope}else{$null}
            evidence_start=if($detail){$detail.Start}else{$null};evidence_length=if($detail){$detail.Length}else{$null};evidence_basis='MODEL_TEXT_WITH_WRAPPER_SUFFIX_REMOVED_OR_USER_TEXT_UTF16'
            linked_user_stage_id=if($linkedUser){[string]$linkedUser.stage_id}else{$null}
            linked_user_sha256=if($linkedUser){Get-LfoEpistemicHash ([string]$Row.user)}else{$null}
            linked_user_signal=if($linkedUser){$userSignal}else{$null}
            magnitude=$null;confidence=$null;additional_model_calls=0
        }
    }
}
function Write-LfoG2Turn {
    param($Controller,$Row,[string]$SourceFile,[string]$LogDirectory)
    $ErrorActionPreference='Stop'
    foreach($event in @(Invoke-LfoG2Controller $Controller $Row $SourceFile)){
        # Derived detector ledger only; raw evidence stays in L0.
        $path=Join-Path $LogDirectory ('epistemic-'+$SourceFile.Substring(13,7)+'.jsonl')
        Append-JsonLine $path $event
        if($Controller.Mode -eq 'ADVISE' -and $event.assessment -in @('CONTRADICTED','INSUFFICIENT_EVIDENCE','OBSERVED_SIGNAL')){
            Write-Host ('[G2 {0}: {1}; signal only, see detector ledger]' -f $event.detector,$event.assessment) -ForegroundColor Yellow
        }
    }
}
function Invoke-LfoG2Command {
    param($Controller,[string]$Command)
    if($null -eq $Controller){Write-Host '[G2 unavailable]';return}
    $parts=$Command.Trim() -split '\s+'
    if($parts.Count -eq 1 -or $parts[1] -eq 'status'){
        Write-Host ('G2: '+$Controller.Mode+'; additional model calls: 0; legacy L4 independent')
        foreach($key in @($Controller.Axes.Keys|Sort-Object)){Write-Host ('  {0} {1}: {2}' -f $key,$Controller.Registry.Axes[$key],$Controller.Axes[$key])}
        foreach($key in @($Controller.Modules.Keys|Sort-Object)){Write-Host ('  detector {0}: enabled={1}' -f $key,$Controller.Modules[$key].Enabled)}
        return
    }
    if($parts[1] -in @('off','observe','advise')){$Controller.Mode=$parts[1].ToUpperInvariant();Write-Host ('G2: '+$Controller.Mode);return}
    if($parts[1] -eq 'set' -and $parts.Count -eq 4){
        $axis=$parts[2].ToUpperInvariant();$level=$parts[3].ToUpperInvariant()
        if($Controller.Axes.ContainsKey($axis) -and $level -in @('OFF','LOW','MEDIUM','HIGH')){$Controller.Axes[$axis]=$level;Write-Host ('G2 '+$axis+': '+$level);return}
    }
    Write-Host 'Usage: /epistemic status|off|observe|advise|set E1 low|medium|high|off. INTERVENE is not enabled.'
}
