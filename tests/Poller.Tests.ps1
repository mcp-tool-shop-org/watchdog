BeforeAll {
  . (Join-Path $PSScriptRoot 'Helpers.ps1')
  Import-Module (Join-Path $script:WatchdogModule 'Watchdog.psd1') -Force
}

Describe 'Invoke-WatchdogPoll (W-03)' {
  It 'writes _watchdog_DEAD from the outside when the heartbeat is stale' {
    $root = Get-WatchdogTestDir 'poll-stale'
    $cfgPath = New-WatchdogTestConfig -Root $root
    $paths = Get-WatchdogPaths -Root $root
    [DateTimeOffset]::UtcNow.AddMinutes(-9).ToString('yyyy-MM-ddTHH:mm:ss.fffZ') | Set-Content $paths.Heartbeat
    'console died here' | Set-Content $paths.Console
    $hb = Invoke-WatchdogPoll -ConfigPath $cfgPath
    $hb.State | Should -Be 'STALE'
    Test-Path $paths.Dead | Should -BeTrue
    (Get-Content $paths.Dead -Raw) | Should -Match 'poller declared STALE'
    (Get-Content $paths.Dead -Raw) | Should -Match 'console died here'
    $LASTEXITCODE | Should -Be 2
  }

  It 'does not overwrite a loop-written DEAD file' {
    $root = Get-WatchdogTestDir 'poll-keep'
    $cfgPath = New-WatchdogTestConfig -Root $root
    $paths = Get-WatchdogPaths -Root $root
    'loop died: something specific' | Set-Content $paths.Dead
    Invoke-WatchdogPoll -ConfigPath $cfgPath
    (Get-Content $paths.Dead -Raw).Trim() | Should -Be 'loop died: something specific'
  }

  It 'is a no-op write when the heartbeat is fresh' {
    $root = Get-WatchdogTestDir 'poll-fresh'
    $cfgPath = New-WatchdogTestConfig -Root $root
    $paths = Get-WatchdogPaths -Root $root
    Get-WatchdogTimestamp | Set-Content $paths.Heartbeat
    Invoke-WatchdogPoll -ConfigPath $cfgPath
    Test-Path $paths.Dead | Should -BeFalse
    $LASTEXITCODE | Should -Be 0
  }
}

Describe 'Start-Watchdog consent' {
  It 'refuses to start without -AllowKill (the gate that must be able to fire)' {
    $root = Get-WatchdogTestDir 'nokill'
    $cfgPath = New-WatchdogTestConfig -Root $root -AllowKill $false
    Start-Watchdog -ConfigPath $cfgPath
    $LASTEXITCODE | Should -Be 1
    Test-Path (Join-Path $root '_watchdog_HEARTBEAT') | Should -BeFalse
  }
}

Describe 'Get-WatchdogPaths' {
  It 'keeps every artifact under Root (A6)' {
    $root = 'C:\watchdog-state'
    $p = Get-WatchdogPaths -Root $root
    foreach ($leaf in @($p.Csv, $p.Kill, $p.Trip, $p.Stop, $p.Heartbeat, $p.Dead, $p.NoTarget, $p.Console, $p.Crash)) {
      Test-WatchdogPathUnderRoot -Root $root -Path $leaf | Should -BeTrue
    }
  }
}
