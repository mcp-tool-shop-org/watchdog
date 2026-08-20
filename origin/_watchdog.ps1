param(
  [int]$IntervalSec   = 2,
  [int]$RamKillPct    = 90,     # system RAM %; today's spill hit ~90%+, normal training peaks ~66%
  [int]$VramKillMiB   = 31200,  # of 32607; within ~1.4 GB of ceiling = WDDM-paging spill (normal ~20 GB)
  [int]$TempKillC     = 87,     # 5090 throttles ~84-88; normal load ~74 C
  [int]$BreachSamples = 3,      # consecutive breaches before abort (hysteresis vs transient spikes)
  [string]$Root       = 'E:\AI\training',
  [string]$WslDistro  = 'Ubuntu',
  [string]$WslKillPattern = 'python.*train_budgeter'  # pkill -f regex for WSL training runs; '' disables
)
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
#   _watchdog_NO_TARGET — written when an ABORT kills nothing (no guarded PID matched, WSL skipped or no match).
#                          A breach with no killable target is the protection GAP, not the mechanism working:
#                          2026-08-04 09:12–09:17 logged 153 ABORTs with VRAM pinned at 31.9 GB, zero kills,
#                          and never named the holder. Cleared on next launch.
# Sample errors (nvidia-smi hiccups, multi-line output, driver resets) are logged to the KILL log AND as a
# state=sample_error row in the CSV; they never kill the loop.
$ErrorActionPreference = 'Continue'
$root = $Root
# widened to guard ALL AI interpreters that run GPU work on this rig
$targets = @(
  'E:\AI\training\sd-scripts\.venv\Scripts\python.exe',
  'E:\AI-Models\trellis2-env\Scripts\python.exe',
  'E:\AI-Models\ComfyUI_windows_portable\python_embeded\python.exe',
  # added 2026-08-01 — ai-toolkit runs were UNGUARDED: the watchdog would log a breach and kill
  # nothing, so every LoRA train since ai-toolkit landed could spill/overheat past the ceiling
  # with no hard abort. Verified real CUDA interpreter (py 3.11.15 / torch 2.9.1+cu128).
  'E:\AI\ai-toolkit\venv\Scripts\python.exe'
)
$venvPy = ($targets -join ' ; ')
$csv="$root\_watchdog_log.csv"; $kill="$root\_watchdog_KILL.log"; $trip="$root\_watchdog_TRIPPED"
$stop="$root\_watchdog_STOP"; $hb="$root\_watchdog_HEARTBEAT"; $dead="$root\_watchdog_DEAD"
$noTarget="$root\_watchdog_NO_TARGET"
$totalRamMB = [int]((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize/1024)
Remove-Item $stop,$trip,$dead,$hb,$noTarget -EA SilentlyContinue
"timestamp,gpu_temp_c,gpu_power_w,vram_mib,ram_pct,ram_gb,sd_python_pids,state" | Set-Content $csv
"$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  watchdog up: interval ${IntervalSec}s | kill@ RAM ${RamKillPct}% / VRAM ${VramKillMiB}MiB / temp ${TempKillC}C / x${BreachSamples} | venv=$venvPy | wsl=$WslDistro pkill -f '$WslKillPattern'" | Add-Content $kill

# nvidia-smi can emit warning/info lines, multiple lines, or stringify as Object[] during driver hiccups —
# .Split() on that killed the loop (2026-06-12 03:29:53). Filter to lines shaped like 'temp,power,vram',
# take the first; anything else throws into the per-sample catch instead of dying.
function Parse-GpuSample([object[]]$raw) {
  $lines = @($raw) | ForEach-Object { "$_" -replace '\s','' } | Where-Object { $_ -match '^\d+,[^,]*,\d+$' }
  if (-not $lines) { throw "nvidia-smi gave no parseable GPU line: '$((@($raw) | ForEach-Object { "$_" }) -join ' || ')'" }
  $f = @($lines)[0] -split ','
  [pscustomobject]@{ Temp = [int]$f[0]; Power = $f[1]; Vram = [int]$f[2] }
}

function Test-WslRunning([string]$distro) {
  try {
    $names = @(& wsl -l --running -q 2>$null) | ForEach-Object { ("$_" -replace "`0",'').Trim() } | Where-Object { $_ }
    return ($names -contains $distro)
  } catch { return $false }
}

# Per-process VRAM so a breach names its holder — the 2026-08-04 burst logged 153 ABORTs without one.
# nvidia-smi's per-process used_gpu_memory reads [N/A] under WDDM (measured on this rig 2026-08-04, all
# rows), so the source is the '\GPU Process Memory' counter set (~1.3s per call; breach path only, never
# the normal loop). Best-effort: any failure degrades to a note and must never kill the loop.
function Get-VramHolders {
  try {
    $byPid = @{}
    foreach ($s in (Get-Counter '\GPU Process Memory(*)\Dedicated Usage' -EA Stop).CounterSamples) {
      if ($s.InstanceName -match '^pid_(\d+)_' -and $s.CookedValue -gt 0) { $byPid[[int]$matches[1]] += [long]$s.CookedValue }
    }
    $top = foreach ($e in ($byPid.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8)) {
      $n = (Get-Process -Id $e.Key -EA SilentlyContinue).ProcessName
      '{0}(pid {1})={2}MiB' -f $(if ($n) { $n } else { '?' }), $e.Key, [math]::Round($e.Value/1MB)
    }
    if ($top) { "holders: $($top -join ' | ')" } else { 'holders: none reported >0' }
  } catch { "holders unavailable: $(($_.Exception.Message -split "`r?`n")[0])" }
}

$breach = 0
$exitReason = $null
try {
  while (-not (Test-Path $stop)) {
    (Get-Date).ToString('o') | Set-Content $hb
    try {
      $g = Parse-GpuSample (& nvidia-smi --query-gpu=temperature.gpu,power.draw,memory.used --format=csv,noheader,nounits 2>&1)
      $temp=$g.Temp; $pwr=$g.Power; $vram=$g.Vram
      $os=Get-CimInstance Win32_OperatingSystem
      $ramUsedMB=$totalRamMB-[int]($os.FreePhysicalMemory/1024); $ramPct=[int](100*$ramUsedMB/$totalRamMB)
      $pids=@(Get-Process python -EA SilentlyContinue | Where-Object { $targets -contains $_.Path } | Select-Object -Expand Id)
      $reasons=@()
      if ($ramPct -ge $RamKillPct) { $reasons += "RAM ${ramPct}%>=${RamKillPct}%" }
      if ($vram   -ge $VramKillMiB){ $reasons += "VRAM ${vram}MiB>=${VramKillMiB}" }
      if ($temp   -ge $TempKillC)  { $reasons += "TEMP ${temp}C>=${TempKillC}C" }
      $state='ok'
      if ($reasons.Count -gt 0) {
        $breach++; $state = if ($breach -ge $BreachSamples) {'KILL'} else {"WARN($breach/$BreachSamples)"}
        $ts=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        # every breach sample names who holds the VRAM, so a burst can be attributed after the fact
        "$ts  $state $($reasons -join '; ') — $(Get-VramHolders)" | Add-Content $kill
        if ($breach -ge $BreachSamples) {
          $acts=@(); $killedAny=$false
          if ($pids.Count -gt 0) {
            foreach ($pp in $pids) { Stop-Process -Id $pp -Force -EA SilentlyContinue }
            $acts += "killed win python PID(s): $($pids -join ',')"; $killedAny=$true
          }
          if ($WslKillPattern -and (Test-WslRunning $WslDistro)) {
            # only if the distro is already up — a cold VM start would allocate RAM mid-emergency
            $null = & wsl -d $WslDistro -- pkill -9 -f $WslKillPattern 2>&1
            $wslExit = $LASTEXITCODE
            $acts += "wsl[$WslDistro] pkill -9 -f '$WslKillPattern' exit=$wslExit (0=killed,1=no match)"
            if ($wslExit -eq 0) { $killedAny=$true }
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
          $breach=0
        }
      } else { $breach=0 }
      "$((Get-Date).ToString('HH:mm:ss')),$temp,$pwr,$vram,$ramPct,$([math]::Round($ramUsedMB/1024,1)),$($pids -join '|'),$state" | Add-Content $csv
    } catch {
      $msg = ($_.Exception.Message -split "`r?`n")[0]
      "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  watchdog sample error: $msg" | Add-Content $kill
      "$((Get-Date).ToString('HH:mm:ss')),,,,,,,sample_error" | Add-Content $csv
    }
    Start-Sleep -Seconds $IntervalSec
  }
  $exitReason = 'stop-file'
} catch {
  $exitReason = "loop died: $(($_.Exception.Message -split "`r?`n")[0])"
} finally {
  $ts=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  if ($exitReason -eq 'stop-file') {
    "$ts  watchdog stopped (clean, STOP file)" | Add-Content $kill
    Remove-Item $hb -EA SilentlyContinue
  } else {
    $why = if ($exitReason) { $exitReason } else { 'loop exited without STOP file (Ctrl+C or terminating error)' }
    "$ts  $why" | Set-Content $dead
    "$ts  watchdog DEAD — $why" | Add-Content $kill
  }
}
