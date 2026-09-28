@echo off
chcp 65001 >nul
title Local Frontier Orchestrator - Ollama
setlocal

set "SCRIPT=%~dp0Start-Ollama.ps1"

if not exist "%SCRIPT%" (
  echo Error: Start-Ollama.ps1 was not found next to this BAT file.
  pause
  exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*

if errorlevel 1 (
  echo.
  echo Ollama launcher exited with an error.
  pause
)

endlocal
