$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/LfoConfiguration.ps1')
$cfg=Import-PowerShellDataFile (Join-Path $root 'config/QwenChat.config.psd1')
$state=[pscustomobject]@{LFO=[pscustomobject]@{DefaultPriority='High'};Ollama=[pscustomobject]@{UMAModel='fixture:latest'};SurrealDB=[pscustomobject]@{}}
$r=Get-LfoConfigurationRegistry $cfg $state $root
if($r.Count -lt 35 -or $r['Epistemic.Axis.E1'].Default -ne 'MEDIUM' -or $r['Models.UMA'].Editable){throw 'Registry contract'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('lfo-cfg-'+[guid]::NewGuid().ToString('N'))
$p=Join-Path $temp 'user-settings.json'
try{
    $v=@{'Epistemic.Axis.E1'='HIGH';'Session.Route'='LOCAL';'Session.Think'=$true;'Chat.LocalGeneration.Temperature'=0.3}
    Save-LfoConfiguration $r $v $p
    $got=Read-LfoConfiguration $r $p
    if($got.Count -ne 4 -or $got['Session.Think'] -ne $true -or $got['Epistemic.Axis.E1'] -ne 'HIGH'){throw 'Roundtrip'}
    Set-LfoChatConfiguration $cfg $got
    if($cfg.LocalGeneration.Temperature -ne 0.3){throw 'Chat overlay'}
    $v['Session.Route']='FRONTIER';Save-LfoConfiguration $r $v $p
    if((Read-LfoConfiguration $r $p)['Session.Route'] -ne 'FRONTIER'){throw 'Replacement'}
    foreach($bad in @(@{'Epistemic.Mode'='INVALID'},@{'Epistemic.InterventionPolicy'='ADAPTIVE'},@{'Models.UMA'='other'},@{'Session.Think'='false'},@{'Chat.LocalGeneration.Temperature'=9})){
        $rejected=$false;try{Assert-LfoConfiguration $r $bad}catch{$rejected=$true}
        if(-not $rejected){throw 'Invalid setting accepted'}
    }
    if((Get-LfoConfigurationValue $r @{} 'Session.Route') -ne 'AUTO'){throw 'Default'}
    Write-Host 'Configuration registry, validation, persistence and overlay PASS.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}

. (Join-Path $root 'src/LfoConfigurationTui.ps1')
foreach($size in @(@(80,25),@(180,50),@(240,60))){
    $v=Get-LfoConfigurationViewport $size[0] $size[1]
    if($v.Width -ne ($size[0]-1) -or $v.Height -ne $size[1] -or $v.Rows+9 -ne $size[1] -or $v.Left+$v.Right+3 -ne $v.Width){throw 'Viewport geometry failed'}
}
$small=$false;try{$null=Get-LfoConfigurationViewport 60 15}catch{$small=$true}
if(-not $small){throw 'Small terminal must fall back'}
# The Slovak hard gate must survive the Windows PowerShell data-file parser.
$word='a '+[char]0x010d+'o'
if($word -notmatch $cfg.HardGates.FollowUpPattern){throw 'UTF-8 data-file regex damaged'}
$bytes=[IO.File]::ReadAllBytes((Join-Path $root 'config/QwenChat.config.psd1'))
if($bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191){throw 'UTF-8 BOM missing from repository PSD1'}
Write-Host 'Viewport and UTF-8 data-file contract PASS.'

foreach($entry in $r.Values){
    $h=Get-LfoConfigurationHint $entry $true 1
    if(-not $h.Meaning -or -not $h.Action -or -not $h.Impact -or -not $h.LongHelp){throw ('Missing context help: '+$entry.Id)}
}
$h=Get-LfoConfigurationHint $r['Runtime.Device'] $true 1
if($h.Action -notmatch 'Auto / CPU / GPU / UMA' -or $h.LongHelp -notmatch 'Strix Halo' -or $h.Impact -notmatch 'relaunch'){throw 'Device help semantics'}
$h=Get-LfoConfigurationHint $r['Epistemic.Mode'] $true 1
if($h.LongHelp -notmatch 'OBSERVE' -or $h.Impact -notmatch 'F10'){throw 'Live help semantics'}
$h=Get-LfoConfigurationHint $r['Models.UMA'] $false 1
if($h.Action -notmatch 'Read-only'){throw 'Read-only help semantics'}
$wrapped=@(Split-LfoConfigurationHelpText 'one two three four five' 8)
if(($wrapped -join ' ') -ne 'one two three four five' -or @($wrapped|Where-Object{$_.Length -gt 8}).Count){throw 'Help wrap'}
Write-Host 'Context help and footer layout PASS.'

$ep=Import-PowerShellDataFile (Join-Path $root 'config/EpistemicRegistry.psd1')
foreach($axis in $ep.Axes.Keys){
    $id='Epistemic.Axis.'+$axis
    if($r[$id].DisplayLabel -cne ($axis+' - '+$ep.Axes[$axis]) -or $r[$id].Id -cne $id){throw ('Axis display label contract: '+$axis)}
}
foreach($entry in $r.Values){if(-not $entry.DisplayLabel){throw ('Missing display label: '+$entry.Id)}}
Write-Host 'Axis display labels PASS (canonical registry; stable configuration IDs).'

if($r['Epistemic.InterventionPolicy'].Default -cne 'STANDARD' -or ($r['Epistemic.InterventionPolicy'].Choices -join ',') -cne 'MINIMAL,STANDARD,CASCADE' -or 'INTERVENE' -notin $r['Epistemic.Mode'].Choices){throw 'Intervention policy menu'}
Assert-LfoConfiguration $r @{'Epistemic.Mode'='INTERVENE';'Epistemic.InterventionPolicy'='CASCADE'}
Write-Host 'Intervention menu contract PASS.'
