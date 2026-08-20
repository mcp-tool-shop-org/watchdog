function Test-WslRunning([string]$distro) {
  try {
    $names = @(& wsl -l --running -q 2>$null) | ForEach-Object { ("$_" -replace "`0",'').Trim() } | Where-Object { $_ }
    return ($names -contains $distro)
  } catch { return $false }
}
