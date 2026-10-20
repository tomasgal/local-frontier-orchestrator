param(
    [Parameter(Mandatory)][ValidateSet('Ollama','SurrealDB')][string]$Service,
    [Parameter(Mandatory)][string]$BaseUri,
    [ValidateRange(1,3600)][int]$HeartbeatSeconds = 60,
    [ValidateRange(1,60)][int]$PollSeconds = 2
)
$ErrorActionPreference = 'Continue'
chcp 65001 > $null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$Host.UI.RawUI.WindowTitle = "LFO | $Service monitor"

Write-Host "LFO $Service status monitor" -ForegroundColor Cyan
Write-Host "Monitoring $Service API state. LFO-owned services run headless; raw stdout/stderr are redirected under the LFO runtime logs directory."
Write-Host "Endpoint: $BaseUri"
Write-Host "Status changes are shown immediately; unchanged state is shown at most once every $HeartbeatSeconds seconds."
Write-Host 'Press Ctrl+C to close this monitor.'
Write-Host ''

$lastState = $null
$lastOutput = [DateTime]::MinValue

while ($true) {
    try {
        if ($Service -eq 'Ollama') {
            $v = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/api/version') -TimeoutSec 2
            $ps = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/api/ps') -TimeoutSec 2
            $models = @($ps.models | ForEach-Object { $_.name }) -join ', '
            if ([string]::IsNullOrWhiteSpace($models)) { $models = '(idle)' }
            $state = ('READY version={0} loaded={1}' -f $v.version,$models)
        } else {
            $null = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/ready') -TimeoutSec 2
            $v = Invoke-RestMethod -Uri ($BaseUri.TrimEnd('/') + '/version') -TimeoutSec 2
            $state = ('READY version={0}' -f ([string]$v).Trim())
        }
    } catch {
        $state = ('NOT READY: {0}' -f $_.Exception.Message)
    }

    $now = Get-Date
    $changed = ($state -cne $lastState)
    $heartbeatDue = (($now - $lastOutput).TotalSeconds -ge $HeartbeatSeconds)

    if ($changed -or $heartbeatDue) {
        $kind = if ($changed -and $null -ne $lastState) { 'CHANGE' } elseif ($changed) { 'STATE' } else { 'HEARTBEAT' }
        Write-Host ('{0:HH:mm:ss} [{1}] {2}' -f $now,$kind,$state)
        $lastState = $state
        $lastOutput = $now
    }

    Start-Sleep -Seconds $PollSeconds
}
