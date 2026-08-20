# OVERWATCH WATCHDOG — mimics the WSL2 guardian: it ACTS, not just logs. Samples system RAM / VRAM / GPU temp and,
# if any HARD ceiling is breached for $BreachSamples consecutive samples, KILLS the guarded AI interpreters (and only
# those — never other python) plus any matching WSL training process, to ABORT the run before it pages the host or
# overheats. Logs every sample to _watchdog_log.csv; writes _watchdog_KILL.log + the _watchdog_TRIPPED sentinel on an
# abort. Stop cleanly: create _watchdog_STOP. Thresholds sit far above normal operation (RAM ~66%, VRAM ~20 GB, 74 C)
# so normal runs never trip it.
#
# Liveness contract:
#   _watchdog_HEARTBEAT — rewritten every sample; age > ~3x interval means the loop is dead or the process was
#                          hard-killed. THIS is how you tell a frozen CSV from a healthy idle.
#   _watchdog_DEAD      — written if the loop exits any way other than the STOP file (terminating error, Ctrl+C).
#                          Cleared on next launch. A hard process kill can't write it — heartbeat age covers that.
#                          The external poller (Invoke-WatchdogPoll) writes this when the heartbeat goes stale, which
#                          is the 2026-08-20 hole: a hard death left nothing and nobody asked.
#   _watchdog_NO_TARGET — written when an ABORT kills nothing (no guarded PID matched, WSL skipped or no match).
#                          A breach with no killable target is the protection GAP, not the mechanism working:
#                          2026-08-04 09:12–09:17 logged 153 ABORTs with VRAM pinned at 31.9 GB, zero kills,
#                          and never named the holder. Cleared on next launch.
# Sample errors (nvidia-smi hiccups, multi-line output, driver resets) are logged to the KILL log AND as a
# state=sample_error row in the CSV; they never kill the loop.
function Invoke-WatchdogLoop {
  param(
    [Parameter(Mandatory)]$Config
  )
  $ErrorActionPreference = 'Continue'
  $root = $Config.Root
  $targets = @($Config.Targets)
  $IntervalSec = [int]$Config.IntervalSec
  $RamKillPct = [int]$Config.RamKillPct
  $VramKillMiB = [int]$Config.VramKillMiB
  $TempKillC = [int]$Config.TempKillC
  $BreachSamples = [int]$Config.BreachSamples
  $WslDistro = [string]$Config.WslDistro
  $WslKillPattern = [string]$Config.WslKillPattern

  $paths = Get-WatchdogPaths -Root $root
  if (-not (Test-Path $root)) {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
  }

  $venvPy = ($targets -join ' ; ')
  $csv = $paths.Csv
  $kill = $paths.Kill
  $trip = $paths.Trip
  $stop = $paths.Stop
  $hb = $paths.Heartbeat
  $dead = $paths.Dead
  $noTarget = $paths.NoTarget

  $totalRamMB = [int]((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1024)
  Remove-Item $stop, $trip, $dead, $hb, $noTarget -EA SilentlyContinue

  $tsUp = Get-WatchdogTimestamp
  $null = Initialize-WatchdogCsv -Path $csv -Timestamp $tsUp
  "$tsUp  watchdog up: interval ${IntervalSec}s | kill@ RAM ${RamKillPct}% / VRAM ${VramKillMiB}MiB / temp ${TempKillC}C / x${BreachSamples} | venv=$venvPy | wsl=$WslDistro pkill -f '$WslKillPattern'" | Add-Content $kill

  $breach = 0
  $exitReason = $null
  try {
    while (-not (Test-Path $stop)) {
      Get-WatchdogTimestamp | Set-Content $hb
      try {
        $g = Parse-GpuSample (& nvidia-smi --query-gpu=temperature.gpu,power.draw,memory.used --format=csv,noheader,nounits 2>&1)
        $temp = $g.Temp; $pwr = $g.Power; $vram = $g.Vram
        $os = Get-CimInstance Win32_OperatingSystem
        $ramUsedMB = $totalRamMB - [int]($os.FreePhysicalMemory / 1024); $ramPct = [int](100 * $ramUsedMB / $totalRamMB)
        $pids = @(Get-Process python -EA SilentlyContinue | Where-Object { $targets -contains $_.Path } | Select-Object -Expand Id)
        $reasons = @()
        if ($ramPct -ge $RamKillPct) { $reasons += "RAM ${ramPct}%>=${RamKillPct}%" }
        if ($vram -ge $VramKillMiB) { $reasons += "VRAM ${vram}MiB>=${VramKillMiB}" }
        if ($temp -ge $TempKillC) { $reasons += "TEMP ${temp}C>=${TempKillC}C" }
        $step = Update-WatchdogBreach -Count $breach -Reasons $reasons -BreachSamples $BreachSamples
        $breach = $step.Count
        $state = $step.State
        if ($reasons.Count -gt 0) {
          $ts = Get-WatchdogTimestamp
          # every breach sample names who holds the VRAM, so a burst can be attributed after the fact
          "$ts  $state $($reasons -join '; ') — $(Get-VramHolders)" | Add-Content $kill
          if ($step.ShouldAbort) {
            $acts = @(); $killedAny = $false
            if ($pids.Count -gt 0) {
              foreach ($pp in $pids) { Stop-Process -Id $pp -Force -EA SilentlyContinue }
              $acts += "killed win python PID(s): $($pids -join ',')"; $killedAny = $true
            }
            if ($WslKillPattern -and (Test-WslRunning $WslDistro)) {
              # only if the distro is already up — a cold VM start would allocate RAM mid-emergency
              $null = & wsl -d $WslDistro -- pkill -9 -f $WslKillPattern 2>&1
              $wslExit = $LASTEXITCODE
              $acts += "wsl[$WslDistro] pkill -9 -f '$WslKillPattern' exit=$wslExit (0=killed,1=no match)"
              if ($wslExit -eq 0) { $killedAny = $true }
            } elseif ($WslKillPattern) {
              $acts += "wsl[$WslDistro] not running, skipped"
            }
            if ($acts.Count -eq 0) { $acts += 'no targets found' }
            if ($killedAny) {
              "$ts  ABORT — $($reasons -join '; ') — $($acts -join ' | ')" | Add-Content $kill
            } else {
              # zero kills must not read as the mechanism working — say so, and leave a distinct sentinel
              "$ts  ABORT — BREACH WITH NO KILLABLE TARGET — $($reasons -join '; ') — $($acts -join ' | ')" | Add-Content $kill
              "$ts $($reasons -join '; ') — no killable target — $($acts -join ' | ')" | Set-Content $noTarget
            }
            "$ts $($reasons -join '; ') $($acts -join ' | ')" | Set-Content $trip
            $breach = 0
          }
        }
        "$(Get-WatchdogTimestamp),$temp,$pwr,$vram,$ramPct,$([math]::Round($ramUsedMB/1024,1)),$($pids -join '|'),$state" | Add-Content $csv
      } catch {
        $msg = ($_.Exception.Message -split "`r?`n")[0]
        "$(Get-WatchdogTimestamp)  watchdog sample error: $msg" | Add-Content $kill
        "$(Get-WatchdogTimestamp),,,,,,,sample_error" | Add-Content $csv
      }
      Start-Sleep -Seconds $IntervalSec
    }
    $exitReason = 'stop-file'
  } catch {
    $exitReason = "loop died: $(($_.Exception.Message -split "`r?`n")[0])"
  } finally {
    $ts = Get-WatchdogTimestamp
    if ($exitReason -eq 'stop-file') {
      "$ts  watchdog stopped (clean, STOP file)" | Add-Content $kill
      Remove-Item $hb -EA SilentlyContinue
    } else {
      $why = if ($exitReason) { $exitReason } else { 'loop exited without STOP file (Ctrl+C or terminating error)' }
      "$ts  $why" | Set-Content $dead
      "$ts  watchdog DEAD — $why" | Add-Content $kill
    }
  }
}
