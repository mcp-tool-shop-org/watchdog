function Get-WatchdogStatus {
  <#
  .SYNOPSIS
    The only correct liveness check. Exit 0 running, 1 no heartbeat, 2 stale (died hard).
  .DESCRIPTION
    WHY THIS EXISTS: on 2026-06-24 the watchdog tripped (killed ComfyUI on a VRAM breach), kept running,
    then was hard-killed ~10h later. A hard kill cannot write _watchdog_DEAD, and nothing else surfaced the
    absence — so the rig ran with NO VRAM protection for 5+ weeks. A dead watchdog and a healthy one look
    identical unless you ask. This asks.

    THE ONLY RELIABLE SIGNAL IS HEARTBEAT AGE. Do NOT process-match on '_watchdog' to answer this — the
    checking command's own command line contains that string and self-matches.
  .PARAMETER ConfigPath
    Config file. Required for Root / StaleSec / VramKillMiB.
  .PARAMETER Brief
    One line when healthy, full detail when not.
  .PARAMETER Hook
    Emit Claude Code SessionStart JSON instead of text; ALWAYS exits 0.
  #>
  [CmdletBinding()]
  param(
    [string]$ConfigPath,
    [switch]$Brief,
    [switch]$Hook
  )
  $cfg = Resolve-WatchdogConfig -Path $ConfigPath
  if (Test-WatchdogError $cfg) {
    if ($Hook) {
      $out = @{
        systemMessage = "VRAM watchdog config is missing or invalid — the GPU may be unprotected. $($cfg.message)"
        hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = "$($cfg.code): $($cfg.message). $($cfg.hint)" }
      }
      $out | ConvertTo-Json -Depth 5 -Compress
      $global:LASTEXITCODE = 0
      return
    }
    Write-WatchdogError -ErrorObject $cfg
    $global:LASTEXITCODE = $cfg.exitCode
    return $cfg
  }

  $paths = Get-WatchdogPaths -Root $cfg.Root
  $hb = Get-WatchdogHeartbeatState -Path $paths.Heartbeat -StaleSec $cfg.StaleSec
  $state = $hb.State
  $ageSec = $hb.AgeSec
  $last = $hb.Last

  $vramTxt = 'gpu unreadable'
  $vramUsed = $null
  try {
    $raw = (& nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>&1 | Select-Object -First 1)
    if ("$raw" -match '^\s*(\d+)\s*,\s*(\d+)\s*$') {
      $vramUsed = [int]$matches[1]; $vramTot = [int]$matches[2]
      $head = $cfg.VramKillMiB - $vramUsed
      $vramTxt = "VRAM ${vramUsed}/${vramTot} MiB, {0} MiB {1} the $($cfg.VramKillMiB) ceiling" -f [math]::Abs($head), $(if ($head -ge 0) { 'below' } else { 'ABOVE' })
    }
  } catch { }

  $verdict = switch ($state) {
    'RUNNING'     { "OK — watchdog alive (heartbeat $(Format-WatchdogAge $ageSec) old). $vramTxt" }
    'STALE'       { "*** WATCHDOG DEAD *** heartbeat is $(Format-WatchdogAge $ageSec) old (last $($last)). The GPU is UNPROTECTED. $vramTxt" }
    'NOT_RUNNING' { "*** WATCHDOG NOT RUNNING *** no heartbeat file. The GPU is UNPROTECTED. $vramTxt" }
  }
  $code = switch ($state) { 'RUNNING' { 0 } 'NOT_RUNNING' { 1 } 'STALE' { 2 } }

  $detail = @()
  if ($code -ne 0) {
    $detail += "restart with:  watchdog start -AllowKill -ConfigPath $($cfg.ConfigPath)"
    if ($null -ne $vramUsed -and $vramUsed -ge ($cfg.VramKillMiB - 400)) {
      $detail += "!! VRAM is at/near the ceiling NOW. Starting the watchdog will kill the current GPU job within seconds."
      $detail += "   Cap the consumer first (ComfyUI: --reserve-vram), then start."
    }
  }
  if (Test-Path $paths.Dead) { $detail += "_watchdog_DEAD: $((Get-Content $paths.Dead -Raw).Trim())" }
  if (Test-Path $paths.Stop) { $detail += "_watchdog_STOP present — a stop was requested; the watchdog will not run until it is removed." }
  if (Test-Path $paths.Trip) { $detail += "last TRIP: $((Get-Content $paths.Trip -Raw).Trim())" }
  if (Test-Path $paths.NoTarget) { $detail += "_watchdog_NO_TARGET: $((Get-Content $paths.NoTarget -Raw).Trim())  (protection GAP, not success)" }

  if ($Hook) {
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
        systemMessage = "⚠ VRAM watchdog is NOT running — the GPU is unprotected. Run: watchdog start -AllowKill"
        hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = ($ctx -join "`n") }
      }
    }
    $out | ConvertTo-Json -Depth 5 -Compress
    $global:LASTEXITCODE = 0
    return
  }

  Write-Output "WATCHDOG $verdict"
  if (-not ($Brief -and $code -eq 0)) { $detail | ForEach-Object { Write-Output "  $_" } }
  $global:LASTEXITCODE = $code
}
