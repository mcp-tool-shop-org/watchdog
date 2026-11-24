BeforeAll {
  . (Join-Path $PSScriptRoot 'Helpers.ps1')
  Import-Module (Join-Path $script:WatchdogModule 'Watchdog.psd1') -Force

  function New-CacheCfg {
    param([bool]$Enabled = $true, [int]$CooldownSec = 300)
    [pscustomobject]@{
      WslCacheRelease     = $Enabled
      WslDistro           = 'Ubuntu'
      WslCacheHighGB      = 16
      WslCacheMinGB       = 8
      WslCacheWinHighPct  = 80
      WslCacheMinCacheGB  = 6
      WslCacheAlertPct    = 90
      WslCacheCooldownSec = $CooldownSec
      WslCacheTimeoutSec  = 90
      WslCacheSettleSec   = 0
    }
  }

  $script:distroUp = { param($Distro) $true }

  function New-HostReader([object[]]$States) {
    $script:hostStates = [System.Collections.Generic.Queue[object]]::new()
    foreach ($s in $States) { $script:hostStates.Enqueue($s) }
    return { $script:hostStates.Dequeue() }
  }

  function New-HostState([double]$WinUsedPct, [double]$WslGB, [bool]$WslUp = $true) {
    [pscustomobject]@{ WinUsedPct = $WinUsedPct; WinFreeGB = 64 * (100 - $WinUsedPct) / 100; WslGB = $WslGB; WslUp = $WslUp }
  }

  function New-WslRecorder([double]$CacheGB, [switch]$Throw) {
    $script:wslCalls = [System.Collections.Generic.List[string]]::new()
    $script:wslCacheKB = [long]($CacheGB * 1MB)
    $script:wslThrow = [bool]$Throw
    return {
      param($Distro, $Command, $TimeoutSec)
      $script:wslCalls.Add($Command)
      if ($script:wslThrow) { throw 'wsl.exe timed out after 90 s' }
      if ($Command -like 'grep*') { return "Buffers:          0 kB`nCached:    $($script:wslCacheKB) kB`n" }
      return ''
    }
  }
}

Describe 'Test-WslCacheReleaseNeeded' {
  It 'is disabled unless the config opts in' {
    Test-WslCacheReleaseNeeded -Cfg (New-CacheCfg -Enabled $false) -WslGB 27 -WinUsedPct 95 -WslUp $true | Should -Be 'disabled'
  }
  It 'never acts on a WSL VM that is not running' {
    Test-WslCacheReleaseNeeded -Cfg (New-CacheCfg) -WslGB 0 -WinUsedPct 95 -WslUp $false | Should -Be 'wsl-not-running'
  }
  It 'acts when the VM reaches the high mark, inclusive' {
    Test-WslCacheReleaseNeeded -Cfg (New-CacheCfg) -WslGB 16 -WinUsedPct 10 -WslUp $true | Should -Be 'act'
  }
  It 'acts on a mid-size VM only when Windows is under pressure' {
    Test-WslCacheReleaseNeeded -Cfg (New-CacheCfg) -WslGB 8 -WinUsedPct 80 -WslUp $true | Should -Be 'act'
    Test-WslCacheReleaseNeeded -Cfg (New-CacheCfg) -WslGB 8 -WinUsedPct 79.9 -WslUp $true | Should -Be 'below-threshold'
    Test-WslCacheReleaseNeeded -Cfg (New-CacheCfg) -WslGB 7.9 -WinUsedPct 95 -WslUp $true | Should -Be 'below-threshold'
  }
}

Describe 'ConvertFrom-WslMeminfoCache' {
  It 'sums Buffers and Cached in GB and ignores other lines' {
    $text = "MemTotal:       28734976 kB`nBuffers:          1048576 kB`nCached:          5242880 kB`nSwapCached:            0 kB`n"
    ConvertFrom-WslMeminfoCache $text | Should -Be 6
  }
}

Describe 'Invoke-WslCacheRelease' {
  BeforeEach {
    $root = Get-WatchdogTestDir ('wslcache-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $script:paths = Get-WatchdogPaths -Root $root
  }

  It 'drops the page cache when the VM is large and the cache is big, then logs before and after' {
    $read = New-HostReader @((New-HostState 81 24.6), (New-HostState 52 6.4))
    $run = New-WslRecorder -CacheGB 27
    $r = Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost $read -RunWsl $run -DistroRunning $script:distroUp
    $r.Action | Should -Be 'dropped'
    $script:wslCalls.Count | Should -Be 2
    $script:wslCalls[1] | Should -Be 'sync; echo 1 > /proc/sys/vm/drop_caches'
    Test-Path $script:paths.WslCacheLast | Should -BeTrue
    $log = Get-Content $script:paths.WslCacheLog -Raw
    $log | Should -Match 'heartbeat win_used=81%'
    $log | Should -Match 'DROPPED linux cache 27.0GB'
    $log | Should -Not -Match 'ALERT'
  }

  It 'leaves a small cache alone and calls WSL only to read it' {
    $read = New-HostReader @((New-HostState 85 17))
    $run = New-WslRecorder -CacheGB 2
    (Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost $read -RunWsl $run -DistroRunning $script:distroUp).Action | Should -Be 'cache-small'
    $script:wslCalls.Count | Should -Be 1
    Test-Path $script:paths.WslCacheLast | Should -BeFalse
    Get-Content $script:paths.WslCacheLog -Raw | Should -Match 'no drop: linux cache 2.0GB below 6GB'
  }

  It 'does not call WSL at all below the thresholds or when WSL is stopped' {
    $run = New-WslRecorder -CacheGB 27
    (Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 50 4))) -RunWsl $run).Action | Should -Be 'below-threshold'
    (Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 95 0 $false))) -RunWsl $run).Action | Should -Be 'wsl-not-running'
    $script:wslCalls.Count | Should -Be 0
  }

  It 'waits out the cooldown after a drop' {
    (Get-Date).AddSeconds(-60).ToString('o') | Set-Content $script:paths.WslCacheLast
    $run = New-WslRecorder -CacheGB 27
    (Invoke-WslCacheRelease -Cfg (New-CacheCfg -CooldownSec 300) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 81 24))) -RunWsl $run).Action | Should -Be 'cooldown'
    $script:wslCalls.Count | Should -Be 0
  }

  It 'acts again once the cooldown has passed' {
    (Get-Date).AddSeconds(-600).ToString('o') | Set-Content $script:paths.WslCacheLast
    $run = New-WslRecorder -CacheGB 27
    $read = New-HostReader @((New-HostState 81 24), (New-HostState 60 8))
    (Invoke-WslCacheRelease -Cfg (New-CacheCfg -CooldownSec 300) -Paths $script:paths -ReadHost $read -RunWsl $run -DistroRunning $script:distroUp).Action | Should -Be 'dropped'
  }

  It 'never starts a stopped distro: it skips without calling WSL and logs one line per run of skips' {
    $run = New-WslRecorder -CacheGB 27
    $down = { param($Distro) $false }
    $now = Get-Date '2026-11-23T22:10:00'
    foreach ($i in 1..3) {
      (Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 81 24.6))) -RunWsl $run -DistroRunning $down -Now $now).Action | Should -Be 'distro-not-running'
    }
    $script:wslCalls.Count | Should -Be 0
    Test-Path $script:paths.WslCacheLast | Should -BeFalse
    $skips = { @(Get-Content $script:paths.WslCacheLog | Where-Object { $_ -match "skip: distro 'Ubuntu' is not running, and a cache drop never starts it; win_used=81%" }).Count }
    & $skips | Should -Be 1
    # The next hour's heartbeat ends the run, so a long run logs at most one skip line an hour.
    [void](Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 81 24.6))) -RunWsl $run -DistroRunning $down -Now $now.AddHours(1))
    & $skips | Should -Be 2
    $script:wslCalls.Count | Should -Be 0
  }

  It 'asks about the configured distro by default, bounded by WslCacheTimeoutSec' {
    # Helpers.ps1 dot-sources Private/*.ps1, so this Invoke-WslCacheRelease resolves its helpers in the test scope.
    Mock Test-WslDistroRunning { $false }
    $run = New-WslRecorder -CacheGB 27
    (Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 81 24.6))) -RunWsl $run).Action | Should -Be 'distro-not-running'
    Should -Invoke Test-WslDistroRunning -Times 1 -Exactly -ParameterFilter { $Distro -eq 'Ubuntu' -and $TimeoutSec -eq 90 }
    $script:wslCalls.Count | Should -Be 0
  }

  It 'treats a hung running-distro check as an error: logged, and nothing is dropped' {
    $run = New-WslRecorder -CacheGB 27
    $hung = { param($Distro, $TimeoutSec) throw "wsl.exe timed out after $TimeoutSec s" }
    $r = Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 81 24.6))) -RunWsl $run -DistroRunning $hung
    $r.Action | Should -Be 'error'
    $script:wslCalls.Count | Should -Be 0
    Test-Path $script:paths.WslCacheLast | Should -BeFalse
    Get-Content $script:paths.WslCacheLog -Raw | Should -Match 'ERROR wsl.exe timed out after 90 s'
  }

  It 'logs an alert with the top processes when Windows is still high after the drop' {
    $read = New-HostReader @((New-HostState 95 20), (New-HostState 93 6))
    $run = New-WslRecorder -CacheGB 14
    $top = { @('chrome 9.0GB', 'claude 6.0GB') }
    (Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost $read -RunWsl $run -TopProcesses $top -DistroRunning $script:distroUp).Action | Should -Be 'dropped'
    Get-Content $script:paths.WslCacheLog -Raw | Should -Match 'ALERT windows still 93% used after the drop; top: chrome 9.0GB, claude 6.0GB'
  }

  It 'never throws: a WSL timeout is logged and returned as an error' {
    $run = New-WslRecorder -CacheGB 27 -Throw
    { $script:r = Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 81 24))) -RunWsl $run -DistroRunning $script:distroUp } | Should -Not -Throw
    $script:r.Action | Should -Be 'error'
    Get-Content $script:paths.WslCacheLog -Raw | Should -Match 'ERROR wsl.exe timed out'
  }

  It 'writes one heartbeat per clock hour' {
    $run = New-WslRecorder -CacheGB 1
    $now = Get-Date '2026-11-23T22:10:00'
    foreach ($i in 1..3) {
      [void](Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 50 4))) -RunWsl $run -Now $now)
    }
    @(Get-Content $script:paths.WslCacheLog | Where-Object { $_ -match 'heartbeat' }).Count | Should -Be 1
    [void](Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 50 4))) -RunWsl $run -Now $now.AddHours(1))
    @(Get-Content $script:paths.WslCacheLog | Where-Object { $_ -match 'heartbeat' }).Count | Should -Be 2
  }

  It 'writes nothing when disabled' {
    $run = New-WslRecorder -CacheGB 27
    (Invoke-WslCacheRelease -Cfg (New-CacheCfg -Enabled $false) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 95 27))) -RunWsl $run).Action | Should -Be 'disabled'
    Test-Path $script:paths.WslCacheLog | Should -BeFalse
  }

  It 'rotates the log past 1 MB' {
    Set-Content -LiteralPath $script:paths.WslCacheLog -Value ('x' * 1100KB)
    Write-WslCacheLog $script:paths.WslCacheLog 'after rotation'
    Test-Path ($script:paths.WslCacheLog + '.1') | Should -BeTrue
    (Get-Content $script:paths.WslCacheLog -Raw) | Should -Match 'after rotation'
  }

  It 'logs an error and still never throws when writing WslCacheHeartbeat fails under ErrorAction Continue' {
    $prevEap = $ErrorActionPreference
    $now = Get-Date '2026-11-24T12:00:00'
    Set-Content -LiteralPath $script:paths.WslCacheHeartbeat -Value '2020010100'
    [IO.File]::SetAttributes($script:paths.WslCacheHeartbeat, [IO.FileAttributes]::ReadOnly)
    try {
      $ErrorActionPreference = 'Continue'
      $run = New-WslRecorder -CacheGB 1
      { $script:r = Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost (New-HostReader @((New-HostState 50 4))) -RunWsl $run -Now $now } | Should -Not -Throw
      $script:r.Action | Should -Be 'error'
      Get-Content $script:paths.WslCacheLog -Raw | Should -Match 'ERROR '
    } finally {
      $ErrorActionPreference = $prevEap
      [IO.File]::SetAttributes($script:paths.WslCacheHeartbeat, [IO.FileAttributes]::Normal)
    }
  }

  It 'logs an error, preserves both WSL calls, and never throws when writing WslCacheLast fails under ErrorAction Continue' {
    $prevEap = $ErrorActionPreference
    $now = Get-Date '2026-11-24T12:00:00'
    Set-Content -LiteralPath $script:paths.WslCacheHeartbeat -Value $now.ToString('yyyyMMddHH')
    Set-Content -LiteralPath $script:paths.WslCacheLast -Value $now.AddHours(-2).ToString('o')
    [IO.File]::SetAttributes($script:paths.WslCacheLast, [IO.FileAttributes]::ReadOnly)
    try {
      $ErrorActionPreference = 'Continue'
      $read = New-HostReader @((New-HostState 81 24.6), (New-HostState 52 6.4))
      $run = New-WslRecorder -CacheGB 27
      { $script:r = Invoke-WslCacheRelease -Cfg (New-CacheCfg) -Paths $script:paths -ReadHost $read -RunWsl $run -DistroRunning $script:distroUp -Now $now } | Should -Not -Throw
      $script:r.Action | Should -Be 'error'
      $script:wslCalls.Count | Should -Be 2
      $log = Get-Content $script:paths.WslCacheLog -Raw
      $log | Should -Match 'ERROR '
      $log | Should -Not -Match 'DROPPED'
    } finally {
      $ErrorActionPreference = $prevEap
      [IO.File]::SetAttributes($script:paths.WslCacheLast, [IO.FileAttributes]::Normal)
    }
  }
}

Describe 'Test-WslDistroRunning' {
  BeforeEach {
    # Pester 6: a filtered mock needs a default one, or the real wsl.exe would run.
    Mock Invoke-ProcessWithTimeout { throw 'unexpected process' }
  }

  It 'finds the distro in the listing as wsl.exe prints it (read on the rig, NULs stripped)' {
    Mock Invoke-ProcessWithTimeout { [pscustomobject]@{ ExitCode = 0; Out = "Ubuntu`r`ndocker-desktop`r`n"; StreamsDrained = $true } } -ParameterFilter { $FileName -eq 'wsl.exe' -and $Arguments -eq '-l --running -q' -and $PassThru }
    Test-WslDistroRunning -Distro 'Ubuntu' -TimeoutSec 5 | Should -BeTrue
    Test-WslDistroRunning -Distro 'docker-desktop' -TimeoutSec 5 | Should -BeTrue
    Test-WslDistroRunning -Distro 'Debian' -TimeoutSec 5 | Should -BeFalse
    Should -Invoke Invoke-ProcessWithTimeout -Times 3 -Exactly -ParameterFilter { $Arguments -eq '-l --running -q' -and $TimeoutSec -eq 5 -and $StreamDrainMs -eq 5000 }
  }

  It 'counts a non-zero exit as not running' {
    Mock Invoke-ProcessWithTimeout { [pscustomobject]@{ ExitCode = 1; Out = "Ubuntu`r`n"; StreamsDrained = $true } } -ParameterFilter { $Arguments -eq '-l --running -q' }
    Test-WslDistroRunning -Distro 'Ubuntu' | Should -BeFalse
  }

  It 'counts an undrained listing as not running and forwards -StreamDrainMs' {
    Mock Invoke-ProcessWithTimeout { [pscustomobject]@{ ExitCode = 0; Out = "Ubuntu`r`n"; StreamsDrained = $false } } -ParameterFilter { $Arguments -eq '-l --running -q' }
    Test-WslDistroRunning -Distro 'Ubuntu' -TimeoutSec 4 -StreamDrainMs 1000 | Should -BeFalse
    Should -Invoke Invoke-ProcessWithTimeout -Times 1 -Exactly -ParameterFilter { $TimeoutSec -eq 4 -and $StreamDrainMs -eq 1000 }
  }

  It 'lets a timeout through, so the release logs it as an error' {
    Mock Invoke-ProcessWithTimeout { throw 'wsl.exe timed out after 5 s' } -ParameterFilter { $Arguments -eq '-l --running -q' }
    { Test-WslDistroRunning -Distro 'Ubuntu' -TimeoutSec 5 } | Should -Throw '*timed out after 5 s*'
  }
}

Describe 'WSL cache config' {
  It 'is off by default, with the documented thresholds' {
    $root = Get-WatchdogTestDir 'wslcache-defaults'
    $cfg = Resolve-WatchdogConfig -Path (New-WatchdogTestConfig -Root $root)
    $cfg.WslCacheRelease | Should -BeFalse
    $cfg.WslCacheHighGB | Should -Be 16
    $cfg.WslCacheMinGB | Should -Be 8
    $cfg.WslCacheWinHighPct | Should -Be 80
    $cfg.WslCacheMinCacheGB | Should -Be 6
    $cfg.WslCacheAlertPct | Should -Be 90
    $cfg.WslCacheCooldownSec | Should -Be 300
    $cfg.WslCacheTimeoutSec | Should -Be 90
    $cfg.WslCacheSettleSec | Should -Be 10
  }

  It 'refuses a threshold that is zero or not a number' {
    $root = Get-WatchdogTestDir 'wslcache-bad'
    $path = New-WatchdogTestConfig -Root $root
    $r = Resolve-WatchdogConfig -Path $path -Override @{ WslCacheRelease = $true; WslCacheHighGB = 0 }
    $r.code | Should -Be 'CONFIG_INVALID'
    $r = Resolve-WatchdogConfig -Path $path -Override @{ WslCacheMinCacheGB = 'six' }
    $r.code | Should -Be 'CONFIG_INVALID'
  }

  It 'refuses a percentage above 100' {
    $root = Get-WatchdogTestDir 'wslcache-pct'
    $r = Resolve-WatchdogConfig -Path (New-WatchdogTestConfig -Root $root) -Override @{ WslCacheAlertPct = 150 }
    $r.code | Should -Be 'CONFIG_INVALID'
  }

  It 'accepts only real booleans for WslCacheRelease (rejecting quoted strings like false)' {
    $root = Get-WatchdogTestDir 'wslcache-bool'
    $path = New-WatchdogTestConfig -Root $root
    (Resolve-WatchdogConfig -Path $path -Override @{ WslCacheRelease = $true }).WslCacheRelease | Should -BeTrue
    (Resolve-WatchdogConfig -Path $path -Override @{ WslCacheRelease = $false }).WslCacheRelease | Should -BeFalse
    foreach ($bad in @('false', 'true', 1, 'sk-test-0123456789abcdef')) {
      $r = Resolve-WatchdogConfig -Path $path -Override @{ WslCacheRelease = $bad }
      $r.code | Should -Be 'CONFIG_INVALID'
      $r.message | Should -Be 'Config field ''WslCacheRelease'' must be a boolean ($true or $false).'
      $r.message | Should -Not -Match 'sk-test-0123456789abcdef'
    }
  }

  It 'refuses NaN and Infinity for numeric WSL cache keys' {
    $root = Get-WatchdogTestDir 'wslcache-nan'
    $path = New-WatchdogTestConfig -Root $root
    foreach ($key in @('WslCacheHighGB', 'WslCacheCooldownSec', 'WslCacheSettleSec')) {
      foreach ($bad in @([double]::NaN, [double]::PositiveInfinity, [double]::NegativeInfinity, 'NaN', 'Infinity', '-Infinity')) {
        $r = Resolve-WatchdogConfig -Path $path -Override @{ $key = $bad }
        $r.code | Should -Be 'CONFIG_INVALID'
        $r.message | Should -Match $key
      }
    }
  }

  It 'refuses sub-1 values that round to zero on integer WSL cache keys while allowing WslCacheSettleSec 0' {
    $root = Get-WatchdogTestDir 'wslcache-round0'
    $path = New-WatchdogTestConfig -Root $root
    foreach ($key in @('WslCacheCooldownSec', 'WslCacheTimeoutSec')) {
      foreach ($bad in @(0.4, 0.5)) {
        $r = Resolve-WatchdogConfig -Path $path -Override @{ $key = $bad }
        $r.code | Should -Be 'CONFIG_INVALID'
        $r.message | Should -Match $key
      }
    }
    (Resolve-WatchdogConfig -Path $path -Override @{ WslCacheSettleSec = 0 }).WslCacheSettleSec | Should -Be 0
    foreach ($bad in @(-1, -0.4)) {
      $r = Resolve-WatchdogConfig -Path $path -Override @{ WslCacheSettleSec = $bad }
      $r.code | Should -Be 'CONFIG_INVALID'
      $r.message | Should -Match 'WslCacheSettleSec'
    }
  }

  It 'keeps the new files under Root' {
    $p = Get-WatchdogPaths -Root 'C:\watchdog-state'
    foreach ($leaf in @($p.WslCacheLog, $p.WslCacheLast, $p.WslCacheHeartbeat, $p.PollStamp)) {
      Test-WatchdogPathUnderRoot -Root 'C:\watchdog-state' -Path $leaf | Should -BeTrue
    }
  }
}

Describe 'Invoke-WatchdogPoll with WSL cache release' {
  It 'runs the release check when enabled and still reports liveness' {
    $root = Get-WatchdogTestDir 'poll-wslcache'
    $cfgPath = New-WatchdogTestConfig -Root $root
    $text = (Get-Content $cfgPath -Raw).TrimEnd()
    Set-Content -Path $cfgPath -Value ($text.Substring(0, $text.Length - 1) + "  WslCacheRelease = `$true`n}`n")
    $paths = Get-WatchdogPaths -Root $root
    Get-WatchdogTimestamp | Set-Content $paths.Heartbeat
    Mock -ModuleName Watchdog Invoke-WslCacheRelease { [pscustomobject]@{ Action = 'below-threshold' } }
    Invoke-WatchdogPoll -ConfigPath $cfgPath
    Should -Invoke -ModuleName Watchdog Invoke-WslCacheRelease -Times 1 -Exactly
    $LASTEXITCODE | Should -Be 0
  }

  It 'runs the release after the liveness check, and the exit code is the liveness one' {
    $root = Get-WatchdogTestDir 'poll-wslcache-order'
    $cfgPath = New-WatchdogTestConfig -Root $root
    $text = (Get-Content $cfgPath -Raw).TrimEnd()
    Set-Content -Path $cfgPath -Value ($text.Substring(0, $text.Length - 1) + "  WslCacheRelease = `$true`n}`n")
    # No heartbeat file: the loop is not running, so this poll writes DEAD before the release runs.
    Mock -ModuleName Watchdog Invoke-WslCacheRelease {
      $global:WatchdogTestDeadBeforeRelease = Test-Path -LiteralPath $Paths.Dead
      $global:WatchdogTestStampBeforeRelease = Test-Path -LiteralPath $Paths.PollStamp
      $global:LASTEXITCODE = 99
      [pscustomobject]@{ Action = 'error' }
    }
    [void](Invoke-WatchdogPoll -ConfigPath $cfgPath)
    $global:WatchdogTestDeadBeforeRelease | Should -BeTrue
    $global:WatchdogTestStampBeforeRelease | Should -BeTrue
    $LASTEXITCODE | Should -Be 1
    Remove-Variable -Name WatchdogTestDeadBeforeRelease, WatchdogTestStampBeforeRelease -Scope Global
  }

  It 'writes a fresh stamp with its state and exit code on every run' {
    $root = Get-WatchdogTestDir 'poll-stamp'
    $cfgPath = New-WatchdogTestConfig -Root $root
    $paths = Get-WatchdogPaths -Root $root
    $before = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    [void](Invoke-WatchdogPoll -ConfigPath $cfgPath)
    $after = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $doc = Get-Content -LiteralPath $paths.PollStamp -Raw | ConvertFrom-Json
    $doc.state | Should -Be 'NOT_RUNNING'
    $doc.exit | Should -Be 1
    [int64]$doc.utc_ms | Should -BeGreaterOrEqual $before
    [int64]$doc.utc_ms | Should -BeLessOrEqual $after
    [int64]$doc.started_ms | Should -BeGreaterOrEqual $before
    [int64]$doc.started_ms | Should -BeLessOrEqual ([int64]$doc.utc_ms)
  }

  It 'writes the registration token into the stamp only when the task passes one' {
    $root = Get-WatchdogTestDir 'poll-stamp-token'
    $cfgPath = New-WatchdogTestConfig -Root $root
    $paths = Get-WatchdogPaths -Root $root
    [void](Invoke-WatchdogPoll -ConfigPath $cfgPath -RegistrationToken '0123456789abcdef0123456789abcdef')
    (Get-Content -LiteralPath $paths.PollStamp -Raw | ConvertFrom-Json).token | Should -BeExactly '0123456789abcdef0123456789abcdef'
    [void](Invoke-WatchdogPoll -ConfigPath $cfgPath)
    (Get-Content -LiteralPath $paths.PollStamp -Raw | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'token'
  }

  It 'still reports liveness when the stamp cannot be written' {
    $root = Get-WatchdogTestDir 'poll-stamp-blocked'
    $cfgPath = New-WatchdogTestConfig -Root $root
    $paths = Get-WatchdogPaths -Root $root
    New-Item -ItemType Directory -Path $paths.PollStamp -Force | Out-Null
    Get-WatchdogTimestamp | Set-Content $paths.Heartbeat
    { Invoke-WatchdogPoll -ConfigPath $cfgPath } | Should -Not -Throw
    $LASTEXITCODE | Should -Be 0
  }

  It 'does not run the release check when disabled' {
    $root = Get-WatchdogTestDir 'poll-wslcache-off'
    $cfgPath = New-WatchdogTestConfig -Root $root
    $paths = Get-WatchdogPaths -Root $root
    Get-WatchdogTimestamp | Set-Content $paths.Heartbeat
    Mock -ModuleName Watchdog Invoke-WslCacheRelease { [pscustomobject]@{ Action = 'dropped' } }
    Invoke-WatchdogPoll -ConfigPath $cfgPath
    Should -Invoke -ModuleName Watchdog Invoke-WslCacheRelease -Times 0 -Exactly
  }
}
