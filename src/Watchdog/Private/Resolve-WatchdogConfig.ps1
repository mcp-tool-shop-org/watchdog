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

function ConvertTo-WatchdogFiniteDouble {
  param(
    $RawValue,
    [ref]$OutDouble
  )
  if ($null -eq $RawValue -or $RawValue -is [bool]) { return $false }
  if ($RawValue -isnot [string] -and $RawValue -is [System.Collections.IEnumerable]) { return $false }
  if ($RawValue -is [double] -or $RawValue -is [single]) {
    $d = [double]$RawValue
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return $false }
    $OutDouble.Value = $d
    return $true
  }
  $text = [System.Convert]::ToString($RawValue, [System.Globalization.CultureInfo]::InvariantCulture)
  $parsed = 0.0
  if (-not [double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
    return $false
  }
  if ([double]::IsNaN($parsed) -or [double]::IsInfinity($parsed)) { return $false }
  $OutDouble.Value = $parsed
  return $true
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

  foreach ($boolKey in @('AllowKill', 'WslCacheRelease')) {
    if ($raw.ContainsKey($boolKey) -and $raw[$boolKey] -isnot [bool]) {
      return New-WatchdogError -Code 'CONFIG_INVALID' -Message "Config field '$boolKey' must be a boolean (`$true or `$false)." -Hint 'Use $true or $false without quotes in the config file.' -Retryable $true -ExitCode 1
    }
  }

  $intSpecs = [ordered]@{
    VramKillMiB         = @{ Default = $null; Min = 1; Hint = 'See src/Watchdog/config/watchdog.example.psd1.' }
    RamKillPct          = @{ Default = $null; Min = 1; Hint = 'See src/Watchdog/config/watchdog.example.psd1.' }
    TempKillC           = @{ Default = $null; Min = 1; Hint = 'See src/Watchdog/config/watchdog.example.psd1.' }
    IntervalSec         = @{ Default = 2;     Min = 1; Hint = 'See src/Watchdog/config/watchdog.example.psd1.' }
    BreachSamples       = @{ Default = 3;     Min = 1; Hint = 'See src/Watchdog/config/watchdog.example.psd1.' }
    StaleSec            = @{ Default = 15;    Min = 1; Hint = 'See src/Watchdog/config/watchdog.example.psd1.' }
    PollIntervalSec     = @{ Default = 60;    Min = 1; Hint = 'See src/Watchdog/config/watchdog.example.psd1.' }
    WslCacheCooldownSec = @{ Default = 300;   Min = 1; Hint = 'See the WSL cache section of src/Watchdog/config/watchdog.example.psd1.' }
    WslCacheTimeoutSec  = @{ Default = 90;    Min = 1; Hint = 'See the WSL cache section of src/Watchdog/config/watchdog.example.psd1.' }
    WslCacheSettleSec   = @{ Default = 10;    Min = 0; Hint = 'See the WSL cache section of src/Watchdog/config/watchdog.example.psd1.' }
  }
  $ints = @{}
  foreach ($key in $intSpecs.Keys) {
    $spec = $intSpecs[$key]
    $value = if ($raw.ContainsKey($key)) { $raw[$key] } else { $spec.Default }
    $number = 0.0
    if (-not (ConvertTo-WatchdogFiniteDouble -RawValue $value -OutDouble ([ref]$number)) -or
        $number -lt 0 -or $number -gt [int]::MaxValue -or [int]$number -lt $spec.Min) {
      $rule = if ($spec.Min -eq 0) { 'must be a finite non-negative number.' } else { 'must be a finite number that rounds to an integer of at least 1.' }
      return New-WatchdogError -Code 'CONFIG_INVALID' -Message "Config field '$key' $rule" -Hint $spec.Hint -Retryable $true -ExitCode 1
    }
    $ints[$key] = [int]$number
  }

  # WSL file-cache release (opt-in). Defaults are the 2026-11-23 rig values; every field must be a
  # finite positive number when present so a typo cannot silently turn a threshold into 0.
  $wslCacheDefaults = [ordered]@{
    WslCacheHighGB      = 16
    WslCacheMinGB       = 8
    WslCacheWinHighPct  = 80
    WslCacheMinCacheGB  = 6
    WslCacheAlertPct    = 90
  }
  $wslCache = @{}
  foreach ($key in $wslCacheDefaults.Keys) {
    $value = if ($raw.ContainsKey($key)) { $raw[$key] } else { $wslCacheDefaults[$key] }
    $number = 0.0
    if (-not (ConvertTo-WatchdogFiniteDouble -RawValue $value -OutDouble ([ref]$number)) -or $number -le 0) {
      return New-WatchdogError -Code 'CONFIG_INVALID' -Message "Config field '$key' must be a finite positive number." -Hint 'See the WSL cache section of src/Watchdog/config/watchdog.example.psd1.' -Retryable $true -ExitCode 1
    }
    $wslCache[$key] = $number
  }
  if ($wslCache.WslCacheWinHighPct -gt 100 -or $wslCache.WslCacheAlertPct -gt 100) {
    return New-WatchdogError -Code 'CONFIG_INVALID' -Message 'WslCacheWinHighPct and WslCacheAlertPct are percentages and must be at most 100.' -Hint 'See the WSL cache section of src/Watchdog/config/watchdog.example.psd1.' -Retryable $true -ExitCode 1
  }

  [pscustomobject]@{
    Kind            = 'Config'
    ConfigPath      = [System.IO.Path]::GetFullPath($candidate)
    Root            = [System.IO.Path]::GetFullPath($raw.Root)
    Targets         = @($targets)
    VramKillMiB     = $ints.VramKillMiB
    RamKillPct      = $ints.RamKillPct
    TempKillC       = $ints.TempKillC
    IntervalSec     = $ints.IntervalSec
    BreachSamples   = $ints.BreachSamples
    StaleSec        = $ints.StaleSec
    WslDistro       = [string]$(if ($raw.ContainsKey('WslDistro')) { $raw.WslDistro } else { 'Ubuntu' })
    WslKillPattern  = [string]$(if ($raw.ContainsKey('WslKillPattern')) { $raw.WslKillPattern } else { '' })
    AllowKill       = ($raw.ContainsKey('AllowKill') -and $raw.AllowKill)
    PollIntervalSec = $ints.PollIntervalSec
    WslCacheRelease     = ($raw.ContainsKey('WslCacheRelease') -and $raw.WslCacheRelease)
    WslCacheHighGB      = $wslCache.WslCacheHighGB
    WslCacheMinGB       = $wslCache.WslCacheMinGB
    WslCacheWinHighPct  = $wslCache.WslCacheWinHighPct
    WslCacheMinCacheGB  = $wslCache.WslCacheMinCacheGB
    WslCacheAlertPct    = $wslCache.WslCacheAlertPct
    WslCacheCooldownSec = $ints.WslCacheCooldownSec
    WslCacheTimeoutSec  = $ints.WslCacheTimeoutSec
    WslCacheSettleSec   = $ints.WslCacheSettleSec
  }
}
