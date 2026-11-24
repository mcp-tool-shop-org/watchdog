function Resolve-WatchdogPwshPath {
  # Absolute path of a pwsh that Task Scheduler can start. Task Scheduler looks a bare 'pwsh' up on the machine
  # PATH only, and a Store install of PowerShell is an execution alias in the user's WindowsApps, so a bare name
  # fails with 0x80070002 (file not found) on every trigger. The first pwsh on this user's PATH is the stable
  # alias for a Store install (not its versioned package folder); otherwise use the pwsh running this.
  $cmd = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd -and $cmd.Source) { return $cmd.Source }
  $self = (Get-Process -Id $PID).Path
  if ($self -and (Split-Path $self -Leaf) -ieq 'pwsh.exe') { return $self }
  throw 'pwsh.exe not found: the poll task needs PowerShell 7 (pwsh).'
}

function Invoke-WatchdogPollTaskProbe {
  # Starts the task once and waits for that run to finish. Returns its LastTaskResult (0 = it ran cleanly).
  # A registered task is not a running one: on 2026-11-24 the poll task had existed for weeks and never started.
  param(
    [Parameter(Mandatory)][string]$TaskName,
    [int]$TimeoutSec = 60,
    [int]$StepMs = 500
  )
  $before = (Get-ScheduledTaskInfo -TaskName $TaskName).LastRunTime
  Start-ScheduledTask -TaskName $TaskName
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds $StepMs
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    $state = "$((Get-ScheduledTask -TaskName $TaskName).State)"
    if ($info.LastRunTime -ne $before -and $state -ne 'Running') { return [int64]$info.LastTaskResult }
  }
  throw "$TaskName did not finish its first run within $TimeoutSec s"
}
