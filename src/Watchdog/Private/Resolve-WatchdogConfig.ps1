function Find-WatchdogConfigPath {
  param([string]$Path)
  if ($Path) { return $Path }
  if ($env:WATCHDOG_CONFIG) { return $env:WATCHDOG_CONFIG }
  $guesses = @(
    (Join-Path (Get-Location) 'watchdog.config.psd1'),
    (Join-Path $HOME '.watchdog\config.psd1')
  )
  return ($guesses | Where-Object { Test-Path $_ } | Select-Object -First 1)
}

function Test-WatchdogAbsolutePath([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  return [System.IO.Path]::IsPathRooted($Value)
}

function Resolve-WatchdogConfig {
  param(
    [string]$Path,
    [hashtable]$Override = @{}
  )
  $candidate = Find-WatchdogConfigPath -Path $Path
  if (-not $candidate) {
    return New-WatchdogError -Code 'CONFIG_MISSING' -Message 'No watchdog config found.' -Hint 'Copy src/Watchdog/config/watchdog.example.psd1 to ~/.watchdog/config.psd1 or pass -ConfigPath. There is no default Root or kill list.' -Retryable $true -ExitCode 1
  }
  if (-not (Test-Path $candidate)) {
    return New-WatchdogError -Code 'CONFIG_MISSING' -Message "Config file not found: $candidate" -Hint 'Pass an existing -ConfigPath. Copy the example file to get started.' -Retryable $true -ExitCode 1
  }

  try {
    $raw = Import-PowerShellDataFile -Path $candidate
  } catch {
    return New-WatchdogError -Code 'CONFIG_INVALID' -Message "Config file could not be parsed: $candidate" -Hint 'The file must be a PowerShell data file (hashtable).' -Cause $_.Exception.Message -Retryable $false -ExitCode 1
  }

  foreach ($k in $Override.Keys) { $raw[$k] = $Override[$k] }

  $required = @('Root', 'Targets', 'VramKillMiB', 'RamKillPct', 'TempKillC')
  foreach ($key in $required) {
    if (-not $raw.ContainsKey($key) -or $null -eq $raw[$key] -or ($raw[$key] -is [string] -and [string]::IsNullOrWhiteSpace($raw[$key]))) {
      return New-WatchdogError -Code 'CONFIG_REQUIRED' -Message "Config is missing required field '$key'." -Hint 'See src/Watchdog/config/watchdog.example.psd1. Hardware envelope fields have no silent default.' -Retryable $true -ExitCode 1
    }
  }

  if (-not (Test-WatchdogAbsolutePath $raw.Root)) {
    return New-WatchdogError -Code 'CONFIG_PATH_NOT_ABSOLUTE' -Message "Root must be an absolute path (got '$($raw.Root)')." -Hint 'The module refuses relative Root so it cannot write next to whatever cwd an agent happens to have.' -Retryable $true -ExitCode 1
  }

  $targets = @($raw.Targets)
  foreach ($t in $targets) {
    if (-not (Test-WatchdogAbsolutePath $t)) {
      return New-WatchdogError -Code 'CONFIG_PATH_NOT_ABSOLUTE' -Message "Each Targets entry must be an absolute path (got '$t')." -Hint 'List the full path to each guarded interpreter. An empty Targets array is allowed and is a protection gap.' -Retryable $true -ExitCode 1
    }
  }

  [pscustomobject]@{
    Kind            = 'Config'
    ConfigPath      = [System.IO.Path]::GetFullPath($candidate)
    Root            = [System.IO.Path]::GetFullPath($raw.Root)
    Targets         = @($targets)
    VramKillMiB     = [int]$raw.VramKillMiB
    RamKillPct      = [int]$raw.RamKillPct
    TempKillC       = [int]$raw.TempKillC
    IntervalSec     = [int]$(if ($raw.ContainsKey('IntervalSec')) { $raw.IntervalSec } else { 2 })
    BreachSamples   = [int]$(if ($raw.ContainsKey('BreachSamples')) { $raw.BreachSamples } else { 3 })
    StaleSec        = [int]$(if ($raw.ContainsKey('StaleSec')) { $raw.StaleSec } else { 15 })
    WslDistro       = [string]$(if ($raw.ContainsKey('WslDistro')) { $raw.WslDistro } else { 'Ubuntu' })
    WslKillPattern  = [string]$(if ($raw.ContainsKey('WslKillPattern')) { $raw.WslKillPattern } else { '' })
    AllowKill       = [bool]$(if ($raw.ContainsKey('AllowKill')) { $raw.AllowKill } else { $false })
    PollIntervalSec = [int]$(if ($raw.ContainsKey('PollIntervalSec')) { $raw.PollIntervalSec } else { 30 })
  }
}
