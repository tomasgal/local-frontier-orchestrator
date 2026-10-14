param(
    [string]$InstallRoot,
    [ValidatePattern('^\d{4}-\d{2}$')][string]$Month = (Get-Date -Format 'yyyy-MM')
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Split-Path -Parent $PSScriptRoot
}

$logPath = Join-Path $InstallRoot ("data\memory\logs\conversation-{0}.jsonl" -f $Month)
if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    throw "Conversation log not found: $logPath"
}

Get-Content -LiteralPath $logPath -Encoding UTF8 |
    ForEach-Object { $_ | ConvertFrom-Json } |
    Select-Object turn_id,epoch,route,user,assistant |
    Format-Table -Wrap
