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
  $mod = Join-Path $script:WatchdogModuleRoot 'Watchdog.psd1'
  $interval = [Math]::Max(15, [int]$cfg.PollIntervalSec)
  $arg = "-NoProfile -ExecutionPolicy Bypass -Command `"Import-Module -Force '$mod'; Invoke-WatchdogPoll -ConfigPath '$($cfg.ConfigPath)'`""
  $action = New-ScheduledTaskAction -Execute 'pwsh' -Argument $arg
  $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Seconds $interval) -RepetitionDuration ([TimeSpan]::MaxValue)
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName 'MCPToolShop.Watchdog.Poll' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
  Write-Output "registered scheduled task MCPToolShop.Watchdog.Poll every ${interval}s (detect only, never restart)."
}

function Unregister-WatchdogPoll {
  <#
  .SYNOPSIS
    Remove the CurrentUser heartbeat poll scheduled task.
  #>
  [CmdletBinding()]
  param()
  Unregister-ScheduledTask -TaskName 'MCPToolShop.Watchdog.Poll' -Confirm:$false -ErrorAction SilentlyContinue
  Write-Output "unregistered scheduled task MCPToolShop.Watchdog.Poll (if it existed)."
}
