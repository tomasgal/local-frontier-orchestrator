# Dot-source for this shell only. No profile, machine policy or Ollama settings change.
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::InputEncoding=New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$global:OutputEncoding=[Console]::OutputEncoding
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$Host.UI.RawUI.WindowTitle='LFO | shell'
Write-Host ('Console: '+$env:COMPUTERNAME+' | PowerShell '+$PSVersionTable.PSVersion)

