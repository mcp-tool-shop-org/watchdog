BeforeAll {
  . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'Resolve-WatchdogConfig' {
  It 'fails closed when no config exists (no default Root, no default kill list)' {
    $prev = $env:WATCHDOG_CONFIG
    try {
      $env:WATCHDOG_CONFIG = (Join-Path (Get-WatchdogTestDir 'missing') 'nope.psd1')
      $r = Resolve-WatchdogConfig
      $r.Kind | Should -Be 'Error'
      $r.code | Should -Be 'CONFIG_MISSING'
    } finally {
      $env:WATCHDOG_CONFIG = $prev
    }
  }

  It 'rejects a relative Root' {
    $path = Join-Path $TestDrive 'rel.psd1'
    "@{ Root = 'relative'; Targets = @('C:\\x\\python.exe'); VramKillMiB = 31200; RamKillPct = 90; TempKillC = 87 }" | Set-Content $path
    $r = Resolve-WatchdogConfig -Path $path
    $r.code | Should -Be 'CONFIG_PATH_NOT_ABSOLUTE'
  }

  It 'rejects a relative target path' {
    $path = Join-Path $TestDrive 'relt.psd1'
    "@{ Root = 'C:\\watchdog-state'; Targets = @('venv\\python.exe'); VramKillMiB = 31200; RamKillPct = 90; TempKillC = 87 }" | Set-Content $path
    $r = Resolve-WatchdogConfig -Path $path
    $r.code | Should -Be 'CONFIG_PATH_NOT_ABSOLUTE'
  }

  It 'requires VramKillMiB — no silent 5090 default' {
    $path = Join-Path $TestDrive 'novram.psd1'
    "@{ Root = 'C:\\watchdog-state'; Targets = @('C:\\x\\python.exe'); RamKillPct = 90; TempKillC = 87 }" | Set-Content $path
    $r = Resolve-WatchdogConfig -Path $path
    $r.code | Should -Be 'CONFIG_REQUIRED'
    $r.message | Should -Match 'VramKillMiB'
  }

  It 'loads a written test config' {
    $root = Get-WatchdogTestDir 'cfg-ok'
    $path = New-WatchdogTestConfig -Root $root
    $r = Resolve-WatchdogConfig -Path $path
    $r.Kind | Should -Be 'Config'
    $r.VramKillMiB | Should -Be 31200
    $r.AllowKill | Should -BeFalse
  }

  It 'loads the shipped example as a valid config (placeholder paths are absolute)' {
    $r = Resolve-WatchdogConfig -Path $script:WatchdogExample
    $r.Kind | Should -Be 'Config'
    $r.Root | Should -Match '^[A-Za-z]:\\'
  }
}
