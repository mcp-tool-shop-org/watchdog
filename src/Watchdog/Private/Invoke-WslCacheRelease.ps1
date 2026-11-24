# WSL file-cache release (opt-in, WslCacheRelease = $true).
#
# 2026-11-23: the WSL VM (vmmemWSL, capped at 28 GB by .wslconfig) held 24.6 GB on a 64 GB host while
# Windows sat at 81% used. Inside Linux, 2.9 GB was process memory and ~27 GB was file cache left by
# large container image pulls. `autoMemoryReclaim=dropCache` only fires when the VM is idle, and a running
# container engine keeps it busy. Dropping the page cache stops nothing that is running, so the poller may
# do it. It never kills a process.

function Test-WslCacheReleaseNeeded {
  # Pure decision. Returns 'act' or the reason not to act.
  param(
    [Parameter(Mandatory)] $Cfg,
    [double]$WslGB,
    [double]$WinUsedPct,
    [bool]$WslUp
  )
  if (-not $Cfg.WslCacheRelease) { return 'disabled' }
  if (-not $WslUp) { return 'wsl-not-running' }
  if ($WslGB -ge $Cfg.WslCacheHighGB) { return 'act' }
  if ($WinUsedPct -ge $Cfg.WslCacheWinHighPct -and $WslGB -ge $Cfg.WslCacheMinGB) { return 'act' }
  return 'below-threshold'
}

function Get-WslHostMemory {
  # Windows-side read only. Never starts or wakes the WSL VM.
  $os = Get-CimInstance Win32_OperatingSystem
  $vm = Get-Process -Name vmmemWSL -ErrorAction SilentlyContinue
  $wslBytes = if ($vm) { ($vm | Measure-Object WorkingSet64 -Sum).Sum } else { 0 }
  [pscustomobject]@{
    WinUsedPct = 100 - 100 * $os.FreePhysicalMemory / $os.TotalVisibleMemorySize
    WinFreeGB  = $os.FreePhysicalMemory / 1MB
    WslGB      = $wslBytes / 1GB
    WslUp      = [bool]$vm
  }
}

function Invoke-WslRootCommand {
  # Runs one shell command as root in the distro with a hard timeout. Throws on timeout or non-zero exit.
  param(
    [Parameter(Mandatory)][string]$Distro,
    [Parameter(Mandatory)][string]$Command,
    [int]$TimeoutSec = 90
  )
  Invoke-ProcessWithTimeout -FileName 'wsl.exe' -Arguments "-d $Distro -u root -e sh -c `"$Command`"" -TimeoutSec $TimeoutSec
}

function Invoke-ProcessWithTimeout {
  # Starts a process with no window, waits up to TimeoutSec, kills it on timeout. Returns stdout.
  param(
    [Parameter(Mandatory)][string]$FileName,
    [string]$Arguments = '',
    [int]$TimeoutSec = 90
  )
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FileName
  $psi.Arguments = $Arguments
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $out = $p.StandardOutput.ReadToEndAsync()
  $err = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    try { $p.Kill($true) } catch { }
    throw "$FileName timed out after $TimeoutSec s"
  }
  if ($p.ExitCode -ne 0) {
    throw ("{0} exited {1}: {2}" -f $FileName, $p.ExitCode, (($err.Result -replace "`0", '').Trim()))
  }
  return ($out.Result -replace "`0", '')
}

function ConvertFrom-WslMeminfoCache([string]$Text) {
  # Sums Buffers + Cached from /proc/meminfo lines. Returns GB.
  $kb = 0.0
  foreach ($line in ($Text -split "`n")) {
    if ($line -match '^(Buffers|Cached):\s+(\d+)\s+kB') { $kb += [double]$Matches[2] }
  }
  return $kb / 1MB
}

function Write-WslCacheLog([string]$Path, [string]$Message) {
  try {
    if ((Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path).Length -gt 1MB)) {
      Move-Item -LiteralPath $Path -Destination ($Path + '.1') -Force
    }
    Add-Content -LiteralPath $Path -Value ("{0}  {1}" -f (Get-WatchdogTimestamp), $Message)
  } catch { }
}

function Get-WslTopProcesses([int]$Count = 5) {
  Get-Process | Group-Object ProcessName | ForEach-Object {
    [pscustomobject]@{ Name = $_.Name; GB = (($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1GB) }
  } | Sort-Object GB -Descending | Select-Object -First $Count | ForEach-Object { '{0} {1:N1}GB' -f $_.Name, $_.GB }
}

function Invoke-WslCacheRelease {
  # One check. Never throws: the poller's main job (heartbeat liveness) must not depend on it.
  param(
    [Parameter(Mandatory)] $Cfg,
    [Parameter(Mandatory)] $Paths,
    [scriptblock]$ReadHost = { Get-WslHostMemory },
    [scriptblock]$RunWsl = { param($Distro, $Command, $TimeoutSec) Invoke-WslRootCommand -Distro $Distro -Command $Command -TimeoutSec $TimeoutSec },
    [scriptblock]$TopProcesses = { Get-WslTopProcesses },
    [scriptblock]$DistroRunning = { param($Distro) Test-WslRunning $Distro },
    [datetime]$Now = (Get-Date)
  )
  try {
    $s = & $ReadHost
    $state = 'win_used={0:N0}% free={1:N1}GB vmmemWSL={2:N1}GB' -f $s.WinUsedPct, $s.WinFreeGB, $s.WslGB

    if ($Cfg.WslCacheRelease) {
      $hour = $Now.ToString('yyyyMMddHH')
      $lastHb = if (Test-Path -LiteralPath $Paths.WslCacheHeartbeat) { (Get-Content -LiteralPath $Paths.WslCacheHeartbeat -Raw).Trim() } else { '' }
      if ($lastHb -ne $hour) {
        Write-WslCacheLog $Paths.WslCacheLog "heartbeat $state"
        Set-Content -LiteralPath $Paths.WslCacheHeartbeat -Value $hour
      }
    }

    $decision = Test-WslCacheReleaseNeeded -Cfg $Cfg -WslGB $s.WslGB -WinUsedPct $s.WinUsedPct -WslUp $s.WslUp
    if ($decision -ne 'act') { return [pscustomobject]@{ Action = $decision } }

    if (Test-Path -LiteralPath $Paths.WslCacheLast) {
      $last = [datetime]::Parse((Get-Content -LiteralPath $Paths.WslCacheLast -Raw).Trim(), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
      if (($Now - $last).TotalSeconds -lt $Cfg.WslCacheCooldownSec) { return [pscustomobject]@{ Action = 'cooldown' } }
    }

    # Another distro (a container engine's, for example) can keep vmmemWSL up while WslDistro is stopped, and
    # `wsl -d <distro>` would START it. So act only when WslDistro is already running; listing the running
    # distros starts nothing. A run of skips logs one line, and the hourly heartbeat ends the run, so a long
    # run shows at most one skip line an hour.
    if (-not (& $DistroRunning $Cfg.WslDistro)) {
      $skip = "skip: distro '$($Cfg.WslDistro)' is not running, and a cache drop never starts it"
      $lastLine = if (Test-Path -LiteralPath $Paths.WslCacheLog) { [string](Get-Content -LiteralPath $Paths.WslCacheLog -Tail 1) } else { '' }
      if (-not $lastLine.Contains($skip)) { Write-WslCacheLog $Paths.WslCacheLog "$skip; $state" }
      return [pscustomobject]@{ Action = 'distro-not-running' }
    }

    $cacheGB = ConvertFrom-WslMeminfoCache (& $RunWsl $Cfg.WslDistro "grep -E '^(Buffers|Cached):' /proc/meminfo" $Cfg.WslCacheTimeoutSec)
    if ($cacheGB -lt $Cfg.WslCacheMinCacheGB) {
      Write-WslCacheLog $Paths.WslCacheLog ('no drop: linux cache {0:N1}GB below {1}GB; {2}' -f $cacheGB, $Cfg.WslCacheMinCacheGB, $state)
      return [pscustomobject]@{ Action = 'cache-small'; CacheGB = $cacheGB }
    }

    [void](& $RunWsl $Cfg.WslDistro 'sync; echo 1 > /proc/sys/vm/drop_caches' $Cfg.WslCacheTimeoutSec)
    Set-Content -LiteralPath $Paths.WslCacheLast -Value $Now.ToString('o')
    if ($Cfg.WslCacheSettleSec -gt 0) { Start-Sleep -Seconds $Cfg.WslCacheSettleSec }
    $a = & $ReadHost
    Write-WslCacheLog $Paths.WslCacheLog ('DROPPED linux cache {0:N1}GB; before {1}; after win_used={2:N0}% free={3:N1}GB vmmemWSL={4:N1}GB' -f $cacheGB, $state, $a.WinUsedPct, $a.WinFreeGB, $a.WslGB)

    if ($a.WinUsedPct -ge $Cfg.WslCacheAlertPct) {
      Write-WslCacheLog $Paths.WslCacheLog ('ALERT windows still {0:N0}% used after the drop; top: {1}' -f $a.WinUsedPct, ((& $TopProcesses) -join ', '))
    }
    return [pscustomobject]@{ Action = 'dropped'; CacheGB = $cacheGB; Before = $s; After = $a }
  } catch {
    Write-WslCacheLog $Paths.WslCacheLog ('ERROR ' + $_.Exception.Message)
    return [pscustomobject]@{ Action = 'error'; Error = $_.Exception.Message }
  }
}
