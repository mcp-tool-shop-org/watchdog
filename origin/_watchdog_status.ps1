param(
  [int]$StaleSec = 15,          # heartbeat older than this = the loop is not alive (interval is 2s; doc says ~3x)
  [int]$VramKillMiB = 31200,    # for headroom reporting only — must match the ceiling the watchdog runs with
  [switch]$Brief,               # one line when healthy, full detail when not
  [switch]$Hook,                # emit Claude Code hook JSON instead of text; ALWAYS exits 0
  [string]$Root = 'E:\AI\training'
)
# WATCHDOG LIVENESS CHECK — answers "is the VRAM watchdog actually alive right now?"
#
# WHY THIS EXISTS: on 2026-06-24 the watchdog tripped (killed ComfyUI on a VRAM breach), kept running,
# then was hard-killed ~10h later. A hard kill cannot write _watchdog_DEAD, and nothing else surfaced the
# absence — so the rig ran with NO VRAM protection for 5+ weeks across multiple training and generation
# sessions. A dead watchdog and a healthy one look identical unless you ask. This asks.
#
# THE ONLY RELIABLE SIGNAL IS HEARTBEAT AGE. Do NOT process-match on '_watchdog' to answer this — the
# checking command's own command line contains that string and self-matches (documented trap,
# [[gpu-run-detached-launch]]). A frozen CSV also can't distinguish "dead" from "healthy but idle".
#
# EXIT CODES:  0 = RUNNING   1 = NOT RUNNING (no heartbeat)   2 = STALE (heartbeat exists but old = died hard)

$hb   = "$Root\_watchdog_HEARTBEAT"
$dead = "$Root\_watchdog_DEAD"
$trip = "$Root\_watchdog_TRIPPED"
$stop = "$Root\_watchdog_STOP"

# --- verdict from heartbeat age ---
$state = $null; $ageSec = $null; $last = $null
if (Test-Path $hb) {
  try {
    $last = [datetime]::Parse((Get-Content $hb -Raw).Trim())
    $ageSec = ((Get-Date) - $last).TotalSeconds
    $state = if ($ageSec -le $StaleSec) { 'RUNNING' } else { 'STALE' }
  } catch { $state = 'STALE'; $ageSec = [double]::NaN }
} else {
  $state = 'NOT_RUNNING'
}

function Age-Str([double]$s) {
  if ([double]::IsNaN($s)) { return 'unreadable' }
  if ($s -lt 90)    { return "$([math]::Round($s))s" }
  if ($s -lt 5400)  { return "$([math]::Round($s/60,1))m" }
  if ($s -lt 172800){ return "$([math]::Round($s/3600,1))h" }
  return "$([math]::Round($s/86400,1))d"
}

# --- current GPU pressure (context for the verdict) ---
$vramTxt = 'gpu unreadable'
$vramUsed = $null
try {
  $raw = (& nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>&1 | Select-Object -First 1)
  if ("$raw" -match '^\s*(\d+)\s*,\s*(\d+)\s*$') {
    $vramUsed = [int]$matches[1]; $vramTot = [int]$matches[2]
    $head = $VramKillMiB - $vramUsed
    $vramTxt = "VRAM ${vramUsed}/${vramTot} MiB, {0} MiB {1} the ${VramKillMiB} ceiling" -f [math]::Abs($head), $(if ($head -ge 0) { 'below' } else { 'ABOVE' })
  }
} catch { }

$verdict = switch ($state) {
  'RUNNING'     { "OK — watchdog alive (heartbeat $(Age-Str $ageSec) old). $vramTxt" }
  'STALE'       { "*** WATCHDOG DEAD *** heartbeat is $(Age-Str $ageSec) old (last $($last)). The GPU is UNPROTECTED. $vramTxt" }
  'NOT_RUNNING' { "*** WATCHDOG NOT RUNNING *** no heartbeat file. The GPU is UNPROTECTED. $vramTxt" }
}
$code = switch ($state) { 'RUNNING' { 0 } 'NOT_RUNNING' { 1 } 'STALE' { 2 } }

$detail = @()
if ($code -ne 0) {
  $detail += "restart with:  pwsh -NoProfile -File $Root\_watchdog_start.ps1"
  if ($null -ne $vramUsed -and $vramUsed -ge ($VramKillMiB - 400)) {
    $detail += "!! VRAM is at/near the ceiling NOW. Starting the watchdog will kill the current GPU job within seconds."
    $detail += "   If that is ComfyUI, relaunch it capped first:  $Root\_comfyui_start.ps1"
  }
}
if (Test-Path $dead) { $detail += "_watchdog_DEAD: $((Get-Content $dead -Raw).Trim())" }
if (Test-Path $stop) { $detail += "_watchdog_STOP present — a stop was requested; the watchdog will not run until it is removed." }
if (Test-Path $trip) { $detail += "last TRIP: $((Get-Content $trip -Raw).Trim())" }

if ($Hook) {
  # SessionStart hook mode. Quiet when healthy, loud when not. ALWAYS exit 0 — a watchdog check
  # must never be able to break session start.
  if ($code -eq 0) {
    $out = @{
      suppressOutput = $true
      hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = "VRAM watchdog: alive. $vramTxt" }
    }
  } else {
    $ctx = @("VRAM WATCHDOG IS NOT PROTECTING THIS RIG. $verdict") + $detail + @(
      "Tell the user before any GPU work (training, ComfyUI generation, TRELLIS) starts this session."
    )
    $out = @{
      systemMessage = "⚠ VRAM watchdog is NOT running — the GPU is unprotected. See E:\AI\training\_watchdog_start.ps1"
      hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = ($ctx -join "`n") }
    }
  }
  $out | ConvertTo-Json -Depth 5 -Compress
  exit 0
}

Write-Output "WATCHDOG $verdict"
if (-not ($Brief -and $code -eq 0)) { $detail | ForEach-Object { Write-Output "  $_" } }
exit $code
