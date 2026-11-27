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
           -not $axes.ContainsKey($d.Axis) -or $d.Stage -cnotin @('USER','FINAL') -or
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
    foreach($key in @($Controller.Modules.Keys|Sort-Object)){
        $m=$Controller.Modules[$key];$d=$m.Descriptor;$s=$Controller.Axes[$d.Axis]
        if(-not $m.Enabled -or $s -eq 'OFF'){continue}
        $field=if($d.Stage -eq 'USER'){'user'}else{'assistant'}
        $stages=@($Row.stage_sources|Where-Object{$_.actor -ceq $d.Stage -and $_.source_field -ceq $field})
        if($stages.Count -ne 1){continue}
        $stage=$stages[0];$raw=[string]$Row.$field
        $text=if($d.Stage -eq 'FINAL'){Get-LfoHistoricalAssistantText $Row}else{$raw}
        $status=Get-LfoExternalEvidenceStatus $Row
        $ctx=[pscustomobject]@{Text=$text;ExternalEvidence=$status;Route=[string]$Row.route;Stage=$d.Stage}
        $sw=[Diagnostics.Stopwatch]::StartNew()
        $outcome='FAILED_ISOLATED'
        try {
            if($d.Stage -eq 'FINAL' -and $stage.producer -eq 'WRAPPER'){$outcome='ABSTAIN'}
            else{
                $result=@(& $m.Run $ctx $s)
                if($result.Count -ne 1 -or $result[0] -cnotin @('ABSTAIN','OBSERVED_SIGNAL','CONTRADICTED','INSUFFICIENT_EVIDENCE')){throw 'Detector result violates contract.'}
                $outcome=[string]$result[0]
            }
        }catch{$outcome='FAILED_ISOLATED'}
        $sw.Stop()
        [pscustomobject][ordered]@{
            schema_version=1;detector=$d.Id;detector_version=$d.Version;axis=$d.Axis;sensitivity=$s;mode=$Controller.Mode
            actor=$d.Stage;producer=[string]$stage.producer;assessment=$outcome;route=[string]$Row.route;external_evidence_status=$status
            source_file=$SourceFile;epoch=[int]$Row.epoch;turn_id=[int]$Row.turn_id;stage_id=[string]$stage.stage_id
            content_sha256=(Get-LfoEpistemicHash $raw);elapsed_ms=[Math]::Round($sw.Elapsed.TotalMilliseconds,3)
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
