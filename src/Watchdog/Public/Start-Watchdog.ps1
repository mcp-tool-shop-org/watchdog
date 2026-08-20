function Start-Watchdog {
  <#
  .SYNOPSIS
    Clean-restart the VRAM watchdog. Stop-via-sentinel, wait, clear, relaunch detached, verify heartbeat.
  .DESCRIPTION
    The exact procedure from [[gpu-run-detached-launch]], encoded so it is never re-derived (and re-botched)
    from memory.

      1. request stop via the _watchdog_STOP sentinel
      2. WAIT for the old loop to actually exit (it removes its own heartbeat on a clean stop)
      3. THEN remove _watchdog_STOP + _watchdog_TRIPPED (+ _watchdog_DEAD)
      4. relaunch DETACHED via Start-Process (survives session/compaction teardown)
      5. verify the heartbeat actually appears — a launch you did not verify is not a launch

    NEVER process-match on '_watchdog' to find or kill the watchdog: this command's own command line
    contains that string and self-matches.

    ORDER IS LOAD-BEARING: the watchdog clears the STOP file at its own startup, so removing STOP before
    the old loop has noticed it leaves the old loop running — and you end up with two watchdogs.

    -AllowKill is required (or AllowKill = $true in config). This process kills guarded interpreters.
  #>
  [CmdletBinding()]
  param(
    [string]$ConfigPath,
    [switch]$AllowKill,
    [switch]$Force,
    [int]$StopWaitSec = 30
  )
  if (-not $IsWindows) {
    $err = New-WatchdogError -Code 'PLATFORM_UNSUPPORTED' -Message 'v1 is Windows-only.' -Hint 'Linux is a later version.' -Retryable $false -ExitCode 1
    Write-WatchdogError -ErrorObject $err
    $global:LASTEXITCODE = 1
    return
  }

  $cfg = Resolve-WatchdogConfig -Path $ConfigPath
  if (Test-WatchdogError $cfg) {
    Write-WatchdogError -ErrorObject $cfg
    $global:LASTEXITCODE = $cfg.exitCode
    return
  }

  if (-not $AllowKill -and -not $cfg.AllowKill) {
    $err = New-WatchdogError -Code 'CONFIG_ALLOWKILL_REQUIRED' -Message 'Start-Watchdog will kill guarded interpreters on a sustained breach. Consent is required.' -Hint 'Re-run with -AllowKill, or set AllowKill = $true in the config after you have read docs/compensators.md.' -Retryable $true -ExitCode 1
    Write-WatchdogError -ErrorObject $err
    $global:LASTEXITCODE = 1
    return
  }

  $paths = Get-WatchdogPaths -Root $cfg.Root
  if (-not (Test-Path $cfg.Root)) {
    New-Item -ItemType Directory -Path $cfg.Root -Force | Out-Null
  }

  # --- 0. refuse to start into a job we would instantly kill ---
  $vram = $null
  try {
    $raw = (& nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>&1 | Select-Object -First 1)
    if ("$raw" -match '^\s*(\d+)\s*$') { $vram = [int]$matches[1] }
  } catch { }
  if ($null -ne $vram -and $vram -ge $cfg.VramKillMiB -and -not $Force) {
    $err = New-WatchdogError -Code 'STATE_VRAM_ALREADY_OVER' -Message "VRAM is ${vram} MiB, already at/over the $($cfg.VramKillMiB) MiB ceiling." -Hint "Starting now would abort the running GPU job within ~$($cfg.IntervalSec * 3)s. Cap the consumer first, or re-run with -Force to accept the kill." -Retryable $true -ExitCode 3
    Write-WatchdogError -ErrorObject $err
    $global:LASTEXITCODE = 3
    return
  }

  # --- 1+2. stop any live watchdog, and WAIT for it ---
  $age = Get-WatchdogHeartbeatState -Path $paths.Heartbeat -StaleSec 15
  if ($age.State -eq 'RUNNING') {
    Write-Output "watchdog is alive (heartbeat $([math]::Round($age.AgeSec))s old) — requesting stop via sentinel..."
    New-Item -Path $paths.Stop -ItemType File -Force | Out-Null
    $deadline = (Get-Date).AddSeconds($StopWaitSec)
    while ((Get-Date) -lt $deadline) {
      $a = Get-WatchdogHeartbeatState -Path $paths.Heartbeat -StaleSec 15
      if ($a.State -ne 'RUNNING') { break }
      Start-Sleep -Milliseconds 500
    }
    $a = Get-WatchdogHeartbeatState -Path $paths.Heartbeat -StaleSec 15
    if ($a.State -eq 'RUNNING') {
      $err = New-WatchdogError -Code 'STATE_STOP_TIMEOUT' -Message "the running watchdog did not stop within ${StopWaitSec}s (heartbeat still fresh). Refusing to launch a second one." -Hint 'Do not process-match. Inspect _watchdog_console.log.' -Retryable $true -ExitCode 4
      Write-WatchdogError -ErrorObject $err
      $global:LASTEXITCODE = 4
      return
    }
    Write-Output "old watchdog stopped."
  } elseif ($age.State -eq 'STALE') {
    Write-Output "stale heartbeat ($((Format-WatchdogAge $age.AgeSec))) — previous watchdog died hard. Clearing."
  } else {
    Write-Output "no watchdog running."
  }

  # --- 3. NOW clear the sentinels (only after the old loop is confirmed gone) ---
  Remove-Item $paths.Stop, $paths.Trip, $paths.Dead, $paths.NoTarget -Force -ErrorAction SilentlyContinue
  Remove-Item $paths.Heartbeat -Force -ErrorAction SilentlyContinue

  # --- 4. relaunch DETACHED (top-level OS process, not a tool background job) ---
  # WindowStyle Hidden, no RedirectStandard* — those flags cannot be combined and would
  # attach the child to this session. W-03 forensics live inside the child: Start-Transcript
  # to _watchdog_console.log, unhandled exceptions to _watchdog_crash.log.
  $loop = Join-Path $script:WatchdogModuleRoot 'watchdog-loop.ps1'
  Start-Process pwsh -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $loop,
    '-ConfigPath', $cfg.ConfigPath
  )

  # --- 5. verify it actually came up ---
  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $deadline) {
    $a = Get-WatchdogHeartbeatState -Path $paths.Heartbeat -StaleSec 15
    if ($a.State -eq 'RUNNING') {
      Write-Output "watchdog UP — kill@ VRAM $($cfg.VramKillMiB) MiB / RAM $($cfg.RamKillPct)% / temp $($cfg.TempKillC)C, x$($cfg.BreachSamples) consecutive @ $($cfg.IntervalSec)s."
      Write-Output "guarding: $($cfg.Targets -join ', ')"
      $global:LASTEXITCODE = 0
      return
    }
    Start-Sleep -Milliseconds 500
  }
  $err = New-WatchdogError -Code 'RUNTIME_LAUNCH_FAILED' -Message "watchdog did NOT produce a heartbeat within 20s — launch failed." -Hint "Check $($paths.Kill), $($paths.Console), $($paths.Crash)." -Retryable $true -ExitCode 5
  Write-WatchdogError -ErrorObject $err
  $global:LASTEXITCODE = 5
}
