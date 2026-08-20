# W-01: never truncate the CSV on start. W-02: rows carry a UTC date, not HH:mm:ss.
function Initialize-WatchdogCsv {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Timestamp
  )
  $header = 'timestamp,gpu_temp_c,gpu_power_w,vram_mib,ram_pct,ram_gb,sd_python_pids,state'
  if (-not (Test-Path $Path)) {
    $header | Set-Content -Path $Path
    return 'created'
  }
  "$Timestamp,,,,,,,restart" | Add-Content -Path $Path
  return 'appended'
}
