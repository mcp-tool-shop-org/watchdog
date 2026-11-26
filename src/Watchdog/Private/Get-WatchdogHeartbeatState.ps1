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

function Get-WatchdogInnerException($Exception, [type]$Type) {
  $e = $Exception
  while ($e) {
    if ($e -is $Type) { return $e }
    $e = $e.InnerException
  }
  return $null
}

# A heartbeat is ISO-8601 with an explicit offset (Z or +hh:mm). Anything else, including a timestamp cut off
# before its Z, would parse as LOCAL time and could read as hours fresh on a dead loop.
$script:WatchdogHeartbeatPattern = '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?(Z|[+-]\d{2}:\d{2})$'

function Get-WatchdogHeartbeatAgeState([double]$Age, [int]$StaleSec) {
  # A heartbeat more than 5 s in the future (clock stepped back, or a bad parse) is not proof of life.
  # Fail closed: only an age inside the window is RUNNING (NaN compares false and lands on STALE).
  if ($Age -ge -5 -and $Age -le $StaleSec) { return 'RUNNING' }
  return 'STALE'
}

function Get-WatchdogHeartbeatState {
  # 2026-11-26 12:26: one locked/empty read made the poller declare the watchdog DEAD while the loop was alive
  # (Set-Content truncates before it writes, and outside readers can hold the file). Each attempt reads the file;
  # an empty or IO-locked read is transient, a partial or malformed one is junk, and both are retried. If the
  # last attempt was transient, the age comes from LastWriteTime (Source = 'mtime'), which only the loop's
  # write moves. If it was junk, the result is STALE (Source = 'unparseable'): no mtime fallback for content
  # that reads but does not parse. A file deleted mid-call (a clean stop) is NOT_RUNNING.
  param(
    [string]$Path,
    [int]$StaleSec,
    [datetimeoffset]$Now = [datetimeoffset]::UtcNow,
    [int]$Attempts = 5,
    [int]$RetryDelayMs = 50
  )
  $notRunning = [pscustomobject]@{ State = 'NOT_RUNNING'; AgeSec = $null; Last = $null; Source = $null }
  if (-not (Test-Path -LiteralPath $Path)) { return $notRunning }
  # [IO.File]::Open resolves relative paths against the process directory, not $PWD; resolve through the
  # provider so a caller sitting on a non-FileSystem drive (Env:, HKLM:) still gets the file path.
  $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
  $Attempts = [math]::Max(1, $Attempts)
  $lastKind = ''
  foreach ($i in 1..$Attempts) {
    try {
      $raw = Read-WatchdogHeartbeatText -Path $full
      $text = if ($null -eq $raw) { '' } else { $raw.Trim() }
      if ($text -eq '') {
        $lastKind = 'transient'
      } elseif ($text -notmatch $script:WatchdogHeartbeatPattern) {
        $lastKind = 'junk'
      } else {
        $last = [datetimeoffset]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture)
        $age = ($Now - $last).TotalSeconds
        return [pscustomobject]@{
          State = (Get-WatchdogHeartbeatAgeState $age $StaleSec); AgeSec = $age; Last = $last; Source = 'content'
        }
      }
    } catch {
      if ((Get-WatchdogInnerException $_.Exception ([System.IO.FileNotFoundException])) -or
          (Get-WatchdogInnerException $_.Exception ([System.IO.DirectoryNotFoundException]))) {
        return $notRunning
      } elseif (Get-WatchdogInnerException $_.Exception ([System.IO.IOException])) {
        $lastKind = 'transient'
      } else {
        $lastKind = 'junk'
      }
    }
    if ($i -lt $Attempts) { Start-Sleep -Milliseconds $RetryDelayMs }
  }
  if ($lastKind -eq 'transient') {
    try {
      $item = Get-Item -LiteralPath $full -ErrorAction Stop
      $last = [datetimeoffset][datetime]::SpecifyKind($item.LastWriteTimeUtc, 'Utc')
      $age = ($Now - $last).TotalSeconds
      return [pscustomobject]@{
        State = (Get-WatchdogHeartbeatAgeState $age $StaleSec); AgeSec = $age; Last = $last; Source = 'mtime'
      }
    } catch {
      if ($_.Exception -is [System.Management.Automation.ItemNotFoundException] -or
          (Get-WatchdogInnerException $_.Exception ([System.IO.FileNotFoundException]))) {
        return $notRunning
      }
      return [pscustomobject]@{ State = 'STALE'; AgeSec = [double]::NaN; Last = $null; Source = 'unreadable' }
    }
  }
  return [pscustomobject]@{ State = 'STALE'; AgeSec = [double]::NaN; Last = $null; Source = 'unparseable' }
}

function Format-WatchdogAge([double]$s) {
  if ([double]::IsNaN($s)) { return 'unreadable' }
  if ($s -lt 90)     { return "$([math]::Round($s))s" }
  if ($s -lt 5400)   { return "$([math]::Round($s/60,1))m" }
  if ($s -lt 172800) { return "$([math]::Round($s/3600,1))h" }
  return "$([math]::Round($s/86400,1))d"
}
