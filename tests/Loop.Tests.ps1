BeforeAll {
  . (Join-Path $PSScriptRoot 'Helpers.ps1')
  Import-Module (Join-Path $script:WatchdogModule 'Watchdog.psd1') -Force
}

AfterAll {
  InModuleScope Watchdog {
    Remove-Item function:script:nvidia-smi, function:script:wsl -ErrorAction SilentlyContinue
  }
}

# Every external effect is replaced inside the module: nvidia-smi and wsl are stub functions (functions win
# over applications), Stop-Process / Get-Process / Get-CimInstance / Start-Sleep are mocked. Nothing on the
# host is read for real or killed.
Describe 'Invoke-WatchdogLoop' {
  BeforeEach {
    $script:loopRoot = Get-WatchdogTestDir ('loop-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:loopRoot -Force | Out-Null
  }

  It 'logs a normal sample and stops cleanly on the STOP file' {
    InModuleScope Watchdog -Parameters @{ Root = $script:loopRoot } {
      param($Root)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { '50, 100.0, 10000' }
      Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 67108864; FreePhysicalMemory = 33554432 } }
      Mock Get-Process { @() }
      Mock Start-Sleep { New-Item -ItemType File -Path $script:T.Stop -Force | Out-Null }
      $cfg = [pscustomobject]@{ Root = $Root; Targets = @('C:\t\python.exe'); IntervalSec = 2; RamKillPct = 90; VramKillMiB = 31200; TempKillC = 87; BreachSamples = 3; WslDistro = 'Ubuntu'; WslKillPattern = '' }
      Invoke-WatchdogLoop -Config $cfg
      (Get-Content $script:T.Csv)[-1] | Should -Match ',50,100\.0,10000,50,32,,ok$'
      $log = Get-Content $script:T.Kill -Raw
      $log | Should -Match 'watchdog up: interval 2s'
      $log | Should -Match 'watchdog stopped \(clean, STOP file\)'
      Test-Path $script:T.Heartbeat | Should -BeFalse
      Test-Path $script:T.Dead | Should -BeFalse
    }
  }

  It 'kills only the guarded interpreter on a breach and leaves a TRIPPED sentinel' {
    InModuleScope Watchdog -Parameters @{ Root = $script:loopRoot } {
      param($Root)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { '60, 300.0, 31500' }
      Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 67108864; FreePhysicalMemory = 33554432 } }
      Mock Get-Process { @([pscustomobject]@{ Id = 4242; Path = 'C:\t\python.exe' }, [pscustomobject]@{ Id = 7; Path = 'C:\other\python.exe' }) }
      Mock Get-VramHolders { 'holders: python(pid 4242)=30000MiB' }
      Mock Stop-Process { }
      Mock Start-Sleep { New-Item -ItemType File -Path $script:T.Stop -Force | Out-Null }
      $cfg = [pscustomobject]@{ Root = $Root; Targets = @('C:\t\python.exe'); IntervalSec = 2; RamKillPct = 90; VramKillMiB = 31200; TempKillC = 87; BreachSamples = 1; WslDistro = 'Ubuntu'; WslKillPattern = '' }
      Invoke-WatchdogLoop -Config $cfg
      Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 4242 }
      $log = Get-Content $script:T.Kill -Raw
      $log | Should -Match 'KILL VRAM 31500MiB>=31200 — holders: python\(pid 4242\)'
      $log | Should -Match 'ABORT — VRAM 31500MiB>=31200 — killed win python PID\(s\): 4242'
      Get-Content $script:T.Trip -Raw | Should -Match 'killed win python'
      Test-Path $script:T.NoTarget | Should -BeFalse
    }
  }

  It 'kills a matching WSL process when the distro is already running' {
    InModuleScope Watchdog -Parameters @{ Root = $script:loopRoot } {
      param($Root)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { '90, 300.0, 1000' }
      function script:wsl { $global:LASTEXITCODE = 0 }
      Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 67108864; FreePhysicalMemory = 33554432 } }
      Mock Get-Process { @() }
      Mock Get-VramHolders { 'holders: none reported >0' }
      Mock Test-WslRunning { $true }
      Mock Start-Sleep { New-Item -ItemType File -Path $script:T.Stop -Force | Out-Null }
      $cfg = [pscustomobject]@{ Root = $Root; Targets = @('C:\t\python.exe'); IntervalSec = 2; RamKillPct = 90; VramKillMiB = 31200; TempKillC = 87; BreachSamples = 1; WslDistro = 'Ubuntu'; WslKillPattern = 'train.py' }
      Invoke-WatchdogLoop -Config $cfg
      $log = Get-Content $script:T.Kill -Raw
      $log | Should -Match "ABORT — TEMP 90C>=87C — wsl\[Ubuntu\] pkill -9 -f 'train.py' exit=0"
      Test-Path $script:T.NoTarget | Should -BeFalse
    }
  }

  It 'names a breach with no killable target as a gap, not a success' {
    InModuleScope Watchdog -Parameters @{ Root = $script:loopRoot } {
      param($Root)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { '40, 100.0, 1000' }
      Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 67108864; FreePhysicalMemory = 3355443 } }
      Mock Get-Process { @() }
      Mock Get-VramHolders { 'holders: none reported >0' }
      Mock Test-WslRunning { $false }
      Mock Start-Sleep { New-Item -ItemType File -Path $script:T.Stop -Force | Out-Null }
      $cfg = [pscustomobject]@{ Root = $Root; Targets = @('C:\t\python.exe'); IntervalSec = 2; RamKillPct = 90; VramKillMiB = 31200; TempKillC = 87; BreachSamples = 1; WslDistro = 'Ubuntu'; WslKillPattern = 'train.py' }
      Invoke-WatchdogLoop -Config $cfg
      $log = Get-Content $script:T.Kill -Raw
      $log | Should -Match 'BREACH WITH NO KILLABLE TARGET — RAM 95%>=90%'
      $log | Should -Match 'wsl\[Ubuntu\] not running, skipped'
      Get-Content $script:T.NoTarget -Raw | Should -Match 'no killable target'
    }
  }

  It 'says so when there is nothing to kill and no WSL pattern' {
    InModuleScope Watchdog -Parameters @{ Root = $script:loopRoot } {
      param($Root)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { '40, 100.0, 32000' }
      Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 67108864; FreePhysicalMemory = 33554432 } }
      Mock Get-Process { @() }
      Mock Get-VramHolders { 'holders: none reported >0' }
      Mock Start-Sleep { New-Item -ItemType File -Path $script:T.Stop -Force | Out-Null }
      $cfg = [pscustomobject]@{ Root = $Root; Targets = @('C:\t\python.exe'); IntervalSec = 2; RamKillPct = 90; VramKillMiB = 31200; TempKillC = 87; BreachSamples = 1; WslDistro = 'Ubuntu'; WslKillPattern = '' }
      Invoke-WatchdogLoop -Config $cfg
      Get-Content $script:T.Kill -Raw | Should -Match 'no targets found'
      Test-Path $script:T.NoTarget | Should -BeTrue
    }
  }

  It 'records a bad GPU sample as sample_error and keeps running' {
    InModuleScope Watchdog -Parameters @{ Root = $script:loopRoot } {
      param($Root)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { 'Unable to determine the device handle' }
      Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 67108864; FreePhysicalMemory = 33554432 } }
      Mock Get-Process { @() }
      Mock Start-Sleep { New-Item -ItemType File -Path $script:T.Stop -Force | Out-Null }
      $cfg = [pscustomobject]@{ Root = $Root; Targets = @(); IntervalSec = 2; RamKillPct = 90; VramKillMiB = 31200; TempKillC = 87; BreachSamples = 3; WslDistro = 'Ubuntu'; WslKillPattern = '' }
      Invoke-WatchdogLoop -Config $cfg
      (Get-Content $script:T.Csv)[-1] | Should -Match ',sample_error$'
      Get-Content $script:T.Kill -Raw | Should -Match 'watchdog sample error: nvidia-smi gave no parseable GPU line'
      Get-Content $script:T.Kill -Raw | Should -Match 'watchdog stopped \(clean'
    }
  }

  It 'skips a locked heartbeat write instead of dying (2026-08-25)' {
    InModuleScope Watchdog -Parameters @{ Root = $script:loopRoot } {
      param($Root)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { '50, 100.0, 10000' }
      Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 67108864; FreePhysicalMemory = 33554432 } }
      Mock Get-Process { @() }
      Mock Start-Sleep { New-Item -ItemType File -Path $script:T.Stop -Force | Out-Null }
      $cfg = [pscustomobject]@{ Root = $Root; Targets = @(); IntervalSec = 2; RamKillPct = 90; VramKillMiB = 31200; TempKillC = 87; BreachSamples = 3; WslDistro = 'Ubuntu'; WslKillPattern = '' }
      # A real exclusive lock on the heartbeat, as when a status read raced the write on 2026-08-25.
      'locked' | Set-Content $script:T.Heartbeat
      $lock = [System.IO.File]::Open($script:T.Heartbeat, 'Open', 'ReadWrite', 'None')
      try {
        Invoke-WatchdogLoop -Config $cfg
      } finally {
        $lock.Dispose()
      }
      $log = Get-Content $script:T.Kill -Raw
      $log | Should -Match 'heartbeat write skipped \(file locked\)'
      $log | Should -Match 'watchdog stopped \(clean'
    }
  }

  It 'writes _watchdog_DEAD when the loop dies any other way than the STOP file' {
    InModuleScope Watchdog -Parameters @{ Root = $script:loopRoot } {
      param($Root)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { '50, 100.0, 10000' }
      Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 67108864; FreePhysicalMemory = 33554432 } }
      Mock Get-Process { @() }
      Mock Start-Sleep { throw 'boom' }
      $cfg = [pscustomobject]@{ Root = $Root; Targets = @(); IntervalSec = 2; RamKillPct = 90; VramKillMiB = 31200; TempKillC = 87; BreachSamples = 3; WslDistro = 'Ubuntu'; WslKillPattern = '' }
      Invoke-WatchdogLoop -Config $cfg
      Get-Content $script:T.Dead -Raw | Should -Match 'loop died: boom'
      Get-Content $script:T.Kill -Raw | Should -Match 'watchdog DEAD — loop died: boom'
    }
  }
}
