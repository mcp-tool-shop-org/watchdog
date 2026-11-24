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
    $r.PollIntervalSec | Should -Be 60
  }

  It 'defaults PollIntervalSec to 60 when omitted' {
    $path = Join-Path $TestDrive 'defpoll.psd1'
    "@{ Root = 'C:\\watchdog-state'; Targets = @('C:\\x\\python.exe'); VramKillMiB = 31200; RamKillPct = 90; TempKillC = 87 }" | Set-Content $path
    $r = Resolve-WatchdogConfig -Path $path
    $r.Kind | Should -Be 'Config'
    $r.PollIntervalSec | Should -Be 60
  }

  It 'refuses NaN and Infinity for core numeric keys' {
    $root = Get-WatchdogTestDir 'cfg-nan'
    $path = New-WatchdogTestConfig -Root $root
    foreach ($key in @('VramKillMiB', 'RamKillPct', 'TempKillC', 'IntervalSec', 'BreachSamples', 'StaleSec', 'PollIntervalSec')) {
      foreach ($bad in @([double]::NaN, [double]::PositiveInfinity, [double]::NegativeInfinity, 'NaN', 'Infinity', '-Infinity')) {
        $r = Resolve-WatchdogConfig -Path $path -Override @{ $key = $bad }
        $r.code | Should -Be 'CONFIG_INVALID'
        $r.message | Should -Match $key
      }
    }
  }

  It 'refuses zero and sub-1 fractions that round to zero for core integer keys' {
    $root = Get-WatchdogTestDir 'cfg-round0'
    $path = New-WatchdogTestConfig -Root $root
    foreach ($key in @('VramKillMiB', 'RamKillPct', 'TempKillC', 'IntervalSec', 'BreachSamples', 'StaleSec', 'PollIntervalSec')) {
      foreach ($bad in @(0, 0.4, 0.5)) {
        $r = Resolve-WatchdogConfig -Path $path -Override @{ $key = $bad }
        $r.code | Should -Be 'CONFIG_INVALID'
        $r.message | Should -Match $key
      }
    }
  }

  It 'accepts only real booleans for AllowKill (refusing quoted strings, integers, and null)' {
    $root = Get-WatchdogTestDir 'cfg-allowkill'
    $path = New-WatchdogTestConfig -Root $root
    (Resolve-WatchdogConfig -Path $path -Override @{ AllowKill = $true }).AllowKill | Should -BeTrue
    (Resolve-WatchdogConfig -Path $path -Override @{ AllowKill = $false }).AllowKill | Should -BeFalse
    foreach ($bad in @('false', 'true', 0, 1, $null, 'sk-test-0123456789abcdef')) {
      $r = Resolve-WatchdogConfig -Path $path -Override @{ AllowKill = $bad }
      $r.code | Should -Be 'CONFIG_INVALID'
      $r.message | Should -Be 'Config field ''AllowKill'' must be a boolean ($true or $false).'
      $r.message | Should -Not -Match 'sk-test-0123456789abcdef'
    }
  }

  It 'refuses booleans, null, and arrays on numeric config keys' {
    $root = Get-WatchdogTestDir 'cfg-types'
    $path = New-WatchdogTestConfig -Root $root
    foreach ($key in @('IntervalSec', 'WslCacheHighGB')) {
      foreach ($bad in @($true, $false, $null, @(1, 2))) {
        $r = Resolve-WatchdogConfig -Path $path -Override @{ $key = $bad }
        $r.code | Should -Be 'CONFIG_INVALID'
        $r.message | Should -Match $key
      }
    }
  }

  It 'never echoes input values in config refusal messages or error stderr output' {
    $root = Get-WatchdogTestDir 'cfg-noecho'
    $path = New-WatchdogTestConfig -Root $root
    $secret = 'sk-test-0123456789abcdef'
    foreach ($key in @('VramKillMiB', 'IntervalSec', 'AllowKill', 'WslCacheHighGB', 'WslCacheCooldownSec', 'WslCacheRelease')) {
      $r = Resolve-WatchdogConfig -Path $path -Override @{ $key = $secret }
      $r.code | Should -Be 'CONFIG_INVALID'
      $r.message | Should -Match $key
      ($r | ConvertTo-Json -Compress) | Should -Not -Match ([regex]::Escape($secret))
      $prevErr = [Console]::Error
      try {
        $sw = [System.IO.StringWriter]::new()
        [Console]::SetError($sw)
        Write-WatchdogError -ErrorObject $r -IncludeStack
        $sw.ToString() | Should -Not -Match ([regex]::Escape($secret))
      } finally {
        [Console]::SetError($prevErr)
      }
    }
  }
}
