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
    foreach($bad in @(@{'Epistemic.Mode'='INTERVENE'},@{'Models.UMA'='other'},@{'Session.Think'='false'},@{'Chat.LocalGeneration.Temperature'=9})){
        $rejected=$false;try{Assert-LfoConfiguration $r $bad}catch{$rejected=$true}
        if(-not $rejected){throw 'Invalid setting accepted'}
    }
    if((Get-LfoConfigurationValue $r @{} 'Session.Route') -ne 'AUTO'){throw 'Default'}
    Write-Host 'Configuration registry, validation, persistence and overlay PASS.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}

. (Join-Path $root 'src/LfoConfigurationTui.ps1')
foreach($size in @(@(80,25),@(180,50),@(240,60))){
    $v=Get-LfoConfigurationViewport $size[0] $size[1]
    if($v.Width -ne ($size[0]-1) -or $v.Height -ne $size[1] -or $v.Rows+6 -ne $size[1] -or $v.Left+$v.Right+3 -ne $v.Width){throw 'Viewport geometry failed'}
}
$small=$false;try{$null=Get-LfoConfigurationViewport 60 15}catch{$small=$true}
if(-not $small){throw 'Small terminal must fall back'}
# The Slovak hard gate must survive the Windows PowerShell data-file parser.
$word='a '+[char]0x010d+'o'
if($word -notmatch $cfg.HardGates.FollowUpPattern){throw 'UTF-8 data-file regex damaged'}
$bytes=[IO.File]::ReadAllBytes((Join-Path $root 'config/QwenChat.config.psd1'))
if($bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191){throw 'UTF-8 BOM missing from repository PSD1'}
Write-Host 'Viewport and UTF-8 data-file contract PASS.'
