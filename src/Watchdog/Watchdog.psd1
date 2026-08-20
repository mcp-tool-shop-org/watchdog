@{
  RootModule           = 'Watchdog.psm1'
  ModuleVersion        = '1.0.0'
  GUID                 = '2c4f3e40-c63e-4083-b5b2-ae9e9247cca4'
  Author               = 'MCP Tool Shop'
  CompanyName          = 'MCP Tool Shop'
  Copyright            = '(c) 2026 MCP Tool Shop'
  Description          = 'Windows VRAM/RAM/temp watchdog for NVIDIA GPUs. Kills guarded interpreters on a sustained breach.'
  PowerShellVersion    = '7.0'
  CompatiblePSEditions = @('Core')
  FunctionsToExport    = @(
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
  CmdletsToExport      = @()
  VariablesToExport    = @()
  AliasesToExport      = @()
  PrivateData          = @{
    PSData = @{
      Tags         = @('watchdog', 'gpu', 'nvidia', 'vram', 'windows')
      LicenseUri   = 'https://github.com/mcp-tool-shop-org/watchdog/blob/main/LICENSE'
      ProjectUri   = 'https://github.com/mcp-tool-shop-org/watchdog'
      ReleaseNotes = 'https://github.com/mcp-tool-shop-org/watchdog/blob/main/CHANGELOG.md'
    }
  }
}
