param(
  [int]$VramKillMiB = 31200,   # CONSERVATIVE + CORRECT. Do NOT raise this to 32000 to stop ComfyUI trips —
                               # cap ComfyUI instead via _comfyui_start.ps1 (--reserve-vram). See note below.
  [int]$IntervalSec = 2,
  [int]$StopWaitSec = 30,      # how long to wait for a running watchdog to honour the STOP sentinel
  [switch]$Force,              # start even if VRAM is already at/near the ceiling (WILL kill the live GPU job)
  [string]$Root = 'E:\AI\training'
)
# CLEAN-RESTART THE VRAM WATCHDOG — the exact procedure from [[gpu-run-detached-launch]], encoded so it is
# never re-derived (and re-botched) from memory.
#
#   1. request stop via the _watchdog_STOP sentinel
#   2. WAIT for the old loop to actually exit (it removes its own heartbeat on a clean stop)
#   3. THEN remove _watchdog_STOP + _watchdog_TRIPPED (+ _watchdog_DEAD)
#   4. relaunch DETACHED via Start-Process (survives session/compaction teardown)
#   5. verify the heartbeat actually appears — a launch you did not verify is not a launch
#
# ⚠ NEVER process-match on '_watchdog' to find or kill the watchdog: this script's own command line
#   contains that string and self-matches, which is how that approach makes a mess. Liveness is the
#   HEARTBEAT, and stopping is the SENTINEL. Both are content checks, not process checks.
#
# ⚠ ORDER IS LOAD-BEARING: the watchdog clears the STOP file at its own startup, so removing STOP before
#   the old loop has noticed it leaves the old loop running — and you end up with two watchdogs.
#
# ⚠ ON THE CEILING: 31200 of 32607 MiB is the training-correct bound (~1.4 GB headroom = WDDM spill).
#   ComfyUI Qwen-Image inference legitimately peaks ~31.2-31.3 GB and WILL trip it. The fix is to cap
#   ComfyUI (--reserve-vram 4.0), NOT to weaken this bound to 32000. -VramKillMiB 32000 is a FALLBACK
#   for when you genuinely cannot relaunch ComfyUI. Training always stays at 31200.

$ErrorActionPreference = 'Stop'
$hb   = "$Root\_watchdog_HEARTBEAT"
$stop = "$Root\_watchdog_STOP"
$trip = "$Root\_watchdog_TRIPPED"
$dead = "$Root\_watchdog_DEAD"
$noTarget = "$Root\_watchdog_NO_TARGET"   # ABORT fired but nothing on the kill list matched (2026-08-04 gap)
$wd   = "$Root\_watchdog.ps1"

function HbAge {
  if (-not (Test-Path $hb)) { return $null }
  try { return ((Get-Date) - [datetime]::Parse((Get-Content $hb -Raw).Trim())).TotalSeconds } catch { return 1e9 }
}

# --- 0. refuse to start into a job we would instantly kill ---
$vram = $null
try {
  $raw = (& nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>&1 | Select-Object -First 1)
  if ("$raw" -match '^\s*(\d+)\s*$') { $vram = [int]$matches[1] }
} catch { }
if ($vram -ne $null -and $vram -ge $VramKillMiB -and -not $Force) {
  Write-Warning "VRAM is ${vram} MiB, already at/over the ${VramKillMiB} MiB ceiling."
  Write-Warning "Starting now would abort the running GPU job within ~$($IntervalSec * 3)s."
  Write-Warning "Cap the consumer first (ComfyUI: $Root\_comfyui_start.ps1), or re-run with -Force to accept the kill."
  exit 3
}

# --- 1+2. stop any live watchdog, and WAIT for it ---
$age = HbAge
if ($age -ne $null -and $age -le 15) {
  Write-Output "watchdog is alive (heartbeat $([math]::Round($age))s old) — requesting stop via sentinel..."
  New-Item -Path $stop -ItemType File -Force | Out-Null
  $deadline = (Get-Date).AddSeconds($StopWaitSec)
  while ((Get-Date) -lt $deadline) {
    $a = HbAge
    if ($a -eq $null -or $a -gt 15) { break }   # clean exit removes the heartbeat; a hang goes stale
    Start-Sleep -Milliseconds 500
  }
  $a = HbAge
  if ($a -ne $null -and $a -le 15) {
    Write-Error "the running watchdog did not stop within ${StopWaitSec}s (heartbeat still fresh). Refusing to launch a second one."
    exit 4
  }
  Write-Output "old watchdog stopped."
} elseif ($age -ne $null) {
  Write-Output "stale heartbeat ($([math]::Round($age/86400,1))d old) — previous watchdog died hard. Clearing."
} else {
  Write-Output "no watchdog running."
}

# --- 3. NOW clear the sentinels (only after the old loop is confirmed gone) ---
Remove-Item $stop, $trip, $dead, $noTarget -Force -ErrorAction SilentlyContinue
Remove-Item $hb -Force -ErrorAction SilentlyContinue

# --- 4. relaunch DETACHED (top-level OS process, not a tool background job) ---
Start-Process pwsh -WindowStyle Hidden -ArgumentList @(
  '-NoProfile','-ExecutionPolicy','Bypass','-File', $wd,
  '-VramKillMiB', $VramKillMiB, '-IntervalSec', $IntervalSec
)

# --- 5. verify it actually came up ---
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
  $a = HbAge
  if ($a -ne $null -and $a -le 15) {
    Write-Output "watchdog UP — kill@ VRAM ${VramKillMiB} MiB / RAM 90% / temp 87C, x3 consecutive @ ${IntervalSec}s."
    Write-Output "guarding: sd-scripts, trellis2-env, ComfyUI embedded, ai-toolkit"
    exit 0
  }
  Start-Sleep -Milliseconds 500
}
Write-Error "watchdog did NOT produce a heartbeat within 20s — launch failed. Check $Root\_watchdog_KILL.log"
exit 5
