[CmdletBinding()]
param([string]$InstallRoot,[ValidateSet('Models','Inference','Routing','Epistemic','Memory','Hardware','Interface','Research','Services')][string]$Section='Epistemic',[switch]$Ascii)
$ErrorActionPreference='Stop'
if(-not $InstallRoot){
    foreach($candidate in @($env:LFO_INSTALL_ROOT,$PSScriptRoot,(Split-Path -Parent $PSScriptRoot),(Join-Path $env:LOCALAPPDATA 'LFO'))){
        if($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'config/install-state.json') -PathType Leaf)){$InstallRoot=$candidate;break}
    }
}
if(-not $InstallRoot){throw 'LFO installation not found. Pass -InstallRoot.'}
$state=Get-Content -LiteralPath (Join-Path $InstallRoot 'config/install-state.json') -Raw -Encoding UTF8|ConvertFrom-Json
$root=[string]$state.AppRoot
. (Join-Path $root 'src/LfoConfiguration.ps1')
. (Join-Path $root 'src/LfoConfigurationTui.ps1')
$config=Import-PowerShellDataFile -LiteralPath ([string]$state.LFO.ConfigPath)
$registry=Get-LfoConfigurationRegistry $config $state $root
$path=Get-LfoConfigurationPath $InstallRoot
$settings=Read-LfoConfiguration $registry $path
$null=Show-LfoConfigurationTui $registry $settings $path -Section $Section -Ascii:($Ascii -or $env:LFO_CONFIG_ASCII -eq '1')
