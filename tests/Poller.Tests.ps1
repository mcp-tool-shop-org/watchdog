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

  It 'creates a missing Root containing brackets and uses literal paths for poll logs and sentinels' {
    $parent = Get-WatchdogTestDir ('poll-brackets-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $bracketRoot = Join-Path $parent 'slot[1]'
    $cfgPath = Join-Path $parent 'watchdog.config.psd1'
    @"
@{
  Root = '$($bracketRoot.Replace('\', '\\'))'
  Targets = @('C:\watchdog-test\python.exe')
  VramKillMiB = 31200
  RamKillPct = 90
  TempKillC = 87
}
"@ | Set-Content -LiteralPath $cfgPath
    Test-Path -LiteralPath $bracketRoot | Should -BeFalse

    $hb = Invoke-WatchdogPoll -ConfigPath $cfgPath
    $hb.State | Should -Be 'NOT_RUNNING'
    $LASTEXITCODE | Should -Be 1
    $paths = Get-WatchdogPaths -Root $bracketRoot
    Test-Path -LiteralPath $bracketRoot -PathType Container | Should -BeTrue
    Test-Path -LiteralPath $paths.Dead | Should -BeTrue
    Test-Path -LiteralPath $paths.Kill | Should -BeTrue
    Test-Path -LiteralPath $paths.PollStamp | Should -BeTrue

    'console bracket line' | Set-Content -LiteralPath $paths.Console
    'crash bracket line' | Set-Content -LiteralPath $paths.Crash
    Remove-Item -LiteralPath $paths.Dead -Force
    [void](Invoke-WatchdogPoll -ConfigPath $cfgPath)
    (Get-Content -LiteralPath $paths.Dead -Raw) | Should -Match 'crash: crash bracket line ; console: console bracket line'
    @(Get-Content -LiteralPath $paths.Kill).Count | Should -Be 2
  }

  It 'returns a structured error naming Root when Root cannot be created' {
    $dir = Get-WatchdogTestDir ('poll-badroot-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $fileRoot = Join-Path $dir 'not-a-dir'
    'occupied' | Set-Content -LiteralPath $fileRoot
    $cfgPath = Join-Path $dir 'watchdog.config.psd1'
    @"
@{
  Root = '$($fileRoot.Replace('\', '\\'))'
  Targets = @('C:\watchdog-test\python.exe')
  VramKillMiB = 31200
  RamKillPct = 90
  TempKillC = 87
}
"@ | Set-Content -LiteralPath $cfgPath
    $r = Invoke-WatchdogPoll -ConfigPath $cfgPath 2>$null
    $r.Kind | Should -Be 'Error'
    $r.code | Should -Be 'RUNTIME_ROOT_UNUSABLE'
    $r.message | Should -Match 'Root'
    $r.message | Should -Not -Match 'not-a-dir'
    $LASTEXITCODE | Should -Be 1
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
