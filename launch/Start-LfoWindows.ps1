param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'LocalFrontierOrchestrator'),
    [ValidateSet('GPU','CPU')][string]$Profile = 'GPU',
    [switch]$NoChat
)
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'LFO Windows launcher requires Windows.'}
. (Join-Path $PSScriptRoot '..\tools\Initialize-LfoWindowsConsole.ps1')

$InstallRoot=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallRoot))
$statePath=Join-Path $InstallRoot 'install-state.json'
if(-not (Test-Path -LiteralPath $statePath -PathType Leaf)){throw "LFO install state not found: $statePath"}
$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if([string]$state.schema -cne 'lfo-windows-install-v1'){throw 'Unsupported LFO install-state schema.'}

$ollamaExe=[string]$state.ollama_exe
$surrealExe=[string]$state.surreal_exe
$configPath=[string]$state.qwen_config
$model=[string]$state.model
$modelsDir=[string]$state.models_dir
$ollamaPort=[int]$state.ollama_port
$surrealPort=[int]$state.surreal_port
$l4Workspace=[string]$state.l4_workspace
foreach($p in @($ollamaExe,$surrealExe,$configPath)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Installed component missing: $p"}}

function Test-LfoTcpPort([int]$Port){
    $c=New-Object Net.Sockets.TcpClient
    try{$c.Connect('127.0.0.1',$Port);return $true}catch{return $false}finally{$c.Dispose()}
}
function Escape-LfoSingleQuoted([string]$Value){return $Value.Replace("'","''")}

$ollamaBase='http://127.0.0.1:'+$ollamaPort
$ollamaRunning=$false
try{
    $v=Invoke-RestMethod -Uri ($ollamaBase+'/api/version') -TimeoutSec 1
    $ollamaRunning=$true
    Write-Host ("Ollama already responding at {0} (v{1}); existing process retained." -f $ollamaBase,$v.version)
}catch{}
if(-not $ollamaRunning){
    if(Test-LfoTcpPort $ollamaPort){throw "Ollama port $ollamaPort is occupied by a non-Ollama endpoint. Existing process was not stopped."}
    $context=if($Profile -eq 'CPU'){5120}else{8192}
    $modeBlock=if($Profile -eq 'CPU'){
@'
$env:CUDA_VISIBLE_DEVICES='-1'
$env:ROCR_VISIBLE_DEVICES='-1'
$env:OLLAMA_VULKAN='0'
$env:GGML_VK_VISIBLE_DEVICES='-1'
'@
    }else{
@'
Remove-Item Env:CUDA_VISIBLE_DEVICES,Env:ROCR_VISIBLE_DEVICES,Env:OLLAMA_VULKAN,Env:GGML_VK_VISIBLE_DEVICES -ErrorAction SilentlyContinue
'@
    }
    $code=@'
$ErrorActionPreference='Stop'
$Host.UI.RawUI.WindowTitle='LFO | Ollama __PROFILE__'
$env:OLLAMA_HOST='127.0.0.1:__PORT__'
$env:OLLAMA_MODELS='__MODELS__'
$env:OLLAMA_CONTEXT_LENGTH='__CONTEXT__'
$env:OLLAMA_NUM_PARALLEL='1'
$env:OLLAMA_MAX_LOADED_MODELS='1'
$env:OLLAMA_NO_CLOUD='1'
$env:OLLAMA_DEBUG='1'
__MODEBLOCK__
Write-Host 'LFO Ollama __PROFILE__ server: live foreground log. Ctrl+C stops this server.'
& '__OLLAMA__' serve
'@
    $code=$code.Replace('__PROFILE__',(Escape-LfoSingleQuoted $Profile)).
        Replace('__PORT__',[string]$ollamaPort).
        Replace('__MODELS__',(Escape-LfoSingleQuoted $modelsDir)).
        Replace('__CONTEXT__',[string]$context).
        Replace('__MODEBLOCK__',$modeBlock).
        Replace('__OLLAMA__',(Escape-LfoSingleQuoted $ollamaExe))
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $windowsPowerShell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $null=Start-Process -FilePath $windowsPowerShell -ArgumentList @('-NoLogo','-NoProfile','-NoExit','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded)
    for($i=0;$i -lt 120;$i++){
        try{$null=Invoke-RestMethod -Uri ($ollamaBase+'/api/version') -TimeoutSec 1;$ollamaRunning=$true;break}
        catch{Start-Sleep -Milliseconds 250}
    }
    if(-not $ollamaRunning){throw 'Ollama did not become ready. Inspect the visible Ollama console.'}
}

$surrealBase='http://127.0.0.1:'+$surrealPort
$surrealRunning=$false
try{
    $null=Invoke-RestMethod -Uri ($surrealBase+'/ready') -TimeoutSec 1
    $surrealRunning=$true
    Write-Host ("SurrealDB already responding at {0}; existing process retained." -f $surrealBase)
}catch{}
if(-not $surrealRunning){
    if(Test-LfoTcpPort $surrealPort){throw "SurrealDB port $surrealPort is occupied by another endpoint. Existing process was not stopped."}
    & (Join-Path $PSScriptRoot '..\tools\Open-LfoSurrealConsole.ps1') -Binary $surrealExe -Workspace $l4Workspace -Port $surrealPort -LogLevel debug
}

if($NoChat){Write-Host ("LFO services ready. Profile={0}; model={1}" -f $Profile,$model);return}
Write-Host ("Starting QwenChat with complete-build profile: {0}" -f $Profile)
$contextHint=if($Profile -eq 'CPU'){5120}else{8192}
& (Join-Path $PSScriptRoot '..\src\QwenChat.ps1') -ConfigPath $configPath -ContextLengthHint $contextHint
