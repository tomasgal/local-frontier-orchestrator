# Optional, not called by R1 tests. Foreground server in its own visible window.
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This visible-console helper requires Windows.' }
$ollama=(Get-Command ollama -CommandType Application -ErrorAction Stop).Source
$client=New-Object Net.Sockets.TcpClient
try { $client.Connect('127.0.0.1',11434);$busy=$true } catch { $busy=$false } finally { $client.Dispose() }
if ($busy) { throw 'Port 11434 is occupied. Exit the existing Ollama tray/server yourself before starting a foreground server.' }
# Only the child window inherits these values. No permanent environment mutation.
$escaped=$ollama.Replace("'","''")
$command="`$Host.UI.RawUI.WindowTitle='LFO | Ollama server';`$env:OLLAMA_HOST='127.0.0.1:11434';`$env:OLLAMA_DEBUG='1';`$env:CUDA_VISIBLE_DEVICES='-1';`$env:OLLAMA_VULKAN='0';& '$escaped' serve"
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$engine=Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Desktop') {'powershell.exe'} else {'pwsh.exe'})
Start-Process -FilePath $engine -ArgumentList @('-NoProfile','-NoExit','-EncodedCommand',$encoded) | Out-Null
Write-Host 'Foreground Ollama window opened. This shell stays available. No model was loaded.'

