# Isolated Windows gate; does not install a service or start Ollama.
param([Parameter(Mandatory)][string]$WorkDirectory,[string]$SurrealBinary='')
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Windows acceptance runner.' }
. (Join-Path $PSScriptRoot 'Initialize-LfoWindowsConsole.ps1')
$root=[IO.Path]::GetFullPath($WorkDirectory)
if (Test-Path -LiteralPath $root) { throw 'Choose a new work directory; existing data is never reused by this runner.' }
$null=New-Item -ItemType Directory -Path $root
$runtime=Import-PowerShellDataFile (Join-Path $PSScriptRoot '../config/L4Runtime.psd1')
if ($SurrealBinary) {
    $binary=(Resolve-Path -LiteralPath $SurrealBinary -ErrorAction Stop).Path
    Write-Host 'Reusing downloaded SurrealDB runtime; verifying SHA256...'
} else {
    $binary=Join-Path $root 'surreal.exe'
    Write-Host 'Downloading pinned SurrealDB 3.3.0 Windows runtime...'
    Invoke-WebRequest -UseBasicParsing -Uri $runtime.WindowsUrl -OutFile $binary
}
if ((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant() -cne $runtime.WindowsSHA256) { throw 'SurrealDB binary checksum mismatch.' }
$version=& $binary version
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^3\.3\.0 ') { throw 'SurrealDB version mismatch.' }
$engine=Join-Path $PSHOME $(if ($PSVersionTable.PSEdition -eq 'Desktop') {'powershell.exe'} else {'pwsh.exe'})
$log=Join-Path $root 'acceptance.log'
$errorLog=Join-Path $root 'acceptance.err.log'
$test=(Resolve-Path (Join-Path $PSScriptRoot '../tests/Test-LfoEpistemicStore.ps1')).Path
# Native stderr under PS5.1 must not terminate this wrapper before it reports
# the actual test failure and evidence location.
$process=Start-Process -FilePath $engine -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$test+'"'),'-SurrealBinary',('"'+$binary+'"')) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError $errorLog
$exitCode=$process.ExitCode
$process.Dispose()
if ($exitCode -ne 0) { Get-Content -LiteralPath $log -Tail 40;Get-Content -LiteralPath $errorLog -Tail 40;throw ('L4 R1 acceptance failed. Evidence: '+$root) }
Get-Content -LiteralPath $log -Tail 10
Write-Host ('Windows acceptance log: '+$log)

