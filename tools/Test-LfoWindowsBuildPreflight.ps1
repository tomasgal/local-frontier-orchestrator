param(
    [string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'LocalFrontierOrchestrator'),
    [string]$ResultPath=''
)
$ErrorActionPreference='Stop'
$InstallRoot=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallRoot))
if([string]::IsNullOrWhiteSpace($ResultPath)){$ResultPath=Join-Path $InstallRoot 'build-preflight-report.json'}
$statePath=Join-Path $InstallRoot 'install-state.json'
if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw 'install-state.json missing.'}
$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json
if([string]$state.schema -cne 'lfo-windows-install-v1'){throw 'Unsupported install-state schema.'}
$repoRoot=[string]$state.repo_root
$script:checks=0
function Assert([bool]$Condition,[string]$Message){$script:checks++;if(-not $Condition){throw $Message}}

Assert (Test-Path -LiteralPath $repoRoot -PathType Container) 'repo root exists'
$git=[string]$state.git_exe
if([string]::IsNullOrWhiteSpace($git) -or -not(Test-Path -LiteralPath $git -PathType Leaf)){throw 'Installed Git executable is unavailable.'}
$head=(& $git -C $repoRoot rev-parse HEAD).Trim()
Assert ($LASTEXITCODE -eq 0) 'git rev-parse'
Assert ($head -ceq [string]$state.commit) 'installed commit equals install state'
$dirty=@(& $git -C $repoRoot status --porcelain)
Assert ($LASTEXITCODE -eq 0 -and $dirty.Count -eq 0) 'installed checkout clean'

$staticResult=Join-Path $env:TEMP ('lfo-static-'+[guid]::NewGuid().ToString('N')+'.json')
$p1Result=Join-Path $env:TEMP ('lfo-p1compat-'+[guid]::NewGuid().ToString('N')+'.json')
try{
    & (Join-Path $repoRoot 'tests/Test-LfoIntegratedBuildStatic.ps1') -ResultPath $staticResult
    Assert ($LASTEXITCODE -eq 0) 'integrated static gate process'
    $sr=Get-Content -LiteralPath $staticResult -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ([bool]$sr.pass) 'integrated static gate result'
    & (Join-Path $repoRoot 'tests/Test-LfoEpistemicPolicyCompatibility.ps1') -ResultPath $p1Result
    Assert ($LASTEXITCODE -eq 0) 'P1 compatibility gate process'
    $pr=Get-Content -LiteralPath $p1Result -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ([bool]$pr.pass) 'P1 compatibility gate result'
}finally{Remove-Item -LiteralPath $staticResult,$p1Result -Force -ErrorAction SilentlyContinue}

$config=Import-PowerShellDataFile -LiteralPath ([string]$state.qwen_config)
Assert ([string]$config.Model -ceq [string]$state.model) 'generated model binding'
Assert ([bool]$config.Memory.L0StageSourcesEnabled) 'installed L0 provenance enabled'
Assert ([bool]$config.Memory.StructuredReadEnabled) 'installed L2 read enabled'
Assert ([bool]$config.Memory.L3ReadEnabled -and [bool]$config.Memory.L3IndexEnabled) 'installed L3 enabled'
Assert ([bool]$config.Epistemic.Enabled) 'installed L4 infrastructure enabled'
Assert (-not [bool]$config.Epistemic.PolicyEnabled -and -not [bool]$config.Epistemic.InterventionEnabled) 'installed automatic L4 OFF'

$ov=Invoke-RestMethod -Uri ('http://127.0.0.1:'+([int]$state.ollama_port)+'/api/version') -TimeoutSec 3
Assert (-not [string]::IsNullOrWhiteSpace([string]$ov.version)) 'Ollama API ready'
$sv=Invoke-RestMethod -Uri ('http://127.0.0.1:'+([int]$state.surreal_port)+'/version') -TimeoutSec 3
Assert ([string]$sv -match '3\.3\.0') 'SurrealDB 3.3.0 ready'
Assert (Test-Path -LiteralPath ([string]$state.l4_runtime_credential) -PathType Leaf) 'L4 runtime credential exists'

$models=Invoke-RestMethod -Uri ('http://127.0.0.1:'+([int]$state.ollama_port)+'/api/tags') -TimeoutSec 10
$modelNames=@($models.models|ForEach-Object{[string]$_.name})
$wanted=[string]$state.model
$baseName=($wanted -split ':')[0]
Assert (($modelNames -contains $wanted) -or (@($modelNames|Where-Object{$_ -eq $wanted -or $_ -like ($baseName+':*')}).Count -gt 0)) 'configured Ollama model present'

$report=[ordered]@{
    schema='lfo-windows-build-preflight-v1'
    pass=$true
    checks=$script:checks
    commit=$head
    powershell=[string]$PSVersionTable.PSVersion
    ollama_version=[string]$ov.version
    surreal_version=[string]$sv
    sqlite_version=[string]$state.sqlite_version
    ollama_sha256=(Get-FileHash -LiteralPath ([string]$state.ollama_exe) -Algorithm SHA256).Hash.ToLowerInvariant()
    surreal_sha256=(Get-FileHash -LiteralPath ([string]$state.surreal_exe) -Algorithm SHA256).Hash.ToLowerInvariant()
    model=[string]$state.model
    automatic_l4_policy=$false
    automatic_l4_intervention=$false
    model_calls=0
    automatic_r1_writes=0
    production_memory_touched=$false
}
[IO.File]::WriteAllText($ResultPath,(($report|ConvertTo-Json -Depth 6)+[Environment]::NewLine),(New-Object Text.UTF8Encoding($false)))
Write-Host ('WINDOWS_BUILD_PREFLIGHT_PASS: '+$script:checks+' checks; commit='+$head+'; ModelCalls=0; AutomaticR1Writes=0')
Write-Host ('Report: '+$ResultPath)