BeforeAll {
  . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'watchdog CLI' {
  It 'prints help and exits 0' {
    $r = & pwsh -NoProfile -File (Join-Path $script:WatchdogModule 'watchdog.ps1') help
    $LASTEXITCODE | Should -Be 0
    ($r -join "`n") | Should -Match 'watchdog status'
  }

  It 'prints version 1.0.0' {
    $r = & pwsh -NoProfile -File (Join-Path $script:WatchdogModule 'watchdog.ps1') version
    $LASTEXITCODE | Should -Be 0
    ($r | Select-Object -Last 1) | Should -Be '1.0.0'
  }

  It 'rejects an unknown command with a structured error' {
    $r = & pwsh -NoProfile -File (Join-Path $script:WatchdogModule 'watchdog.ps1') explode 2>&1
    $LASTEXITCODE | Should -Be 1
    ($r | Out-String) | Should -Match 'INPUT_UNKNOWN_COMMAND'
  }

  It 'status without config fails closed' {
    $cli = Join-Path $script:WatchdogModule 'watchdog.ps1'
    $r = & pwsh -NoProfile -File $cli status -ConfigPath 'C:\watchdog-ci-missing\nope.psd1' 2>&1
    $LASTEXITCODE | Should -Be 1
    ($r | Out-String) | Should -Match 'CONFIG_MISSING'
  }
}
