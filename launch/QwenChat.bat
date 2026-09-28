@echo off
chcp 65001 >nul
setlocal

set "SCRIPT=%~dp0..\src\QwenChat.ps1"

if not exist "%SCRIPT%" (
  echo Error: QwenChat.ps1 was not found at "%SCRIPT%".
  pause
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
endlocal
