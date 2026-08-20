# Detached entry for Start-Watchdog. Transcript + crash log are the W-03
# forensics the hidden Start-Process used to throw away.
param(
  [Parameter(Mandatory)][string]$ConfigPath
)
$ErrorActionPreference = 'Continue'
$moduleRoot = $PSScriptRoot
Get-ChildItem (Join-Path $moduleRoot 'Private\*.ps1') | ForEach-Object { . $_.FullName }

$config = Resolve-WatchdogConfig -Path $ConfigPath
if (Test-WatchdogError $config) {
  Write-WatchdogError -ErrorObject $config
  exit $config.exitCode
}

$paths = Get-WatchdogPaths -Root $config.Root
if (-not (Test-Path $config.Root)) {
  New-Item -ItemType Directory -Path $config.Root -Force | Out-Null
}

try {
  Start-Transcript -Path $paths.Console -Append | Out-Null
} catch { }

try {
  Invoke-WatchdogLoop -Config $config
} catch {
  $ts = Get-WatchdogTimestamp
  "$ts  unhandled: $($_.Exception.Message)`n$($_.ScriptStackTrace)" | Add-Content $paths.Crash
  throw
} finally {
  Stop-Transcript -ErrorAction SilentlyContinue
}
