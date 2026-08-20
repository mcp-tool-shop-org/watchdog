# Per-process VRAM so a breach names its holder — the 2026-08-04 burst logged 153 ABORTs without one.
# nvidia-smi's per-process used_gpu_memory reads [N/A] under WDDM (measured on this rig 2026-08-04, all
# rows), so the source is the '\GPU Process Memory' counter set (~1.3s per call; breach path only, never
# the normal loop). Best-effort: any failure degrades to a note and must never kill the loop.
# Linux host path is a later version (nvidia-smi pmon / /proc); v1 is Windows / WDDM only.
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
