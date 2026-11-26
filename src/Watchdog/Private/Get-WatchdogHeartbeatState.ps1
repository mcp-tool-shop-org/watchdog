function Read-WatchdogHeartbeatText {
  # Open with full sharing so this reader never fails on another reader's share mode. It can still collide
  # with the loop's Set-Content (which opens without sharing); the loop retries its write, and this reader
  # retries and then falls back to LastWriteTime.
  param([string]$Path)
  $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
    [System.IO.FileShare]'ReadWrite, Delete')
  try {
    $sr = [System.IO.StreamReader]::new($fs)
    try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
  } finally { $fs.Dispose() }
}

function Test-WatchdogIoException($Exception) {
  $e = $Exception
  while ($e) {
    if ($e -is [System.IO.IOException]) { return $true }
    $e = $e.InnerException
  }
  return $false
}

function Get-WatchdogHeartbeatState {
  # 2026-11-26 12:26: one locked/empty read made the poller declare the watchdog DEAD while the loop was alive
  # (Set-Content truncates before it writes, and outside readers can hold the file). An empty or locked read is
  # retried; if it stays that way, the age comes from the file's LastWriteTime (Source = 'mtime'), which the
  # loop's own write moves. Content that reads but does not parse is still STALE: that is a broken writer.
  param(
    [string]$Path,
    [int]$StaleSec,
    [datetimeoffset]$Now = [datetimeoffset]::UtcNow,
    [int]$Attempts = 5,
    [int]$RetryDelayMs = 50
  )
  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject]@{ State = 'NOT_RUNNING'; AgeSec = $null; Last = $null; Source = $null }
  }
  $Attempts = [math]::Max(1, $Attempts)
  $transient = $false
  foreach ($i in 1..$Attempts) {
    try {
      $raw = Read-WatchdogHeartbeatText -Path $Path
      if ([string]::IsNullOrWhiteSpace($raw)) {
        $transient = $true
      } else {
        $last = [datetimeoffset]::Parse($raw.Trim())
        $age = ($Now - $last).TotalSeconds
        $state = if ($age -le $StaleSec) { 'RUNNING' } else { 'STALE' }
        return [pscustomobject]@{ State = $state; AgeSec = $age; Last = $last; Source = 'content' }
      }
    } catch {
      if (Test-WatchdogIoException $_.Exception) {
        $transient = $true
      } else {
        return [pscustomobject]@{ State = 'STALE'; AgeSec = [double]::NaN; Last = $null; Source = 'unparseable' }
      }
    }
    if ($i -lt $Attempts) { Start-Sleep -Milliseconds $RetryDelayMs }
  }
  if ($transient) {
    try {
      $last = [datetimeoffset][datetime]::SpecifyKind((Get-Item -LiteralPath $Path).LastWriteTimeUtc, 'Utc')
      $age = ($Now - $last).TotalSeconds
      $state = if ($age -le $StaleSec) { 'RUNNING' } else { 'STALE' }
      return [pscustomobject]@{ State = $state; AgeSec = $age; Last = $last; Source = 'mtime' }
    } catch { }
  }
  return [pscustomobject]@{ State = 'STALE'; AgeSec = [double]::NaN; Last = $null; Source = 'unreadable' }
}

function Format-WatchdogAge([double]$s) {
  if ([double]::IsNaN($s)) { return 'unreadable' }
  if ($s -lt 90)     { return "$([math]::Round($s))s" }
  if ($s -lt 5400)   { return "$([math]::Round($s/60,1))m" }
  if ($s -lt 172800) { return "$([math]::Round($s/3600,1))h" }
  return "$([math]::Round($s/86400,1))d"
}
