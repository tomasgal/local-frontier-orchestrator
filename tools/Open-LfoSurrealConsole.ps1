# Explicit Windows development environment, independent of production memory.
param([Parameter(Mandatory)][string]$Binary,
    [Parameter(Mandatory)][string]$Workspace,
    [ValidateRange(1024,65535)][int]$Port=18080,
    [ValidateSet('info','debug')][string]$LogLevel='debug')
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This visible-console helper requires Windows.' }
$Binary=(Resolve-Path -LiteralPath $Binary).Path
$runtime=Import-PowerShellDataFile (Join-Path $PSScriptRoot '../config/L4Runtime.psd1')
if ((Get-FileHash -LiteralPath $Binary -Algorithm SHA256).Hash.ToLowerInvariant() -cne $runtime.WindowsSHA256) { throw 'Runtime checksum mismatch.' }
$Workspace=[IO.Path]::GetFullPath($Workspace)
if ([IO.Path]::GetPathRoot($Workspace) -eq $Workspace) { throw 'Use a dedicated workspace directory, not a filesystem root.' }
$client=New-Object Net.Sockets.TcpClient
try { $client.Connect('127.0.0.1',$Port);$busy=$true } catch { $busy=$false } finally { $client.Dispose() }
if ($busy) { throw ('Port '+$Port+' is occupied. No existing process was stopped.') }
$marker=Join-Path $Workspace 'lfo-dev-environment.json'
$adminFile=Join-Path $Workspace 'bootstrap.credential.xml'
$runtimeFile=Join-Path $Workspace 'runtime.credential.xml'
$data=Join-Path $Workspace 'data'
if (Test-Path -LiteralPath $Workspace) {
    $saved=Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($saved.kind -cne 'LFO-L4-R1-DEV' -or $saved.port -ne $Port -or -not (Test-Path -LiteralPath $adminFile) -or -not (Test-Path -LiteralPath $runtimeFile)) { throw 'Incomplete or unrelated development directory.' }
} else {
    $null=New-Item -ItemType Directory -Path $data
    # Windows Export-Clixml protects PSCredential secrets using current-user DPAPI.
    $admin=New-Object Management.Automation.PSCredential('lfo_bootstrap',(ConvertTo-SecureString ([guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N')) -AsPlainText -Force))
    $credential=New-Object Management.Automation.PSCredential('lfo_r1',(ConvertTo-SecureString ([guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N')) -AsPlainText -Force))
    $admin | Export-Clixml -LiteralPath $adminFile
    $credential | Export-Clixml -LiteralPath $runtimeFile
    @{kind='LFO-L4-R1-DEV';port=$Port;endpoint=('http://127.0.0.1:'+$Port)} | ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding UTF8
}
$admin=Import-Clixml -LiteralPath $adminFile
$credential=Import-Clixml -LiteralPath $runtimeFile
$launcher=(Resolve-Path (Join-Path $PSScriptRoot 'Start-LfoEpistemicServer.ps1')).Path
function Quote-LfoConsoleLiteral([string]$Value) { return "'"+$Value.Replace("'","''")+"'" }
# Encoded command contains paths/settings only, never passwords. Credentials
# are decrypted in the visible child window under the same Windows account.
$code=@'
$ErrorActionPreference='Stop'
$Host.UI.RawUI.WindowTitle='LFO | SurrealDB DEV server'
$c=Import-Clixml -LiteralPath __ADMIN__
$env:SURREAL_USER=$c.UserName
$env:SURREAL_PASS=$c.GetNetworkCredential().Password
Write-Host 'SurrealDB DEV: operational/diagnostic log. Ctrl+C stops the foreground server.'
try { & __LAUNCHER__ -Binary __BINARY__ -DataDirectory __DATA__ -Port __PORT__ -LogLevel __LEVEL__ }
finally { Remove-Item Env:SURREAL_USER,Env:SURREAL_PASS -ErrorAction SilentlyContinue }
'@
$code=$code.Replace('__ADMIN__',(Quote-LfoConsoleLiteral $adminFile)).Replace('__LAUNCHER__',(Quote-LfoConsoleLiteral $launcher)).Replace('__BINARY__',(Quote-LfoConsoleLiteral $Binary)).Replace('__DATA__',(Quote-LfoConsoleLiteral $data)).Replace('__PORT__',[string]$Port).Replace('__LEVEL__',(Quote-LfoConsoleLiteral $LogLevel))
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
$engine=Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Desktop') {'powershell.exe'} else {'pwsh.exe'})
$null=Start-Process -FilePath $engine -ArgumentList @('-NoProfile','-NoExit','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded)
$endpoint='http://127.0.0.1:'+$Port
$ready=$false
for($i=0;$i -lt 40;$i++) {
    try { $null=Invoke-RestMethod ($endpoint+'/ready') -TimeoutSec 1;$ready=$true;break }
    catch { Start-Sleep -Milliseconds 250 }
}
if (-not $ready) { throw 'Server did not become ready. Inspect its visible console; no existing process was stopped.' }
. (Join-Path $PSScriptRoot '../src/LfoEpistemicStore.ps1')
$bootstrap=New-LfoEpistemicConnection $endpoint $admin -Bootstrap
Initialize-LfoEpistemicSchema $bootstrap $credential
Write-Host ('DEV_SERVER_READY: '+$endpoint+' | lfo / epistemic')
Write-Host ('Workspace: '+$Workspace)
Write-Host ('Runtime credential: '+$runtimeFile+' (Windows current-user encrypted)')
Write-Host 'Server window stays open. This shell is free. Ollama was not started; production memory untouched.'

