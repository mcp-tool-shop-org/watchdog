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
      Mock Invoke-WatchdogPollTaskProbe { [pscustomobject]@{ State = 'RUNNING'; Exit = 0; LastTaskResult = 0 } }
      (Register-WatchdogPoll -ConfigPath $Cfg) | Should -Match 'every 60s \(detects death, never kills or restarts\); its first run polled and saw RUNNING'
      Should -Invoke New-ScheduledTaskTrigger -Times 1 -Exactly -ParameterFilter { $RepetitionInterval.TotalSeconds -eq 60 -and $RepetitionDuration.TotalDays -eq 3650 }
      Should -Invoke Register-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'MCPToolShop.Watchdog.Poll' }
      Should -Invoke New-ScheduledTaskAction -Times 1 -Exactly -ParameterFilter {
        $Execute -like '*\System32\conhost.exe' -and
        $Argument -like '--headless "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -Command "Import-Module -Force *Watchdog.psd1''; Invoke-WatchdogPoll -ConfigPath *"'
      }
      Should -Invoke Invoke-WatchdogPollTaskProbe -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'MCPToolShop.Watchdog.Poll' -and $StampPath -like '*\_watchdog_poll_last.json' }
    }
  }

  It 'throws when the first run leaves no proof that the poll ran, instead of reporting a task that would never poll' {
    InModuleScope Watchdog -Parameters @{ Cfg = $script:rCfg } {
      param($Cfg)
      Mock Resolve-WatchdogPwshPath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
      Mock New-ScheduledTaskAction { $script:regExecute = $Execute; $script:regArgument = $Argument; 'action' }
      Mock New-ScheduledTaskTrigger { 'trigger' }
      Mock New-ScheduledTaskSettingsSet { 'settings' }
      Mock New-ScheduledTaskPrincipal { 'principal' }
      Mock Register-ScheduledTask { } -RemoveParameterType 'Action', 'Trigger', 'Settings', 'Principal'
      Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'MCPToolShop.Watchdog.Poll'; Actions = @([pscustomobject]@{ Execute = $script:regExecute; Arguments = $script:regArgument }) } }
      Mock Invoke-WatchdogPollTaskProbe { throw 'MCPToolShop.Watchdog.Poll did not write a fresh poll stamp within 60 s, so the poll did not run.' }
      { Register-WatchdogPoll -ConfigPath $Cfg } | Should -Throw '*did not write a fresh poll stamp*'
    }
  }

  It 'doubles an apostrophe in the config path inside the single-quoted -Command' {
    $quoted = Join-Path (Split-Path $script:rCfg -Parent) "o'brien"
    New-Item -ItemType Directory -Path $quoted -Force | Out-Null
    $cfgCopy = Join-Path $quoted 'watchdog.config.psd1'
    Copy-Item -LiteralPath $script:rCfg -Destination $cfgCopy
    InModuleScope Watchdog -Parameters @{ Cfg = $cfgCopy } {
      param($Cfg)
      Mock Resolve-WatchdogPwshPath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
      Mock New-ScheduledTaskAction { $script:regExecute = $Execute; $script:regArgument = $Argument; 'action' }
      Mock New-ScheduledTaskTrigger { 'trigger' }
      Mock New-ScheduledTaskSettingsSet { 'settings' }
      Mock New-ScheduledTaskPrincipal { 'principal' }
      Mock Register-ScheduledTask { } -RemoveParameterType 'Action', 'Trigger', 'Settings', 'Principal'
      Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'MCPToolShop.Watchdog.Poll'; Actions = @([pscustomobject]@{ Execute = $script:regExecute; Arguments = $script:regArgument }) } }
      Mock Invoke-WatchdogPollTaskProbe { [pscustomobject]@{ State = 'RUNNING'; Exit = 0; LastTaskResult = 0 } }
      [void](Register-WatchdogPoll -ConfigPath $Cfg)
      Should -Invoke New-ScheduledTaskAction -Times 1 -Exactly -ParameterFilter { $Argument -like "*-ConfigPath '*o''brien\watchdog.config.psd1'*" }
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
      Mock Invoke-WatchdogPollTaskProbe { [pscustomobject]@{ State = 'RUNNING'; Exit = 0; LastTaskResult = 0 } }
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
      Mock Invoke-WatchdogPollTaskProbe { [pscustomobject]@{ State = 'RUNNING'; Exit = 0; LastTaskResult = 0 } }
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
      Mock Invoke-WatchdogPollTaskProbe { [pscustomobject]@{ State = 'RUNNING'; Exit = 0; LastTaskResult = 0 } }
      { Register-WatchdogPoll -ConfigPath $Cfg } | Should -Throw '*still holds an older action (pwsh)*'
      Should -Invoke Invoke-WatchdogPollTaskProbe -Times 0 -Exactly
    }
  }

  It 'creates Root before the first poll writes its stamp there' {
    $missingRoot = Join-Path (Get-WatchdogTestDir ('reg-noroot-' + [guid]::NewGuid().ToString('N'))) 'root-not-yet'
    $cfgCopy = Join-Path (Split-Path $script:rCfg -Parent) 'noroot.config.psd1'
    (Get-Content -LiteralPath $script:rCfg -Raw) -replace "Root = '[^']*'", ("Root = '" + $missingRoot.Replace('\', '\\') + "'") | Set-Content -LiteralPath $cfgCopy
    InModuleScope Watchdog -Parameters @{ Cfg = $cfgCopy } {
      param($Cfg)
      Mock Resolve-WatchdogPwshPath { 'C:\Program Files\PowerShell\7\pwsh.exe' }
      Mock New-ScheduledTaskAction { $script:regExecute = $Execute; $script:regArgument = $Argument; 'action' }
      Mock New-ScheduledTaskTrigger { 'trigger' }
      Mock New-ScheduledTaskSettingsSet { 'settings' }
      Mock New-ScheduledTaskPrincipal { 'principal' }
      Mock Register-ScheduledTask { } -RemoveParameterType 'Action', 'Trigger', 'Settings', 'Principal'
      Mock Get-ScheduledTask { [pscustomobject]@{ TaskName = 'MCPToolShop.Watchdog.Poll'; Actions = @([pscustomobject]@{ Execute = $script:regExecute; Arguments = $script:regArgument }) } }
      Mock Invoke-WatchdogPollTaskProbe { [pscustomobject]@{ State = 'NOT_RUNNING'; Exit = 1; LastTaskResult = 0 } }
      [void](Register-WatchdogPoll -ConfigPath $Cfg)
    }
    Test-Path -LiteralPath $missingRoot | Should -BeTrue
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

  It 'refuses the versioned Store package folder as the fallback' {
    InModuleScope Watchdog {
      Mock Get-Command { $null }
      Mock Get-Process { [pscustomobject]@{ Path = 'C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.0.0_x64__8wekyb3d8bbwe\pwsh.exe' } }
      { Resolve-WatchdogPwshPath } | Should -Throw '*versioned Store package folder*'
    }
  }

  It 'clears the previous stamp, then returns what the fresh stamp of the run it started says' {
    $stamp = Join-Path (Get-WatchdogTestDir ('probe-' + [guid]::NewGuid().ToString('N'))) '_watchdog_poll_last.json'
    New-Item -ItemType Directory -Path (Split-Path $stamp -Parent) -Force | Out-Null
    $old = [DateTimeOffset]::UtcNow.AddMinutes(-1).ToUnixTimeMilliseconds()
    ('{"utc_ms":' + $old + ',"started_ms":' + $old + ',"state":"RUNNING","exit":0}') | Set-Content -LiteralPath $stamp
    $global:WdProbeStamp = $stamp
    InModuleScope Watchdog -Parameters @{ Stamp = $stamp } {
      param($Stamp)
      # The run the probe starts writes a fresh stamp, as Invoke-WatchdogPoll does at the end of every run.
      Mock Start-ScheduledTask {
        $global:WdProbeOldGone = -not (Test-Path -LiteralPath $global:WdProbeStamp)
        ('{"utc_ms":' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + ',"started_ms":' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + ',"state":"NOT_RUNNING","exit":1}') | Set-Content -LiteralPath $global:WdProbeStamp
      }
      Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' } }
      Mock Get-ScheduledTaskInfo { [pscustomobject]@{ LastTaskResult = 0 } }
      $r = Invoke-WatchdogPollTaskProbe -TaskName 'MCPToolShop.Watchdog.Poll' -StampPath $Stamp -TimeoutSec 5 -StepMs 10
      $r.State | Should -Be 'NOT_RUNNING'
      $r.Exit | Should -Be 1
      $global:WdProbeOldGone | Should -BeTrue
      Should -Invoke Start-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq 'MCPToolShop.Watchdog.Poll' }
    }
    Remove-Variable -Name WdProbeStamp, WdProbeOldGone -Scope Global
  }

  It 'throws when the run leaves no fresh stamp, as when conhost exits 0 but pwsh never started' {
    $stamp = Join-Path (Get-WatchdogTestDir ('probe-' + [guid]::NewGuid().ToString('N'))) '_watchdog_poll_last.json'
    New-Item -ItemType Directory -Path (Split-Path $stamp -Parent) -Force | Out-Null
    ('{"utc_ms":' + [DateTimeOffset]::UtcNow.AddMinutes(-1).ToUnixTimeMilliseconds() + ',"started_ms":' + [DateTimeOffset]::UtcNow.AddMinutes(-1).ToUnixTimeMilliseconds() + ',"state":"RUNNING","exit":0}') | Set-Content -LiteralPath $stamp
    InModuleScope Watchdog -Parameters @{ Stamp = $stamp } {
      param($Stamp)
      Mock Start-ScheduledTask { }
      Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' } }
      Mock Get-ScheduledTaskInfo { [pscustomobject]@{ LastTaskResult = 0 } }
      { Invoke-WatchdogPollTaskProbe -TaskName 'MCPToolShop.Watchdog.Poll' -StampPath $Stamp -TimeoutSec 1 -StepMs 50 } | Should -Throw '*did not write a fresh poll stamp*'
    }
  }

  It 'does not count a poll that began before the start, even if its stamp lands after the clear' {
    $stamp = Join-Path (Get-WatchdogTestDir ('probe-' + [guid]::NewGuid().ToString('N'))) '_watchdog_poll_last.json'
    New-Item -ItemType Directory -Path (Split-Path $stamp -Parent) -Force | Out-Null
    $global:WdProbeStamp = $stamp
    InModuleScope Watchdog -Parameters @{ Stamp = $stamp } {
      param($Stamp)
      # An instance already running when the task was replaced: IgnoreNew drops this start, and the old poll stamps late.
      Mock Start-ScheduledTask { ('{"utc_ms":' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + ',"started_ms":' + [DateTimeOffset]::UtcNow.AddSeconds(-30).ToUnixTimeMilliseconds() + ',"state":"RUNNING","exit":0}') | Set-Content -LiteralPath $global:WdProbeStamp }
      Mock Get-ScheduledTaskInfo { [pscustomobject]@{ LastTaskResult = 267009 } }
      { Invoke-WatchdogPollTaskProbe -TaskName 'MCPToolShop.Watchdog.Poll' -StampPath $Stamp -TimeoutSec 1 -StepMs 50 } | Should -Throw '*did not write a fresh poll stamp*'
    }
    Remove-Variable -Name WdProbeStamp -Scope Global
  }

  It 'does not count a stamp whose time is before the start, even if it appears after' {
    $stamp = Join-Path (Get-WatchdogTestDir ('probe-' + [guid]::NewGuid().ToString('N'))) '_watchdog_poll_last.json'
    New-Item -ItemType Directory -Path (Split-Path $stamp -Parent) -Force | Out-Null
    $global:WdProbeStamp = $stamp
    InModuleScope Watchdog -Parameters @{ Stamp = $stamp } {
      param($Stamp)
      Mock Start-ScheduledTask { ('{"utc_ms":' + [DateTimeOffset]::UtcNow.AddMinutes(-1).ToUnixTimeMilliseconds() + ',"started_ms":' + [DateTimeOffset]::UtcNow.AddMinutes(-1).ToUnixTimeMilliseconds() + ',"state":"RUNNING","exit":0}') | Set-Content -LiteralPath $global:WdProbeStamp }
      Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Ready' } }
      Mock Get-ScheduledTaskInfo { [pscustomobject]@{ LastTaskResult = 0 } }
      { Invoke-WatchdogPollTaskProbe -TaskName 'MCPToolShop.Watchdog.Poll' -StampPath $Stamp -TimeoutSec 1 -StepMs 50 } | Should -Throw '*did not write a fresh poll stamp*'
    }
    Remove-Variable -Name WdProbeStamp -Scope Global
  }

  It 'throws when the previous stamp cannot be cleared' {
    $stamp = Join-Path (Get-WatchdogTestDir ('probe-' + [guid]::NewGuid().ToString('N'))) '_watchdog_poll_last.json'
    New-Item -ItemType Directory -Path (Split-Path $stamp -Parent) -Force | Out-Null
    '{"utc_ms":1,"state":"RUNNING","exit":0}' | Set-Content -LiteralPath $stamp
    InModuleScope Watchdog -Parameters @{ Stamp = $stamp } {
      param($Stamp)
      Mock Remove-Item { throw 'The process cannot access the file because it is being used by another process.' }
      Mock Start-ScheduledTask { }
      { Invoke-WatchdogPollTaskProbe -TaskName 'MCPToolShop.Watchdog.Poll' -StampPath $Stamp -TimeoutSec 1 -StepMs 50 } | Should -Throw '*Could not clear the previous poll stamp*'
      Should -Invoke Start-ScheduledTask -Times 0 -Exactly
    }
  }

  It 'returns as soon as a fresh stamp appears, even while the task is still running a slow cache release' {
    $stamp = Join-Path (Get-WatchdogTestDir ('probe-' + [guid]::NewGuid().ToString('N'))) '_watchdog_poll_last.json'
    New-Item -ItemType Directory -Path (Split-Path $stamp -Parent) -Force | Out-Null
    $global:WdProbeStamp = $stamp
    InModuleScope Watchdog -Parameters @{ Stamp = $stamp } {
      param($Stamp)
      Mock Start-ScheduledTask { ('{"utc_ms":' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + ',"started_ms":' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + ',"state":"RUNNING","exit":0}') | Set-Content -LiteralPath $global:WdProbeStamp }
      Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Running' } }
      Mock Get-ScheduledTaskInfo { [pscustomobject]@{ LastTaskResult = 267009 } }
      $r = Invoke-WatchdogPollTaskProbe -TaskName 'MCPToolShop.Watchdog.Poll' -StampPath $Stamp -TimeoutSec 5 -StepMs 10
      $r.State | Should -Be 'RUNNING'
      $r.LastTaskResult | Should -Be 267009
    }
    Remove-Variable -Name WdProbeStamp -Scope Global
  }

  It 'reads the exact instant from utc_ms, with milliseconds and no offset' {
    $dir = Get-WatchdogTestDir ('stamp-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $f = Join-Path $dir 'stamp.json'
    # The text 'utc' is for people; a reader that parses it as local time shifts it by the UTC offset.
    '{"utc":"2026-11-24T06:04:17.263Z","utc_ms":1795500257263,"started_ms":1795500256900,"state":"NOT_RUNNING","exit":1}' | Set-Content -LiteralPath $f
    InModuleScope Watchdog -Parameters @{ F = $f } {
      param($F)
      $r = Read-WatchdogPollStamp $F
      $r.Utc.ToUnixTimeMilliseconds() | Should -Be 1795500257263
      $r.Utc.Offset | Should -Be ([TimeSpan]::Zero)
      $r.Utc.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fff', [Globalization.CultureInfo]::InvariantCulture) | Should -Be '2026-11-24T06:04:17.263'
      $r.State | Should -Be 'NOT_RUNNING'
    }
  }

  It 'reads a missing, unreadable or utc_ms-less stamp as no stamp' {
    $dir = Get-WatchdogTestDir ('stamp-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $bad = Join-Path $dir 'bad.json'
    'not json' | Set-Content -LiteralPath $bad
    $textOnly = Join-Path $dir 'text-only.json'
    '{"utc":"2026-11-24T06:04:17.263Z","utc_ms":1795500257263,"state":"RUNNING","exit":0}' | Set-Content -LiteralPath $textOnly
    InModuleScope Watchdog -Parameters @{ Dir = $dir; Bad = $bad; TextOnly = $textOnly } {
      param($Dir, $Bad, $TextOnly)
      Read-WatchdogPollStamp (Join-Path $Dir 'missing.json') | Should -BeNullOrEmpty
      Read-WatchdogPollStamp $Bad | Should -BeNullOrEmpty
      Read-WatchdogPollStamp $TextOnly | Should -BeNullOrEmpty
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
