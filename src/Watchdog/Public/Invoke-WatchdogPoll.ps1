function Invoke-WatchdogPoll {
  <#
  .SYNOPSIS
    One-shot liveness poll. Writes _watchdog_DEAD from the outside when the heartbeat is stale.
  .DESCRIPTION
    The loop cannot write DEAD after a hard kill (2026-08-20, 2026-06-24). This is the process
    that can. It DETECTS. It does not restart — auto-restart can abort a live GPU job.
  #>
  [CmdletBinding()]
  param(
    [string]$ConfigPath
  )
  $cfg = Resolve-WatchdogConfig -Path $ConfigPath
  if (Test-WatchdogError $cfg) {
    Write-WatchdogError -ErrorObject $cfg
    $global:LASTEXITCODE = $cfg.exitCode
    return $cfg
  }

  $paths = Get-WatchdogPaths -Root $cfg.Root
  $hb = Get-WatchdogHeartbeatState -Path $paths.Heartbeat -StaleSec $cfg.StaleSec
  if ($hb.State -eq 'RUNNING') {
    $global:LASTEXITCODE = 0
    return $hb
  }

  $tail = ''
  if (Test-Path $paths.Console) {
    $tail = ((Get-Content $paths.Console -Tail 20 -ErrorAction SilentlyContinue) -join ' | ')
  }
  if (Test-Path $paths.Crash) {
    $crashTail = ((Get-Content $paths.Crash -Tail 10 -ErrorAction SilentlyContinue) -join ' | ')
    $tail = "crash: $crashTail ; console: $tail"
  }
  $ageTxt = if ($null -eq $hb.AgeSec) { 'none' } else { Format-WatchdogAge $hb.AgeSec }
  $ts = Get-WatchdogTimestamp
  $why = "$ts  poller declared $($hb.State) — heartbeat age=$ageTxt — last=$($hb.Last) — $tail"

  if (-not (Test-Path $paths.Dead)) {
    Set-Content -Path $paths.Dead -Value $why
  }
  if (Test-Path $paths.Kill) {
    Add-Content -Path $paths.Kill -Value $why
  } else {
    Set-Content -Path $paths.Kill -Value $why
  }

  $code = switch ($hb.State) { 'NOT_RUNNING' { 1 } default { 2 } }
  $global:LASTEXITCODE = $code
  return $hb
}
