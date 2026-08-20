BeforeAll {
  . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'Get-WatchdogHeartbeatState' {
  It 'is NOT_RUNNING when the heartbeat file is missing' {
    $dir = Join-Path $TestDrive 'hb-missing'
    New-Item -ItemType Directory $dir | Out-Null
    $s = Get-WatchdogHeartbeatState -Path (Join-Path $dir '_watchdog_HEARTBEAT') -StaleSec 15
    $s.State | Should -Be 'NOT_RUNNING'
  }

  It 'is RUNNING when the heartbeat is fresh (UTC)' {
    $path = Join-Path $TestDrive 'hb-fresh'
    Get-WatchdogTimestamp | Set-Content $path
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15
    $s.State | Should -Be 'RUNNING'
  }

  It 'is STALE when the heartbeat is older than StaleSec — the 2026-08-20 9-minute "fresh" lie' {
    $path = Join-Path $TestDrive 'hb-stale'
    [DateTimeOffset]::UtcNow.AddMinutes(-9).ToString('yyyy-MM-ddTHH:mm:ss.fffZ') | Set-Content $path
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15
    $s.State | Should -Be 'STALE'
    $s.AgeSec | Should -BeGreaterThan 500
  }

  It 'accepts a local-offset round-trip timestamp (legacy heartbeat format)' {
    $path = Join-Path $TestDrive 'hb-offset'
    (Get-Date).ToString('o') | Set-Content $path
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15
    $s.State | Should -Be 'RUNNING'
  }

  It 'is STALE when the heartbeat is unreadable' {
    $path = Join-Path $TestDrive 'hb-junk'
    'not a date' | Set-Content $path
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15
    $s.State | Should -Be 'STALE'
    [double]::IsNaN($s.AgeSec) | Should -BeTrue
  }
}

Describe 'Get-WatchdogTimestamp' {
  It 'emits UTC ISO-8601 with a Z suffix (W-04)' {
    $ts = Get-WatchdogTimestamp
    $ts | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'
  }
}
