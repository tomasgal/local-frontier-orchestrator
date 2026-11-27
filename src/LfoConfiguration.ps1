# Shared data-only settings; bootstrap state and frozen contracts remain untouched.
function Get-LfoConfigurationPath([string]$InstallRoot){Join-Path $InstallRoot 'config/user-settings.json'}
function Get-LfoConfigurationRegistry {
    param([hashtable]$BaseConfig,$InstallState,[string]$RepositoryRoot)
    $r=[ordered]@{}
    function AddEntry($id,$section,$value,$kind,$choices,$apply,$description,$editable=$true){
        $r[$id]=[pscustomobject]@{Id=$id;Section=$section;Default=$value;Kind=$kind;Choices=@($choices);Apply=$apply;Description=$description;Editable=$editable}
    }
    $profile=Get-Content -LiteralPath (Join-Path $RepositoryRoot 'config/EpistemicProfile.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $ep=Import-PowerShellDataFile -LiteralPath (Join-Path $RepositoryRoot 'config/EpistemicRegistry.psd1')
    AddEntry 'Epistemic.Mode' 'Epistemic' $profile.mode 'enum' @('OFF','OBSERVE','ADVISE') 'Live' 'Observation or post-answer advisory; intervention unavailable.'
    foreach($axis in @($ep.Axes.Keys|Sort-Object)){
        $prop=$profile.axes.PSObject.Properties[$axis];$level=if($prop){[string]$prop.Value}else{'OFF'}
        $count=@($ep.Detectors|Where-Object Axis -eq $axis).Count
        AddEntry ('Epistemic.Axis.'+$axis) 'Epistemic' $level 'enum' @('OFF','LOW','MEDIUM','HIGH') 'Live' ($ep.Axes[$axis]+'; registered detectors: '+$count)
    }
    foreach($d in @($ep.Detectors|Sort-Object Id)){
        $p=$profile.detectors.PSObject.Properties[$d.Id]
        AddEntry ('Epistemic.Detector.'+$d.Id) 'Epistemic' ([bool]($p -and $p.Value)) 'bool' @() 'Live' ($d.Axis+' / '+$d.Version)
    }
    AddEntry 'Session.Think' 'Inference' $false 'bool' @() 'Live' 'Ollama thinking mode.'
    AddEntry 'Session.Route' 'Routing' 'AUTO' 'enum' @('AUTO','LOCAL','FRONTIER') 'Live' 'Route policy.'
    AddEntry 'Session.Stream' 'Interface' 'AUTO' 'enum' @('AUTO','ON','OFF') 'Live' 'AUTO uses device-specific streaming default.'
    AddEntry 'Runtime.Device' 'Hardware' 'Auto' 'enum' @('Auto','CPU','GPU','UMA') 'Restart' 'Default runtime device; explicit -Device wins.'
    $priority=if($InstallState.LFO.DefaultPriority -in @('Normal','High','Realtime')){[string]$InstallState.LFO.DefaultPriority}else{'High'}
    AddEntry 'Runtime.Priority' 'Hardware' $priority 'enum' @('Normal','High','Realtime') 'Restart' 'Explicit -Priority wins.'
    foreach($device in @('CPU','GPU','UMA')){
        $name=$device+'Model'
        AddEntry ('Models.'+$device) 'Models' ([string]$InstallState.Ollama.$name) 'string' @() 'Provision' 'Installed alias; selection/pull reserved for model manager.' $false
    }
    AddEntry 'Services.Ollama' 'Services' ([string]$InstallState.Ollama.BaseUri) 'string' @() 'Provision' 'Bootstrap-managed endpoint.' $false
    AddEntry 'Services.SurrealDB' 'Services' ([string]$InstallState.SurrealDB.BaseUri) 'string' @() 'Provision' 'Bootstrap-managed endpoint.' $false
    foreach($name in @('ImportDirectory','ExportDirectory','MemoryDirectory')){
        AddEntry ('Services.'+$name) 'Services' ([string]$InstallState.LFO.$name) 'string' @() 'Provision' 'Bootstrap-managed path.' $false
    }
    foreach($key in @('HistoryMaxMessages','CodexTimeoutSec')){
        AddEntry ('Chat.'+$key) 'Inference' $BaseConfig[$key] 'int' @() 'Restart' 'Existing QwenChat setting.'
    }
    foreach($group in @('Memory','LocalGeneration','SynthesisGeneration','Frontier','ResearchLogging','L4','HardGates')){
        if(-not $BaseConfig.ContainsKey($group)){continue}
        $section=switch($group){'Memory'{'Memory'} 'ResearchLogging'{'Research'} 'L4'{'Memory'} 'HardGates'{'Routing'} 'Frontier'{'Routing'} default{'Inference'}}
        foreach($key in @($BaseConfig[$group].Keys|Sort-Object)){
            if($key -match 'Credential|Password|Token|Secret'){continue}
            $v=$BaseConfig[$group][$key]
            $kind=if($v -is [bool]){'bool'}elseif($v -is [int] -or $v -is [long]){'int'}elseif($v -is [double] -or $v -is [decimal]){'number'}elseif($v -is [string]){'string'}else{'complex'}
            $edit=($kind -in @('bool','int','number') -and $group -ne 'L4' -and $key -ne 'L0StageSourcesEnabled')
            $display=if($kind -eq 'complex'){'[structured value: repository managed]'}else{$v}
            AddEntry ('Chat.'+$group+'.'+$key) $section $display $kind @() $(if($edit){'Restart'}else{'Managed'}) ($group+'.'+$key+'; existing runtime parameter.') $edit
        }
    }
    return $r
}
function ConvertTo-LfoConfigurationValue($Entry,$Value){
    if(-not $Entry.Editable){throw 'Managed setting is read-only.'}
    switch($Entry.Kind){
        'bool' {if($Value -isnot [bool]){throw 'Boolean required.'};return $Value}
        'enum' {if($Value -cnotin $Entry.Choices){throw 'Unknown choice.'};return [string]$Value}
        'int' {
            $n=0
            if(-not [int]::TryParse([string]$Value,[ref]$n) -or $n -lt 0 -or $n -gt 10000000){throw 'Integer 0..10000000 required.'}
            if($Entry.Id -match 'CodexTimeoutSec|HistoryMaxMessages|NumPredict|MaxChars|RecentTurns|MaxItems|ScanMaxTurns|MaxPending|NoteMaxChars|StateMaxChars' -and $n -eq 0){throw 'Positive integer required.'}
            return $n
        }
        'number' {
            $n=0.0
            if(-not [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$n) -or [double]::IsNaN($n) -or [double]::IsInfinity($n)){throw 'Finite number required (decimal point).'}
            if($Entry.Id -match 'Temperature' -and ($n -lt 0 -or $n -gt 2)){throw 'Temperature range 0..2.'}
            if($Entry.Id -match 'PresencePenalty' -and ($n -lt -2 -or $n -gt 2)){throw 'Presence penalty range -2..2.'}
            return $n
        }
        default{throw 'Unsupported setting type.'}
    }
}
function Read-LfoConfiguration($Registry,[string]$Path){
    $values=@{}
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return $values}
    $data=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
    if($data.schemaVersion -ne 1 -or $null -eq $data.settings){throw 'Unsupported configuration file.'}
    foreach($p in $data.settings.PSObject.Properties){
        if(-not $Registry.Contains($p.Name)){throw ('Unknown configuration setting: '+$p.Name)}
        $values[$p.Name]=ConvertTo-LfoConfigurationValue $Registry[$p.Name] $p.Value
    }
    return $values
}
function Get-LfoConfigurationValue($Registry,$Values,[string]$Id){
    if($Values.ContainsKey($Id)){return $Values[$Id]}
    return $Registry[$Id].Default
}
function Assert-LfoConfiguration($Registry,$Values){
    foreach($id in $Values.Keys){
        if(-not $Registry.Contains($id)){throw ('Unknown setting: '+$id)}
        $null=ConvertTo-LfoConfigurationValue $Registry[$id] $Values[$id]
    }
    if((Get-LfoConfigurationValue $Registry $Values 'Chat.Memory.StructuredReadEnabled') -and -not (Get-LfoConfigurationValue $Registry $Values 'Chat.Memory.StructuredEnabled')){throw 'Structured read requires structured memory.'}
    if((Get-LfoConfigurationValue $Registry $Values 'Chat.LocalGeneration.LeanReadPolicyEnabled') -and -not (Get-LfoConfigurationValue $Registry $Values 'Chat.LocalGeneration.CompactReadSchemaEnabled')){throw 'Lean read policy requires compact schema.'}
    if((Get-LfoConfigurationValue $Registry $Values 'Chat.LocalGeneration.LowerTrustL2EvidenceEnabled') -and -not (Get-LfoConfigurationValue $Registry $Values 'Chat.LocalGeneration.LeanReadPolicyEnabled')){throw 'Lower-trust evidence requires lean read policy.'}
}
function Save-LfoConfiguration($Registry,$Values,[string]$Path){
    Assert-LfoConfiguration $Registry $Values
    $payload=[ordered]@{schemaVersion=1;settings=[ordered]@{}}
    foreach($id in @($Values.Keys|Sort-Object)){$payload.settings[$id]=$Values[$id]}
    $dir=Split-Path -Parent $Path
    $null=New-Item -ItemType Directory -Force -Path $dir
    $temp=Join-Path $dir ('.settings-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{
        [IO.File]::WriteAllText($temp,($payload|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,$null)}else{[IO.File]::Move($temp,$Path)}
    }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
function Set-LfoChatConfiguration($Config,$Values){
    foreach($id in $Values.Keys){
        if($id -notlike 'Chat.*'){continue}
        $parts=$id.Split('.')
        if($parts.Count -eq 2){$Config[$parts[1]]=$Values[$id]}
        elseif($parts.Count -eq 3){$Config[$parts[1]][$parts[2]]=$Values[$id]}
    }
}
function Set-LfoEpistemicConfiguration($Controller,$Values){
    if($null -eq $Controller){return}
    if($Values.ContainsKey('Epistemic.Mode')){$Controller.Mode=$Values['Epistemic.Mode']}
    foreach($axis in @($Controller.Axes.Keys)){
        $id='Epistemic.Axis.'+$axis
        if($Values.ContainsKey($id)){$Controller.Axes[$axis]=$Values[$id]}
    }
    foreach($det in @($Controller.Modules.Keys)){
        $id='Epistemic.Detector.'+$det
        if($Values.ContainsKey($id)){$Controller.Modules[$det].Enabled=$Values[$id]}
    }
}
