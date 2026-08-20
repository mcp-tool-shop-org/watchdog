function Get-WatchdogPaths([string]$Root) {
  [pscustomobject]@{
    Root      = $Root
    Csv       = Join-Path $Root '_watchdog_log.csv'
    Kill      = Join-Path $Root '_watchdog_KILL.log'
    Trip      = Join-Path $Root '_watchdog_TRIPPED'
    Stop      = Join-Path $Root '_watchdog_STOP'
    Heartbeat = Join-Path $Root '_watchdog_HEARTBEAT'
    Dead      = Join-Path $Root '_watchdog_DEAD'
    NoTarget  = Join-Path $Root '_watchdog_NO_TARGET'
    Console   = Join-Path $Root '_watchdog_console.log'
    Crash     = Join-Path $Root '_watchdog_crash.log'
  }
}

function Test-WatchdogPathUnderRoot {
  param([string]$Root, [string]$Path)
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
  $pathFull = [System.IO.Path]::GetFullPath($Path)
  return $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
}
