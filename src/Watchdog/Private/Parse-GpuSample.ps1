# nvidia-smi can emit warning/info lines, multiple lines, or stringify as Object[] during driver hiccups —
# .Split() on that killed the loop (2026-06-12 03:29:53). Filter to lines shaped like 'temp,power,vram',
# take the first; anything else throws into the per-sample catch instead of dying.
function Parse-GpuSample([object[]]$raw) {
  $lines = @($raw) | ForEach-Object { "$_" -replace '\s','' } | Where-Object { $_ -match '^\d+,[^,]*,\d+$' }
  if (-not $lines) { throw "nvidia-smi gave no parseable GPU line: '$((@($raw) | ForEach-Object { "$_" }) -join ' || ')'" }
  $f = @($lines)[0] -split ','
  [pscustomobject]@{ Temp = [int]$f[0]; Power = $f[1]; Vram = [int]$f[2] }
}
