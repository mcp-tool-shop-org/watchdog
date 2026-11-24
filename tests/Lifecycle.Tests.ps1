BeforeAll {
  . (Join-Path $PSScriptRoot 'Helpers.ps1')
  Import-Module (Join-Path $script:WatchdogModule 'Watchdog.psd1') -Force
}

AfterAll {
  InModuleScope Watchdog {
    Remove-Item function:script:nvidia-smi -ErrorAction SilentlyContinue
  }
}

# Start-Process, Start-Sleep, Get-Date, the scheduled-task cmdlets, Copy-Item and Remove-Item are mocked inside
# the module for every test that reaches them. No loop is launched, no task is registered, no module is copied.
Describe 'Get-WatchdogStatus' {
  BeforeEach {
    $script:stRoot = Get-WatchdogTestDir ('status-' + [guid]::NewGuid().ToString('N'))
    $script:stCfg = New-WatchdogTestConfig -Root $script:stRoot
  }

  It 'reports a live watchdog with exit 0 and one line when -Brief' {
    InModuleScope Watchdog -Parameters @{ Root = $script:stRoot; Cfg = $script:stCfg } {
      param($Root, $Cfg)
      function script:nvidia-smi { '10000, 32607' }
      Get-WatchdogTimestamp | Set-Content (Get-WatchdogPaths -Root $Root).Heartbeat
      $out = @(Get-WatchdogStatus -ConfigPath $Cfg -Brief)
      $LASTEXITCODE | Should -Be 0
      $out.Count | Should -Be 1
      $out[0] | Should -Match 'OK — watchdog alive .* VRAM 10000/32607 MiB, 21200 MiB below the 31200 ceiling'
    }
  }

  It 'reports a missing watchdog with the restart line and a warning when VRAM is near the ceiling' {
    InModuleScope Watchdog -Parameters @{ Root = $script:stRoot; Cfg = $script:stCfg } {
      param($Root, $Cfg)
      function script:nvidia-smi { '31000, 32607' }
      $out = (Get-WatchdogStatus -ConfigPath $Cfg) -join "`n"
      $LASTEXITCODE | Should -Be 1
      $out | Should -Match 'WATCHDOG NOT RUNNING'
      $out | Should -Match 'restart with:  watchdog start -AllowKill'
      $out | Should -Match 'VRAM is at/near the ceiling NOW'
    }
  }

  It 'reports a stale watchdog with every sentinel it finds' {
    InModuleScope Watchdog -Parameters @{ Root = $script:stRoot; Cfg = $script:stCfg } {
      param($Root, $Cfg)
      function script:nvidia-smi { throw 'no gpu' }
      $p = Get-WatchdogPaths -Root $Root
      [DateTimeOffset]::UtcNow.AddHours(-3).ToString('o') | Set-Content $p.Heartbeat
      'loop died: x' | Set-Content $p.Dead
      '' | Set-Content $p.Stop
      'VRAM over' | Set-Content $p.Trip
      'no killable target' | Set-Content $p.NoTarget
      $out = (Get-WatchdogStatus -ConfigPath $Cfg) -join "`n"
      $LASTEXITCODE | Should -Be 2
      $out | Should -Match 'WATCHDOG DEAD \*\*\* heartbeat is 3(\.0)?h old'
      $out | Should -Match 'gpu unreadable'
      $out | Should -Match '_watchdog_DEAD: loop died: x'
      $out | Should -Match '_watchdog_STOP present'
      $out | Should -Match 'last TRIP: VRAM over'
      $out | Should -Match '_watchdog_NO_TARGET: no killable target'
    }
  }

  It 'emits SessionStart JSON and always exits 0 with -Hook' {
    InModuleScope Watchdog -Parameters @{ Root = $script:stRoot; Cfg = $script:stCfg } {
      param($Root, $Cfg)
      function script:nvidia-smi { '10000, 32607' }
      $down = Get-WatchdogStatus -ConfigPath $Cfg -Hook | ConvertFrom-Json
      $LASTEXITCODE | Should -Be 0
      $down.systemMessage | Should -Match 'NOT running'
      Get-WatchdogTimestamp | Set-Content (Get-WatchdogPaths -Root $Root).Heartbeat
      $up = Get-WatchdogStatus -ConfigPath $Cfg -Hook | ConvertFrom-Json
      $up.suppressOutput | Should -BeTrue
      $up.hookSpecificOutput.additionalContext | Should -Match 'VRAM watchdog: alive'
    }
  }

  It 'fails closed on a missing config, and still exits 0 under -Hook' {
    $missing = Join-Path (Get-WatchdogTestDir 'status-nocfg') 'nope.psd1'
    $r = Get-WatchdogStatus -ConfigPath $missing 2>$null
    $r.code | Should -Be 'CONFIG_MISSING'
    $LASTEXITCODE | Should -Be 1
    $j = Get-WatchdogStatus -ConfigPath $missing -Hook | ConvertFrom-Json
    $LASTEXITCODE | Should -Be 0
    $j.systemMessage | Should -Match 'config is missing or invalid'
  }
}

Describe 'Start-Watchdog' {
  BeforeEach {
    $script:sRoot = Get-WatchdogTestDir ('start-' + [guid]::NewGuid().ToString('N'))
    $script:sCfg = New-WatchdogTestConfig -Root $script:sRoot -AllowKill $true
  }

  It 'launches detached and verifies the heartbeat' {
    InModuleScope Watchdog -Parameters @{ Root = $script:sRoot; Cfg = $script:sCfg } {
      param($Root, $Cfg)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { '1000' }
      Mock Start-Process { Get-WatchdogTimestamp | Set-Content $script:T.Heartbeat }
      Mock Start-Sleep { }
      $out = (Start-Watchdog -ConfigPath $Cfg) -join "`n"
      $LASTEXITCODE | Should -Be 0
      $out | Should -Match 'no watchdog running'
      $out | Should -Match 'watchdog UP — kill@ VRAM 31200 MiB'
      Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'pwsh' -and $WindowStyle -eq 'Hidden' }
    }
  }

  It 'stops a live watchdog through the sentinel before relaunching' {
    InModuleScope Watchdog -Parameters @{ Root = $script:sRoot; Cfg = $script:sCfg } {
      param($Root, $Cfg)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { '1000' }
      Get-WatchdogTimestamp | Set-Content $script:T.Heartbeat
      Mock Start-Sleep { Remove-Item $script:T.Heartbeat -ErrorAction SilentlyContinue }
      Mock Start-Process { Get-WatchdogTimestamp | Set-Content $script:T.Heartbeat }
      $out = (Start-Watchdog -ConfigPath $Cfg) -join "`n"
      $LASTEXITCODE | Should -Be 0
      $out | Should -Match 'requesting stop via sentinel'
      $out | Should -Match 'old watchdog stopped'
      Test-Path $script:T.Stop | Should -BeFalse
    }
  }

  It 'clears a stale heartbeat from a hard death and relaunches' {
    InModuleScope Watchdog -Parameters @{ Root = $script:sRoot; Cfg = $script:sCfg } {
      param($Root, $Cfg)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { '1000' }
      New-Item -ItemType Directory -Path $Root -Force | Out-Null
      [DateTimeOffset]::UtcNow.AddMinutes(-30).ToString('o') | Set-Content $script:T.Heartbeat
      'old trip' | Set-Content $script:T.Trip
      Mock Start-Sleep { }
      Mock Start-Process { Get-WatchdogTimestamp | Set-Content $script:T.Heartbeat }
      $out = (Start-Watchdog -ConfigPath $Cfg) -join "`n"
      $out | Should -Match 'previous watchdog died hard'
      Test-Path $script:T.Trip | Should -BeFalse
      $LASTEXITCODE | Should -Be 0
    }
  }

  It 'refuses to start into a job it would kill (exit 3) unless -Force' {
    InModuleScope Watchdog -Parameters @{ Root = $script:sRoot; Cfg = $script:sCfg } {
      param($Root, $Cfg)
      function script:nvidia-smi { '31500' }
      Mock Start-Process { }
      Start-Watchdog -ConfigPath $Cfg 2>$null
      $LASTEXITCODE | Should -Be 3
      Should -Invoke Start-Process -Times 0 -Exactly
    }
  }

  It 'refuses a second loop when the old one will not stop (exit 4)' {
    InModuleScope Watchdog -Parameters @{ Root = $script:sRoot; Cfg = $script:sCfg } {
      param($Root, $Cfg)
      $script:T = Get-WatchdogPaths -Root $Root
      function script:nvidia-smi { '1000' }
      New-Item -ItemType Directory -Path $Root -Force | Out-Null
      Get-WatchdogTimestamp | Set-Content $script:T.Heartbeat
      $script:Clock = Get-Date
      Mock Get-Date { $script:Clock = $script:Clock.AddSeconds(5); $script:Clock }
      Mock Start-Sleep { Get-WatchdogTimestamp | Set-Content $script:T.Heartbeat }
      Mock Start-Process { }
      Start-Watchdog -ConfigPath $Cfg -StopWaitSec 10 2>$null
      $LASTEXITCODE | Should -Be 4
      Should -Invoke Start-Process -Times 0 -Exactly
    }
  }

  It 'reports a launch that never produced a heartbeat (exit 5)' {
    InModuleScope Watchdog -Parameters @{ Root = $script:sRoot; Cfg = $script:sCfg } {
      param($Root, $Cfg)
      function script:nvidia-smi { '1000' }
      $script:Clock = Get-Date
      Mock Get-Date { $script:Clock = $script:Clock.AddSeconds(5); $script:Clock }
      Mock Start-Sleep { }
      Mock Start-Process { }
      Start-Watchdog -ConfigPath $Cfg 2>$null
      $LASTEXITCODE | Should -Be 5
    }
  }

  It 'fails closed on a missing config' {
    Start-Watchdog -ConfigPath (Join-Path (Get-WatchdogTestDir 'start-nocfg') 'nope.psd1') 2>$null
    $LASTEXITCODE | Should -Be 1
  }
}

Describe 'Stop-Watchdog' {
  BeforeEach {
    $script:pRoot = Get-WatchdogTestDir ('stop-' + [guid]::NewGuid().ToString('N'))
    $script:pCfg = New-WatchdogTestConfig -Root $script:pRoot
  }

  It 'is a no-op with exit 0 when nothing is running' {
    (Stop-Watchdog -ConfigPath $script:pCfg) | Should -Match 'no live watchdog to stop'
    $LASTEXITCODE | Should -Be 0
  }

  It 'stops a live loop through the sentinel' {
    InModuleScope Watchdog -Parameters @{ Root = $script:pRoot; Cfg = $script:pCfg } {
      param($Root, $Cfg)
      $script:T = Get-WatchdogPaths -Root $Root
      Get-WatchdogTimestamp | Set-Content $script:T.Heartbeat
      Mock Start-Sleep { Remove-Item $script:T.Heartbeat -ErrorAction SilentlyContinue }
      ((Stop-Watchdog -ConfigPath $Cfg) -join "`n") | Should -Match 'old watchdog stopped'
      $LASTEXITCODE | Should -Be 0
      Test-Path $script:T.Stop | Should -BeTrue
    }
  }

  It 'refuses to claim a stop that did not happen (exit 4)' {
    InModuleScope Watchdog -Parameters @{ Root = $script:pRoot; Cfg = $script:pCfg } {
      param($Root, $Cfg)
      $script:T = Get-WatchdogPaths -Root $Root
      Get-WatchdogTimestamp | Set-Content $script:T.Heartbeat
      $script:Clock = Get-Date
      Mock Get-Date { $script:Clock = $script:Clock.AddSeconds(5); $script:Clock }
      Mock Start-Sleep { Get-WatchdogTimestamp | Set-Content $script:T.Heartbeat }
      Stop-Watchdog -ConfigPath $Cfg -StopWaitSec 10 2>$null
      $LASTEXITCODE | Should -Be 4
    }
  }

  It 'fails closed on a missing config' {
    Stop-Watchdog -ConfigPath (Join-Path (Get-WatchdogTestDir 'stop-nocfg') 'nope.psd1') 2>$null
    $LASTEXITCODE | Should -Be 1
  }
}

Describe 'Register-WatchdogPoll / Unregister-WatchdogPoll' {
  BeforeEach {
    $script:rRoot = Get-WatchdogTestDir ('reg-' + [guid]::NewGuid().ToString('N'))
    $script:rCfg = New-WatchdogTestConfig -Root $script:rRoot
  }

  It 'registers the poll every 60 s for ten years, through conhost with the absolute pwsh path, and runs it once' {
    InModuleScope Watchdog -Parameters @{ Cfg = $script:rCfg } {
      param($Cfg)
      Mock Resolve-WatchdogPwshPath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
      Mock New-ScheduledTaskAction { $script:regExecute = $Execute; $script:regArgument = $Argument; 'action' }
      Mock New-ScheduledTaskTrigger { 'trigger' }
      Mock New-ScheduledTaskSettingsSet { 'settings' }
      Mock New-ScheduledTaskPrincipal { 'principal' }
      Mock Register-ScheduledTask { } -RemoveParameterType 'Action', 'Trigger', 'Settings', 'Principal'
      Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'MCPToolShop.Watchdog.Poll'; Actions = @([pscustomobject]@{ Execute = $script:regExecute; Arguments = $script:regArgument }) } }
      Mock Invoke-WatchdogPollTaskProbe { 0 }
      (Register-WatchdogPoll -ConfigPath $Cfg) | Should -Match 'every 60s \(detects death, never kills or restarts\); its first run returned 0'
      Should -Invoke New-ScheduledTaskTrigger -Times 1 -Exactly -ParameterFilter { $RepetitionInterval.TotalSeconds -eq 60 -and $RepetitionDuration.TotalDays -eq 3650 }
      Should -Invoke Register-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'MCPToolShop.Watchdog.Poll' }
      Should -Invoke New-ScheduledTaskAction -Times 1 -Exactly -ParameterFilter {
        $Execute -like '*\System32\conhost.exe' -and
        $Argument -like '--headless "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -Command "Import-Module -Force *Watchdog.psd1''; Invoke-WatchdogPoll -ConfigPath *"'
      }
      Should -Invoke Invoke-WatchdogPollTaskProbe -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'MCPToolShop.Watchdog.Poll' }
    }
  }

  It 'throws when the first run fails, instead of reporting a task that would never poll' {
    InModuleScope Watchdog -Parameters @{ Cfg = $script:rCfg } {
      param($Cfg)
      Mock Resolve-WatchdogPwshPath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
      Mock New-ScheduledTaskAction { $script:regExecute = $Execute; $script:regArgument = $Argument; 'action' }
      Mock New-ScheduledTaskTrigger { 'trigger' }
      Mock New-ScheduledTaskSettingsSet { 'settings' }
      Mock New-ScheduledTaskPrincipal { 'principal' }
      Mock Register-ScheduledTask { } -RemoveParameterType 'Action', 'Trigger', 'Settings', 'Principal'
      Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'MCPToolShop.Watchdog.Poll'; Actions = @([pscustomobject]@{ Execute = $script:regExecute; Arguments = $script:regArgument }) } }
      # 0x80070002, file not found: what the bare 'pwsh' action returned on every trigger on the rig (2026-11-24).
      Mock Invoke-WatchdogPollTaskProbe { 2147942402 }
      { Register-WatchdogPoll -ConfigPath $Cfg } | Should -Throw '*first run failed with 0x80070002*'
    }
  }

  It 'says the poll may drop the WSL page cache when the config turns that on' {
    $cfgText = (Get-Content $script:rCfg -Raw).TrimEnd()
    Set-Content -Path $script:rCfg -Value ($cfgText.Substring(0, $cfgText.Length - 1) + "  WslCacheRelease = `$true`n}`n")
    InModuleScope Watchdog -Parameters @{ Cfg = $script:rCfg } {
      param($Cfg)
      Mock Resolve-WatchdogPwshPath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
      Mock New-ScheduledTaskAction { $script:regExecute = $Execute; $script:regArgument = $Argument; 'action' }
      Mock New-ScheduledTaskTrigger { 'trigger' }
      Mock New-ScheduledTaskSettingsSet { 'settings' }
      Mock New-ScheduledTaskPrincipal { 'principal' }
      Mock Register-ScheduledTask { } -RemoveParameterType 'Action', 'Trigger', 'Settings', 'Principal'
      Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'MCPToolShop.Watchdog.Poll'; Actions = @([pscustomobject]@{ Execute = $script:regExecute; Arguments = $script:regArgument }) } }
      Mock Invoke-WatchdogPollTaskProbe { 0 }
      (Register-WatchdogPoll -ConfigPath $Cfg) | Should -Match 'WslCacheRelease is on, so each poll may also drop the WSL page cache'
    }
  }

  It 'throws with the elevation hint when Task Scheduler refuses the registration' {
    InModuleScope Watchdog -Parameters @{ Cfg = $script:rCfg } {
      param($Cfg)
      Mock Resolve-WatchdogPwshPath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
      Mock New-ScheduledTaskAction { 'action' }
      Mock New-ScheduledTaskTrigger { 'trigger' }
      Mock New-ScheduledTaskSettingsSet { 'settings' }
      Mock New-ScheduledTaskPrincipal { 'principal' }
      # What Task Scheduler said on the rig (2026-11-24) when a normal shell tried to replace the task.
      Mock Register-ScheduledTask { throw 'Access is denied.' } -RemoveParameterType 'Action', 'Trigger', 'Settings', 'Principal'
      Mock Invoke-WatchdogPollTaskProbe { 0 }
      { Register-WatchdogPoll -ConfigPath $Cfg } | Should -Throw '*refused to register MCPToolShop.Watchdog.Poll: Access is denied.*elevated shell*'
      Should -Invoke Invoke-WatchdogPollTaskProbe -Times 0 -Exactly
    }
  }

  It 'throws when the task still holds an older action, instead of probing a task it did not replace' {
    InModuleScope Watchdog -Parameters @{ Cfg = $script:rCfg } {
      param($Cfg)
      Mock Resolve-WatchdogPwshPath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
      Mock New-ScheduledTaskAction { 'action' }
      Mock New-ScheduledTaskTrigger { 'trigger' }
      Mock New-ScheduledTaskSettingsSet { 'settings' }
      Mock New-ScheduledTaskPrincipal { 'principal' }
      Mock Register-ScheduledTask { } -RemoveParameterType 'Action', 'Trigger', 'Settings', 'Principal'
      Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'MCPToolShop.Watchdog.Poll'; Actions = @([pscustomobject]@{ Execute = 'pwsh'; Arguments = '-NoProfile -Command old' }) } }
      Mock Invoke-WatchdogPollTaskProbe { 0 }
      { Register-WatchdogPoll -ConfigPath $Cfg } | Should -Throw '*still holds an older action (pwsh)*'
      Should -Invoke Invoke-WatchdogPollTaskProbe -Times 0 -Exactly
    }
  }

  It 'throws instead of printing success when the task did not appear' {
    InModuleScope Watchdog -Parameters @{ Cfg = $script:rCfg } {
      param($Cfg)
      Mock Resolve-WatchdogPwshPath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
      Mock New-ScheduledTaskAction { $script:regExecute = $Execute; $script:regArgument = $Argument; 'action' }
      Mock New-ScheduledTaskTrigger { 'trigger' }
      Mock New-ScheduledTaskSettingsSet { 'settings' }
      Mock New-ScheduledTaskPrincipal { 'principal' }
      Mock Register-ScheduledTask { } -RemoveParameterType 'Action', 'Trigger', 'Settings', 'Principal'
      Mock Get-ScheduledTask { $null }
      { Register-WatchdogPoll -ConfigPath $Cfg } | Should -Throw '*without creating MCPToolShop.Watchdog.Poll*'
    }
  }

  It 'fails closed on a missing config' {
    InModuleScope Watchdog {
      Mock Register-ScheduledTask { }
      Register-WatchdogPoll -ConfigPath 'C:\watchdog-ci-missing\nope.psd1' 2>$null
      $LASTEXITCODE | Should -Be 1
      Should -Invoke Register-ScheduledTask -Times 0 -Exactly
    }
  }

  It 'unregisters the task by name' {
    InModuleScope Watchdog {
      Mock Unregister-ScheduledTask { }
      (Unregister-WatchdogPoll) | Should -Match 'unregistered scheduled task MCPToolShop.Watchdog.Poll'
      Should -Invoke Unregister-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'MCPToolShop.Watchdog.Poll' }
    }
  }
}

Describe 'Poll task launch helpers' {
  It 'resolves pwsh from PATH' {
    InModuleScope Watchdog {
      Mock Get-Command { [pscustomobject]@{ Source = 'C:\Program Files\PowerShell\7\pwsh.exe' } }
      Resolve-WatchdogPwshPath | Should -Be 'C:\Program Files\PowerShell\7\pwsh.exe'
    }
  }

  It 'falls back to the pwsh that is running when PATH has none' {
    InModuleScope Watchdog {
      Mock Get-Command { $null }
      Mock Get-Process { [pscustomobject]@{ Path = 'D:\tools\pwsh\pwsh.exe' } }
      Resolve-WatchdogPwshPath | Should -Be 'D:\tools\pwsh\pwsh.exe'
    }
  }

  It 'fails closed when no pwsh can be found' {
    InModuleScope Watchdog {
      Mock Get-Command { $null }
      Mock Get-Process { [pscustomobject]@{ Path = 'D:\tools\other\powershell.exe' } }
      { Resolve-WatchdogPwshPath } | Should -Throw '*pwsh.exe not found*'
    }
  }

  It 'starts the task once and returns the result of that run' {
    InModuleScope Watchdog {
      $script:probeInfo = [System.Collections.Generic.Queue[object]]::new()
      $script:probeInfo.Enqueue([pscustomobject]@{ LastRunTime = [datetime]'2026-11-24T00:00:00'; LastTaskResult = 267011 })
      $script:probeInfo.Enqueue([pscustomobject]@{ LastRunTime = [datetime]'2026-11-24T00:00:00'; LastTaskResult = 267011 })
      $script:probeInfo.Enqueue([pscustomobject]@{ LastRunTime = [datetime]'2026-11-24T00:05:00'; LastTaskResult = 2147942402 })
      Mock Get-ScheduledTaskInfo { $script:probeInfo.Dequeue() }
      Mock Start-ScheduledTask { }
      Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' } }
      Invoke-WatchdogPollTaskProbe -TaskName 'MCPToolShop.Watchdog.Poll' -TimeoutSec 5 -StepMs 10 | Should -Be 2147942402
      Should -Invoke Start-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'MCPToolShop.Watchdog.Poll' }
    }
  }

  It 'throws when the run does not finish in time' {
    InModuleScope Watchdog {
      Mock Get-ScheduledTaskInfo { [pscustomobject]@{ LastRunTime = [datetime]'2026-11-24T00:00:00'; LastTaskResult = 267009 } }
      Mock Start-ScheduledTask { }
      Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Running' } }
      { Invoke-WatchdogPollTaskProbe -TaskName 'MCPToolShop.Watchdog.Poll' -TimeoutSec 1 -StepMs 50 } | Should -Throw '*did not finish its first run within 1 s*'
    }
  }
}

Describe 'Install-Watchdog / Uninstall-Watchdog' {
  It 'copies the module and registers the poller only with -Poll' {
    InModuleScope Watchdog {
      Mock Test-Path { $true } -ParameterFilter { "$Path" -like '*PowerShell\Modules\Watchdog' }
      Mock Copy-Item { }
      Mock Register-WatchdogPoll { 'registered' }
      $out = (Install-Watchdog) -join "`n"
      $out | Should -Match 'installed module to .*PowerShell\\Modules\\Watchdog'
      Should -Invoke Register-WatchdogPoll -Times 0 -Exactly
      [void](Install-Watchdog -Poll -ConfigPath 'C:\x\config.psd1')
      Should -Invoke Register-WatchdogPoll -Times 1 -Exactly
      Should -Invoke Copy-Item -Times 2 -Exactly
    }
  }

  It 'creates the destination when it is missing' {
    InModuleScope Watchdog {
      Mock Test-Path { $false } -ParameterFilter { "$Path" -like '*PowerShell\Modules\Watchdog' }
      Mock New-Item { } -ParameterFilter { "$Path" -like '*PowerShell\Modules\Watchdog' }
      Mock Copy-Item { }
      [void](Install-Watchdog)
      Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { "$Path" -like '*PowerShell\Modules\Watchdog' }
    }
  }

  It 'removes the module copy and the poller but never config or telemetry' {
    InModuleScope Watchdog {
      Mock Unregister-WatchdogPoll { }
      Mock Test-Path { $true } -ParameterFilter { "$Path" -like '*PowerShell\Modules\Watchdog' }
      Mock Remove-Item { }
      $out = (Uninstall-Watchdog) -join "`n"
      $out | Should -Match 'removed .*PowerShell\\Modules\\Watchdog'
      $out | Should -Match 'user config and Root telemetry were not deleted'
      Should -Invoke Unregister-WatchdogPoll -Times 1 -Exactly
    }
  }

  It 'says so when there is no module copy to remove' {
    InModuleScope Watchdog {
      Mock Unregister-WatchdogPoll { }
      Mock Test-Path { $false } -ParameterFilter { "$Path" -like '*PowerShell\Modules\Watchdog' }
      Mock Remove-Item { }
      ((Uninstall-Watchdog) -join "`n") | Should -Match 'no CurrentUser module copy'
      Should -Invoke Remove-Item -Times 0 -Exactly
    }
  }
}
