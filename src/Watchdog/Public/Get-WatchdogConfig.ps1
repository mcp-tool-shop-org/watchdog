function Get-WatchdogConfig {
  <#
  .SYNOPSIS
    Load and validate a watchdog config file.
  .PARAMETER ConfigPath
    Path to a PowerShell data file. Falls back to $env:WATCHDOG_CONFIG, ./watchdog.config.psd1, ~/.watchdog/config.psd1.
  #>
  [CmdletBinding()]
  param(
    [string]$ConfigPath
  )
  $cfg = Resolve-WatchdogConfig -Path $ConfigPath
  if (Test-WatchdogError $cfg) {
    Write-WatchdogError -ErrorObject $cfg
    $global:LASTEXITCODE = $cfg.exitCode
    return $cfg
  }
  $cfg
}
