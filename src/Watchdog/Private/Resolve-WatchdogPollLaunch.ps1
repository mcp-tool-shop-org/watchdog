function Resolve-WatchdogPwshPath {
  # Absolute path of a pwsh that Task Scheduler can start. Task Scheduler looks a bare 'pwsh' up on the machine
  # PATH only, and a Store install of PowerShell is an execution alias in the user's WindowsApps, so a bare name
  # fails with 0x80070002 (file not found) on every trigger. The first pwsh on this user's PATH is the stable
  # alias for a Store install (not its versioned package folder); otherwise use the pwsh running this.
  $cmd = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd -and $cmd.Source) { return $cmd.Source }
  $self = (Get-Process -Id $PID).Path
  if ($self -and (Split-Path $self -Leaf) -ieq 'pwsh.exe') {
    # A Store install's package folder carries its version and moves on every update; registering it would break
    # the task at the next update.
    if ($self -like '*\Program Files\WindowsApps\*') {
      throw "pwsh is only reachable through its versioned Store package folder ($self). Put pwsh on PATH, then register again."
    }
    return $self
  }
  throw 'pwsh.exe not found: the poll task needs PowerShell 7 (pwsh).'
}

function Read-WatchdogPollStamp([string]$Path) {
  # The stamp Invoke-WatchdogPoll writes after its liveness work on every run, or $null when it is missing or unreadable.
  # The instant is utc_ms (Unix milliseconds). The 'utc' text is for people only: ConvertFrom-Json turns an ISO
  # string into a DateTime, and re-reading that as text shifts it by the local UTC offset and drops the milliseconds
  # (2026-11-24, on a rig in Eastern time a stale stamp read as fresh).
  try {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $doc = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $doc.utc_ms) { return $null }
    $ms = [int64]$doc.utc_ms
    return [pscustomobject]@{ UtcMs = $ms; Utc = [DateTimeOffset]::FromUnixTimeMilliseconds($ms); State = [string]$doc.state; Exit = $doc.exit }
  } catch {
    return $null
  }
}

function Invoke-WatchdogPollTaskProbe {
  # Starts the task once and proves that the poll itself ran: Invoke-WatchdogPoll writes a stamp under Root after its
  # liveness work on every run, and only a stamp newer than this start counts. The task's exit code proves nothing, because the
  # action is conhost --headless, which exits 0 even when the pwsh it should start does not exist (measured on the
  # rig, 2026-11-24). A registered task is not a running one: on 2026-11-24 the poll task had existed for weeks and
  # never started.
  param(
    [Parameter(Mandatory)][string]$TaskName,
    [Parameter(Mandatory)][string]$StampPath,
    [int]$TimeoutSec = 60,
    [int]$StepMs = 500
  )
  $startedMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  # Clear the previous stamp, so a stamp present after the run was written after this point; the time check below
  # is the second guard. A run the trigger starts meanwhile also counts: it is the same action.
  if (Test-Path -LiteralPath $StampPath) {
    try {
      Remove-Item -LiteralPath $StampPath -Force -ErrorAction Stop
    } catch {
      throw "Could not clear the previous poll stamp ($StampPath), so the first run could not be proven: $($_.Exception.Message)"
    }
  }
  Start-ScheduledTask -TaskName $TaskName
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds $StepMs
    # The poll writes its stamp right after its liveness work, so a fresh stamp counts at once, even while the task
    # is still running an opt-in cache release that can take minutes.
    $stamp = Read-WatchdogPollStamp $StampPath
    if ($stamp -and $stamp.UtcMs -ge $startedMs) {
      $info = Get-ScheduledTaskInfo -TaskName $TaskName
      return [pscustomobject]@{ State = $stamp.State; Exit = $stamp.Exit; LastTaskResult = [int64]$info.LastTaskResult }
    }
  }
  throw "$TaskName did not write a fresh poll stamp ($StampPath) within $TimeoutSec s, so the poll did not run. Check that pwsh starts from Task Scheduler."
}
