param(
    [Parameter(Mandatory)][ValidateSet('Ollama','SurrealDB')][string]$Service,
    [Parameter(Mandatory)][string]$BaseUri
)
$ErrorActionPreference = 'Continue'
chcp 65001 > $null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$Host.UI.RawUI.WindowTitle = "LFO | $Service activity monitor"
Write-Host "Reusing an already-running $Service service." -ForegroundColor Cyan
Write-Host "This window monitors service activity; the original process owns its raw stdout/stderr."
Write-Host "Endpoint: $BaseUri"
Write-Host 'Press Ctrl+C to close this monitor.'
Write-Host ''
$last = ''
while ($true) {
    try {
        if ($Service -eq 'Ollama') {
            $v = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/api/version') -TimeoutSec 2
            $ps = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/api/ps') -TimeoutSec 2
            $models = @($ps.models | ForEach-Object { $_.name }) -join ', '
            if ([string]::IsNullOrWhiteSpace($models)) { $models = '(idle)' }
            $line = ('{0:HH:mm:ss} READY version={1} loaded={2}' -f (Get-Date),$v.version,$models)
        } else {
            $null = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/ready') -TimeoutSec 2
            $v = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/version') -TimeoutSec 2
            $line = ('{0:HH:mm:ss} READY version={1}' -f (Get-Date),([string]$v).Trim())
        }
    } catch {
        $line = ('{0:HH:mm:ss} NOT READY: {1}' -f (Get-Date),$_.Exception.Message)
    }
    if ($line -ne $last) { Write-Host $line; $last = $line }
    Start-Sleep -Seconds 2
}
