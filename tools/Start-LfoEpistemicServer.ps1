# Foreground server: console remains visible. No service, Docker or Ollama required.
param([Parameter(Mandatory)][string]$Binary,[Parameter(Mandatory)][string]$DataDirectory,
    [ValidateRange(1024,65535)][int]$Port=18080,
    [ValidateSet('info','debug')][string]$LogLevel='info')
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath $DataDirectory -PathType Container)) { throw 'Create an explicit L4-only data directory first.' }
$version = & $Binary version
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^3\.3\.0 ') { throw 'Expected SurrealDB 3.3.0 binary.' }
if (-not $env:SURREAL_USER -or -not $env:SURREAL_PASS) { throw 'Set process SURREAL_USER and SURREAL_PASS for bootstrap before launch.' }
$path = 'rocksdb://' + (Join-Path ([IO.Path]::GetFullPath($DataDirectory)) 'observations.db').Replace('\','/')
& $Binary start --bind ('127.0.0.1:'+$Port) --query-timeout 3s --deny-guests --deny-scripting --deny-net --log $LogLevel $path
if ($LASTEXITCODE -ne 0) { throw 'SurrealDB exited with failure.' }
