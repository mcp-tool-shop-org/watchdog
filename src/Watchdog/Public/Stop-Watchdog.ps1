function Stop-Watchdog {
  <#
  .SYNOPSIS
    Request a clean stop via the STOP sentinel. Never process-matches on '_watchdog'.
  #>
  [CmdletBinding()]
  param(
    [string]$ConfigPath,
    [int]$StopWaitSec = 30
  )
  $cfg = Resolve-WatchdogConfig -Path $ConfigPath
  if (Test-WatchdogError $cfg) {
    Write-WatchdogError -ErrorObject $cfg
    $global:LASTEXITCODE = $cfg.exitCode
    return
  }
  $paths = Get-WatchdogPaths -Root $cfg.Root
  $hb = Get-WatchdogHeartbeatState -Path $paths.Heartbeat -StaleSec 15
  if ($hb.State -ne 'RUNNING') {
    Write-Output "no live watchdog to stop (state=$($hb.State))."
    $global:LASTEXITCODE = 0
    return
  }
  Write-Output "watchdog is alive (heartbeat $([math]::Round($hb.AgeSec))s old) — requesting stop via sentinel..."
  New-Item -Path $paths.Stop -ItemType File -Force | Out-Null
  $deadline = (Get-Date).AddSeconds($StopWaitSec)
  while ((Get-Date) -lt $deadline) {
    $a = Get-WatchdogHeartbeatState -Path $paths.Heartbeat -StaleSec 15
    if ($a.State -ne 'RUNNING') { break }
    Start-Sleep -Milliseconds 500
  }
  $a = Get-WatchdogHeartbeatState -Path $paths.Heartbeat -StaleSec 15
  if ($a.State -eq 'RUNNING') {
    $err = New-WatchdogError -Code 'STATE_STOP_TIMEOUT' -Message "the running watchdog did not stop within ${StopWaitSec}s (heartbeat still fresh)." -Hint 'Refusing to lie about a stop. Do not launch a second loop. Inspect _watchdog_console.log.' -Retryable $true -ExitCode 4
    Write-WatchdogError -ErrorObject $err
    $global:LASTEXITCODE = 4
    return
  }
  Write-Output "old watchdog stopped."
  $global:LASTEXITCODE = 0
}
