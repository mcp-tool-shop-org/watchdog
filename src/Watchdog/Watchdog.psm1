$script:WatchdogModuleRoot = $PSScriptRoot

Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private\*.ps1') | ForEach-Object { . $_.FullName }
Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public\*.ps1') | ForEach-Object { . $_.FullName }

Export-ModuleMember -Function @(
  'Get-WatchdogStatus',
  'Start-Watchdog',
  'Stop-Watchdog',
  'Install-Watchdog',
  'Uninstall-Watchdog',
  'Register-WatchdogPoll',
  'Unregister-WatchdogPoll',
  'Get-WatchdogConfig',
  'Invoke-WatchdogPoll'
)
