# Discoverable dispatcher. After install: watchdog status
# Do not hand-roll a heartbeat-age check. This is the right one.
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Command = 'help',
  [string]$ConfigPath,
  [switch]$AllowKill,
  [switch]$Force,
  [switch]$Hook,
  [switch]$Brief,
  [switch]$Poll,
  [switch]$Help,
  [switch]$Version
)

$moduleManifest = Join-Path $PSScriptRoot 'Watchdog.psd1'
Import-Module $moduleManifest -Force

if ($Help -or $Command -in @('help', '-h', '--help', '/?')) {
  @"
watchdog $((Import-PowerShellDataFile $moduleManifest).ModuleVersion) — VRAM/RAM/temp watchdog for NVIDIA GPUs (Windows)

Usage:
  watchdog status   [-ConfigPath <path>] [-Brief] [-Hook]
  watchdog start    [-ConfigPath <path>] -AllowKill [-Force]
  watchdog stop     [-ConfigPath <path>]
  watchdog poll     [-ConfigPath <path>]
  watchdog install  [-ConfigPath <path>] [-Poll]
  watchdog uninstall
  watchdog help
  watchdog version

Exit codes (status / poll):
  0 running   1 no heartbeat   2 stale (died hard)

Exit codes (start):
  0 up   1 usage/config   3 VRAM already over ceiling   4 old loop did not stop   5 launch failed

Config search: -ConfigPath, `$env:WATCHDOG_CONFIG, ./watchdog.config.psd1, ~/.watchdog/config.psd1
There is no default Root or kill list. Copy config/watchdog.example.psd1 and edit it.

Do not process-match on '_watchdog'. Heartbeat age is the liveness signal.
"@ | Write-Output
  exit 0
}

if ($Version -or $Command -eq 'version') {
  Write-Output (Import-PowerShellDataFile $moduleManifest).ModuleVersion
  exit 0
}

switch -Regex ($Command) {
  '^(status|st)$' {
    Get-WatchdogStatus -ConfigPath $ConfigPath -Brief:$Brief -Hook:$Hook
  }
  '^(start)$' {
    Start-Watchdog -ConfigPath $ConfigPath -AllowKill:$AllowKill -Force:$Force
  }
  '^(stop)$' {
    Stop-Watchdog -ConfigPath $ConfigPath
  }
  '^(poll)$' {
    Invoke-WatchdogPoll -ConfigPath $ConfigPath
  }
  '^(install)$' {
    Install-Watchdog -ConfigPath $ConfigPath -Poll:$Poll
    exit 0
  }
  '^(uninstall)$' {
    Uninstall-Watchdog
    exit 0
  }
  default {
    $err = New-WatchdogError -Code 'INPUT_UNKNOWN_COMMAND' -Message "Unknown command '$Command'." -Hint 'watchdog help' -Retryable $true -ExitCode 1
    Write-WatchdogError -ErrorObject $err
    exit 1
  }
}

if ($null -eq $LASTEXITCODE) { exit 0 }
exit $LASTEXITCODE
