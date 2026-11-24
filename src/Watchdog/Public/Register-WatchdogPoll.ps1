function Register-WatchdogPoll {
  <#
  .SYNOPSIS
    Register a CurrentUser scheduled task that polls heartbeat. Detects death; never restarts.
  #>
  [CmdletBinding()]
  param(
    [string]$ConfigPath
  )
  if (-not $IsWindows) {
    $err = New-WatchdogError -Code 'PLATFORM_UNSUPPORTED' -Message 'Scheduled-task poller is Windows-only in v1.' -Hint 'Linux is a later version.' -Retryable $false -ExitCode 1
    Write-WatchdogError -ErrorObject $err
    $global:LASTEXITCODE = 1
    return
  }
  $cfg = Resolve-WatchdogConfig -Path $ConfigPath
  if (Test-WatchdogError $cfg) {
    Write-WatchdogError -ErrorObject $cfg
    $global:LASTEXITCODE = $cfg.exitCode
    return
  }
  # The first poll writes its stamp (and _watchdog_DEAD, when no loop runs yet) under Root, which may not exist before
  # the first Start-Watchdog. Create it before registering anything, and stop here if Root is not a usable folder.
  try {
    [void][IO.Directory]::CreateDirectory([string]$cfg.Root)
  } catch {
    throw "Root '$($cfg.Root)' could not be created as a folder, so no poll could write there: $($_.Exception.Message)"
  }
  if (-not (Test-Path -LiteralPath $cfg.Root -PathType Container)) {
    throw "Root '$($cfg.Root)' is not a folder, so no poll could write there."
  }
  $probeFile = Join-Path $cfg.Root ('_watchdog_write_probe_' + [guid]::NewGuid().ToString('N'))
  try {
    Set-Content -LiteralPath $probeFile -Value '' -NoNewline -ErrorAction Stop
    Remove-Item -LiteralPath $probeFile -Force -ErrorAction Stop
  } catch {
    Remove-Item -LiteralPath $probeFile -Force -ErrorAction SilentlyContinue
    throw "Root is not writable, so no poll could write there: $($_.Exception.Message)"
  }
  $mod = Join-Path $script:WatchdogModuleRoot 'Watchdog.psd1'
  $interval = [Math]::Max(60, [int]$cfg.PollIntervalSec)
  # A per-registration token in the action: only a stamp that carries it proves that THIS action ran a poll, not a
  # manual poll on the same Root or another registration's run. Hex only, so it needs no quoting.
  $token = [guid]::NewGuid().ToString('N')
  # The absolute pwsh path (a bare 'pwsh' is not found by Task Scheduler for a Store install), started through
  # conhost --headless so no console window flashes on every poll.
  $pwsh = Resolve-WatchdogPwshPath
  $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
  # Single-quoted PowerShell strings: an apostrophe in a path is doubled.
  $modQ = $mod.Replace("'", "''")
  $cfgQ = ([string]$cfg.ConfigPath).Replace("'", "''")
  $poll = "Import-Module -Force '$modQ'; Invoke-WatchdogPoll -ConfigPath '$cfgQ' -RegistrationToken '$token'"
  $arg = "--headless `"$pwsh`" -NoProfile -ExecutionPolicy Bypass -Command `"$poll`""
  $action = New-ScheduledTaskAction -Execute $conhost -Argument $arg
  # Windows rejects TimeSpan.MaxValue as ISO duration P99999999DT23H59M59S (this build).
  # 10 years is "until we uninstall"; do not print success unless Get-ScheduledTask sees the task.
  $rep = New-TimeSpan -Seconds $interval
  $dur = New-TimeSpan -Days 3650
  $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval $rep -RepetitionDuration $dur
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
  try {
    Register-ScheduledTask -TaskName 'MCPToolShop.Watchdog.Poll' -TaskPath '\' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
  } catch {
    throw ("Task Scheduler refused to register MCPToolShop.Watchdog.Poll: {0} A task first registered from an elevated shell can only be replaced from one: run Unregister-WatchdogPoll there once, then register again." -f $_.Exception.Message)
  }
  $task = Get-ScheduledTask -TaskName 'MCPToolShop.Watchdog.Poll' -TaskPath '\' -ErrorAction SilentlyContinue
  if (-not $task) {
    throw "Register-ScheduledTask returned without creating MCPToolShop.Watchdog.Poll"
  }
  $held = @($task.Actions)[0]
  if ("$($held.Execute)" -ne $conhost -or "$($held.Arguments)" -ne $arg) {
    throw "MCPToolShop.Watchdog.Poll exists but still holds an older action ($($held.Execute)); it was not replaced."
  }
  # Run it once now and require proof that this action ran a poll (a fresh stamp under Root carrying this
  # registration's token), so a task that can never start is an error here, not a silent gap.
  $paths = Get-WatchdogPaths -Root $cfg.Root
  $first = Invoke-WatchdogPollTaskProbe -TaskName 'MCPToolShop.Watchdog.Poll' -StampPath $paths.PollStamp -Token $token -TimeoutSec 60
  $wsl = if ($cfg.WslCacheRelease) { '; WslCacheRelease is on, so each poll may also drop the WSL page cache' } else { '' }
  Write-Output "registered scheduled task MCPToolShop.Watchdog.Poll every ${interval}s (detects death, never kills or restarts$wsl); its first run polled and saw $($first.State)."
}

function Unregister-WatchdogPoll {
  <#
  .SYNOPSIS
    Remove the CurrentUser heartbeat poll scheduled task.
  #>
  [CmdletBinding()]
  param()
  $existing = Get-ScheduledTask -TaskName 'MCPToolShop.Watchdog.Poll' -TaskPath '\' -ErrorAction SilentlyContinue
  if (-not $existing) {
    Write-Output 'no scheduled task MCPToolShop.Watchdog.Poll to remove.'
    return
  }
  try {
    Unregister-ScheduledTask -TaskName 'MCPToolShop.Watchdog.Poll' -TaskPath '\' -Confirm:$false -ErrorAction Stop
  } catch {
    throw ("Task Scheduler refused to unregister MCPToolShop.Watchdog.Poll: {0} A task first registered from an elevated shell can only be removed from one: run Unregister-WatchdogPoll there once." -f $_.Exception.Message)
  }
  Write-Output 'unregistered scheduled task MCPToolShop.Watchdog.Poll.'
}
