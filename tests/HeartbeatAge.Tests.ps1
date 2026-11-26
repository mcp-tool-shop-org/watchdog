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
    $s.Source | Should -Be 'unparseable'
  }

  It 'is RUNNING from LastWriteTime when the heartbeat reads empty (mid-write truncate, 2026-11-26)' {
    $path = Join-Path $TestDrive 'hb-empty'
    Set-Content -LiteralPath $path -Value '' -NoNewline
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15 -Attempts 2 -RetryDelayMs 1
    $s.State | Should -Be 'RUNNING'
    $s.Source | Should -Be 'mtime'
  }

  It 'is STALE from LastWriteTime when an empty heartbeat is also old' {
    $path = Join-Path $TestDrive 'hb-empty-old'
    Set-Content -LiteralPath $path -Value '' -NoNewline
    (Get-Item -LiteralPath $path).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(-10)
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15 -Attempts 2 -RetryDelayMs 1
    $s.State | Should -Be 'STALE'
    $s.Source | Should -Be 'mtime'
    $s.AgeSec | Should -BeGreaterThan 500
  }

  It 'is RUNNING from LastWriteTime while another process holds the file exclusively' {
    $path = Join-Path $TestDrive 'hb-locked'
    Get-WatchdogTimestamp | Set-Content $path
    $lock = [System.IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
    try {
      $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15 -Attempts 2 -RetryDelayMs 1
    } finally { $lock.Dispose() }
    $s.State | Should -Be 'RUNNING'
    $s.Source | Should -Be 'mtime'
  }

  It 'reads the content when nothing holds the file' {
    $path = Join-Path $TestDrive 'hb-content'
    Get-WatchdogTimestamp | Set-Content $path
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15
    $s.Source | Should -Be 'content'
  }

  It 'is STALE from LastWriteTime when a locked heartbeat is also old' {
    $path = Join-Path $TestDrive 'hb-locked-old'
    Get-WatchdogTimestamp | Set-Content $path
    (Get-Item -LiteralPath $path).LastWriteTimeUtc = [datetime]::UtcNow.AddMinutes(-10)
    $lock = [System.IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
    try {
      $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15 -Attempts 2 -RetryDelayMs 1
    } finally { $lock.Dispose() }
    $s.State | Should -Be 'STALE'
    $s.Source | Should -Be 'mtime'
  }

  It 'recovers on a later attempt: a locked first read, then the content (proves the retry)' {
    $path = Join-Path $TestDrive 'hb-retry'
    Get-WatchdogTimestamp | Set-Content $path
    $script:readCalls = 0
    Mock Read-WatchdogHeartbeatText {
      $script:readCalls++
      if ($script:readCalls -eq 1) { throw [System.IO.IOException]::new('locked') }
      Get-WatchdogTimestamp
    }
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15 -Attempts 3 -RetryDelayMs 1
    $s.State | Should -Be 'RUNNING'
    $s.Source | Should -Be 'content'
    $script:readCalls | Should -Be 2
  }

  It 'retries a partial write and then reads the content' {
    $path = Join-Path $TestDrive 'hb-partial'
    Get-WatchdogTimestamp | Set-Content $path
    $script:readCalls = 0
    Mock Read-WatchdogHeartbeatText {
      $script:readCalls++
      if ($script:readCalls -eq 1) { return '2026-11-26T17:' }
      Get-WatchdogTimestamp
    }
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15 -Attempts 3 -RetryDelayMs 1
    $s.State | Should -Be 'RUNNING'
    $s.Source | Should -Be 'content'
  }

  It 'is STALE, not fresh, for a timestamp cut off before its offset (would parse as local time)' {
    $path = Join-Path $TestDrive 'hb-nooffset'
    [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss') | Set-Content $path
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15 -Attempts 2 -RetryDelayMs 1
    $s.State | Should -Be 'STALE'
    $s.Source | Should -Be 'unparseable'
  }

  It 'is STALE for a heartbeat stamped well in the future (clock stepped back)' {
    $path = Join-Path $TestDrive 'hb-future'
    [DateTimeOffset]::UtcNow.AddHours(5).ToString('yyyy-MM-ddTHH:mm:ss.fffZ') | Set-Content $path
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15
    $s.State | Should -Be 'STALE'
    $s.Source | Should -Be 'content'
  }

  It 'is NOT_RUNNING when a clean stop deletes the file mid-call' {
    $path = Join-Path $TestDrive 'hb-deleted'
    Get-WatchdogTimestamp | Set-Content $path
    Mock Read-WatchdogHeartbeatText {
      Remove-Item -LiteralPath $Path -Force
      throw [System.IO.FileNotFoundException]::new('gone', $Path)
    }
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15 -Attempts 3 -RetryDelayMs 1
    $s.State | Should -Be 'NOT_RUNNING'
  }

  It 'is STALE with Source unreadable when the mtime cannot be read either' {
    $path = Join-Path $TestDrive 'hb-unreadable'
    Get-WatchdogTimestamp | Set-Content $path
    Mock Read-WatchdogHeartbeatText { throw [System.IO.IOException]::new('locked') }
    Mock Get-Item { throw [System.UnauthorizedAccessException]::new('denied') }
    $s = Get-WatchdogHeartbeatState -Path $path -StaleSec 15 -Attempts 2 -RetryDelayMs 1
    $s.State | Should -Be 'STALE'
    $s.Source | Should -Be 'unreadable'
  }
}

Describe 'Get-WatchdogTimestamp' {
  It 'emits UTC ISO-8601 with a Z suffix (W-04)' {
    $ts = Get-WatchdogTimestamp
    $ts | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'
  }
}
