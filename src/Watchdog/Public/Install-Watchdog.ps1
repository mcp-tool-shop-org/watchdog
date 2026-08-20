function Install-Watchdog {
  <#
  .SYNOPSIS
    Copy the module into the CurrentUser PowerShell module path.
  .DESCRIPTION
    Does not start the loop and does not register the poller unless -Poll is passed.
    Does not overwrite an existing user config.
  #>
  [CmdletBinding()]
  param(
    [string]$ConfigPath,
    [switch]$Poll
  )
  $destRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules\Watchdog'
  if (-not (Test-Path $destRoot)) {
    New-Item -ItemType Directory -Path $destRoot -Force | Out-Null
  }
  Copy-Item -Path (Join-Path $script:WatchdogModuleRoot '*') -Destination $destRoot -Recurse -Force
  Write-Output "installed module to $destRoot"
  Write-Output "next: copy config\watchdog.example.psd1 to ~/.watchdog/config.psd1 and edit Root + Targets + envelope."
  Write-Output "then: Import-Module Watchdog; Start-Watchdog -AllowKill"
  if ($Poll) {
    Register-WatchdogPoll -ConfigPath $ConfigPath
  }
}

function Uninstall-Watchdog {
  <#
  .SYNOPSIS
    Remove the CurrentUser module copy and the poll scheduled task. Does not delete config or telemetry.
  #>
  [CmdletBinding()]
  param()
  Unregister-WatchdogPoll
  $destRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules\Watchdog'
  if (Test-Path $destRoot) {
    Remove-Item $destRoot -Recurse -Force
    Write-Output "removed $destRoot"
  } else {
    Write-Output "no CurrentUser module copy at $destRoot"
  }
  Write-Output "user config and Root telemetry were not deleted."
}
