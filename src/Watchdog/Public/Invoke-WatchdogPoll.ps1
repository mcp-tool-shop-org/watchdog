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
  if ($hb.State -ne 'RUNNING') {
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
  }

  # Opt-in, and only after the liveness check, so it can never delay or block the poller's main job. It never
  # throws, reads memory from the Windows side (it never wakes a stopped WSL VM), and bounds every wsl.exe call.
  if ($cfg.WslCacheRelease) {
    [void](Invoke-WslCacheRelease -Cfg $cfg -Paths $paths)
  }

  $code = switch ($hb.State) { 'RUNNING' { 0 } 'NOT_RUNNING' { 1 } default { 2 } }
  # Proof that a poll ran, for Register-WatchdogPoll's first-run check (a task's exit code cannot show it: the
  # action is conhost, which exits 0 even when pwsh never starts). Never allowed to break the poll.
  try {
    $now = [DateTimeOffset]::UtcNow
    [ordered]@{ utc = $now.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture); utc_ms = $now.ToUnixTimeMilliseconds(); state = [string]$hb.State; exit = $code } |
      ConvertTo-Json -Compress | Set-Content -LiteralPath $paths.PollStamp -ErrorAction Stop
  } catch { }
  $global:LASTEXITCODE = $code
  return $hb
}
