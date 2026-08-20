function Get-WatchdogHeartbeatState {
  param(
    [string]$Path,
    [int]$StaleSec,
    [datetimeoffset]$Now = [datetimeoffset]::UtcNow
  )
  if (-not (Test-Path $Path)) {
    return [pscustomobject]@{ State = 'NOT_RUNNING'; AgeSec = $null; Last = $null }
  }
  try {
    $last = [datetimeoffset]::Parse((Get-Content $Path -Raw).Trim())
    $age = ($Now - $last).TotalSeconds
    $state = if ($age -le $StaleSec) { 'RUNNING' } else { 'STALE' }
    return [pscustomobject]@{ State = $state; AgeSec = $age; Last = $last }
  } catch {
    return [pscustomobject]@{ State = 'STALE'; AgeSec = [double]::NaN; Last = $null }
  }
}

function Format-WatchdogAge([double]$s) {
  if ([double]::IsNaN($s)) { return 'unreadable' }
  if ($s -lt 90)     { return "$([math]::Round($s))s" }
  if ($s -lt 5400)   { return "$([math]::Round($s/60,1))m" }
  if ($s -lt 172800) { return "$([math]::Round($s/3600,1))h" }
  return "$([math]::Round($s/86400,1))d"
}
