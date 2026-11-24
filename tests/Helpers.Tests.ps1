BeforeAll {
  . (Join-Path $PSScriptRoot 'Helpers.ps1')
  Import-Module (Join-Path $script:WatchdogModule 'Watchdog.psd1') -Force
}

Describe 'Get-WatchdogConfig' {
  It 'returns the validated config' {
    $root = Get-WatchdogTestDir 'getcfg-ok'
    (Get-WatchdogConfig -ConfigPath (New-WatchdogTestConfig -Root $root)).Root | Should -Be $root
  }
  It 'returns the structured error and its exit code' {
    $r = Get-WatchdogConfig -ConfigPath 'C:\watchdog-ci-missing\nope.psd1' 2>$null
    $r.code | Should -Be 'CONFIG_MISSING'
    $LASTEXITCODE | Should -Be 1
  }
}

Describe 'Resolve-WatchdogConfig edge cases' {
  It 'refuses a config path that does not exist' {
    (Resolve-WatchdogConfig -Path 'C:\watchdog-ci-missing\nope.psd1').code | Should -Be 'CONFIG_MISSING'
  }
  It 'refuses a file that is not a PowerShell data file' {
    $dir = Get-WatchdogTestDir 'cfg-bad'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $p = Join-Path $dir 'bad.psd1'
    'this is not a hashtable {' | Set-Content $p
    (Resolve-WatchdogConfig -Path $p).code | Should -Be 'CONFIG_INVALID'
  }
}

Describe 'Get-VramHolders' {
  It 'names holders by process, largest first, from the GPU counter set' {
    InModuleScope Watchdog {
      Mock Get-Counter {
        [pscustomobject]@{ CounterSamples = @(
          [pscustomobject]@{ InstanceName = 'pid_100_luid_0x1_phys_0'; CookedValue = 1GB },
          [pscustomobject]@{ InstanceName = 'pid_200_luid_0x1_phys_0'; CookedValue = 3GB },
          [pscustomobject]@{ InstanceName = 'pid_300_luid_0x1_phys_0'; CookedValue = 0 }
        ) }
      }
      Mock Get-Process { if ($Id -eq 200) { [pscustomobject]@{ ProcessName = 'python' } } }
      Get-VramHolders | Should -Be 'holders: python(pid 200)=3072MiB | ?(pid 100)=1024MiB'
    }
  }
  It 'says when no process reports VRAM' {
    InModuleScope Watchdog {
      Mock Get-Counter { [pscustomobject]@{ CounterSamples = @() } }
      Get-VramHolders | Should -Be 'holders: none reported >0'
    }
  }
  It 'degrades to a note instead of throwing' {
    InModuleScope Watchdog {
      Mock Get-Counter { throw 'counter set missing' }
      Get-VramHolders | Should -Be 'holders unavailable: counter set missing'
    }
  }
}

Describe 'Format-WatchdogAge' {
  It 'formats seconds, minutes, hours, days and unreadable' {
    Format-WatchdogAge 30 | Should -Be '30s'
    Format-WatchdogAge 120 | Should -Be '2m'
    Format-WatchdogAge 7200 | Should -Be '2h'
    Format-WatchdogAge 216000 | Should -Be '2.5d'
    Format-WatchdogAge ([double]::NaN) | Should -Be 'unreadable'
  }
}

Describe 'Write-WatchdogError' {
  It 'writes code, message, hint, cause and retryable to stderr, and includes the full object only with -IncludeStack' {
    $e = New-WatchdogError -Code 'X_TEST' -Message 'm' -Hint 'h' -Cause 'c'
    $prevErr = [Console]::Error
    try {
      $swPlain = [System.IO.StringWriter]::new()
      [Console]::SetError($swPlain)
      Write-WatchdogError -ErrorObject $e
      $plainText = $swPlain.ToString()
      $plainText | Should -Match 'WATCHDOG X_TEST'
      $plainText | Should -Match 'message: m'
      $plainText | Should -Match 'hint: h'
      $plainText | Should -Match 'cause: c'
      $plainText | Should -Match 'retryable: False'
      $plainText | Should -Not -Match 'exitCode\s*:'

      $swStack = [System.IO.StringWriter]::new()
      [Console]::SetError($swStack)
      Write-WatchdogError -ErrorObject $e -IncludeStack
      $stackText = $swStack.ToString()
      $stackText | Should -Match 'WATCHDOG X_TEST'
      $stackText | Should -Match 'message: m'
      $stackText | Should -Match 'hint: h'
      $stackText | Should -Match 'cause: c'
      $stackText | Should -Match 'exitCode\s*:\s*1'
    } finally {
      [Console]::SetError($prevErr)
    }
  }
}

Describe 'Invoke-WatchdogPoll forensics' {
  It 'carries the console and crash tails into _watchdog_DEAD' {
    $root = Get-WatchdogTestDir 'poll-tails'
    $cfgPath = New-WatchdogTestConfig -Root $root
    $paths = Get-WatchdogPaths -Root $root
    [DateTimeOffset]::UtcNow.AddMinutes(-9).ToString('o') | Set-Content $paths.Heartbeat
    'console line' | Set-Content $paths.Console
    'crash line' | Set-Content $paths.Crash
    'earlier kill line' | Set-Content $paths.Kill
    [void](Invoke-WatchdogPoll -ConfigPath $cfgPath)
    $dead = Get-Content $paths.Dead -Raw
    $dead | Should -Match 'crash: crash line ; console: console line'
    (Get-Content $paths.Kill -Raw) | Should -Match 'earlier kill line'
    (Get-Content $paths.Kill -Raw) | Should -Match 'poller declared STALE'
  }
  It 'returns the config error with its exit code' {
    $r = Invoke-WatchdogPoll -ConfigPath 'C:\watchdog-ci-missing\nope.psd1' 2>$null
    $r.code | Should -Be 'CONFIG_MISSING'
    $LASTEXITCODE | Should -Be 1
  }
  It 'reports NOT_RUNNING (exit 1) when there is no heartbeat at all' {
    $root = Get-WatchdogTestDir 'poll-none'
    $cfgPath = New-WatchdogTestConfig -Root $root
    (Invoke-WatchdogPoll -ConfigPath $cfgPath).State | Should -Be 'NOT_RUNNING'
    $LASTEXITCODE | Should -Be 1
  }
}

Describe 'WSL cache helpers' {
  It 'reads Windows and vmmemWSL memory from the Windows side' {
    InModuleScope Watchdog {
      Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 67108864; FreePhysicalMemory = 13421773 } }
      Mock Get-Process { [pscustomobject]@{ WorkingSet64 = 24GB } } -ParameterFilter { $Name -eq 'vmmemWSL' }
      $m = Get-WslHostMemory
      [math]::Round($m.WinUsedPct) | Should -Be 80
      $m.WslGB | Should -Be 24
      $m.WslUp | Should -BeTrue
    }
  }
  It 'reports WSL as down when vmmemWSL is absent' {
    InModuleScope Watchdog {
      Mock Get-CimInstance { [pscustomobject]@{ TotalVisibleMemorySize = 67108864; FreePhysicalMemory = 33554432 } }
      Mock Get-Process { $null } -ParameterFilter { $Name -eq 'vmmemWSL' }
      $m = Get-WslHostMemory
      $m.WslUp | Should -BeFalse
      $m.WslGB | Should -Be 0
    }
  }
  It 'runs a process with a timeout and returns its output' {
    InModuleScope Watchdog {
      (Invoke-ProcessWithTimeout -FileName 'pwsh' -Arguments '-NoProfile -Command "Write-Output ok-from-child"' -TimeoutSec 60).Trim() | Should -Be 'ok-from-child'
    }
  }
  It 'throws with the exit code and stderr on failure' {
    InModuleScope Watchdog {
      { Invoke-ProcessWithTimeout -FileName 'pwsh' -Arguments '-NoProfile -Command "[Console]::Error.WriteLine(''bad thing''); exit 3"' -TimeoutSec 60 } | Should -Throw '*exited 3: bad thing*'
    }
  }
  It 'with -PassThru returns the exit code and output instead of throwing' {
    InModuleScope Watchdog {
      $r = Invoke-ProcessWithTimeout -FileName 'pwsh' -Arguments '-NoProfile -Command "Write-Output partial; exit 3"' -TimeoutSec 60 -PassThru
      $r.ExitCode | Should -Be 3
      $r.Out.Trim() | Should -Be 'partial'
      $r.StreamsDrained | Should -BeTrue
    }
  }
  It 'returns within the stream drain bound when a fake stream task never completes' {
    InModuleScope Watchdog {
      $launcher = {
        param($psi)
        $fakeProc = [pscustomobject]@{ ExitCode = 0 }
        $fakeProc | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $true }
        $neverOut = [System.Threading.Tasks.TaskCompletionSource[string]]::new()
        [pscustomobject]@{
          Process = $fakeProc
          Out     = $neverOut.Task
          Err     = [System.Threading.Tasks.Task]::FromResult('')
        }
      }
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $r = Invoke-ProcessWithTimeout -FileName 'fake' -PassThru -Launcher $launcher
      $sw.Stop()
      $sw.Elapsed.TotalSeconds | Should -BeLessThan 15
      $r.ExitCode | Should -Be 0
      $r.Out | Should -Be ''
      $r.StreamsDrained | Should -BeFalse
    }
  }
  It 'throws with a stream-not-drained message when a failing exit leaves stderr incomplete' {
    InModuleScope Watchdog {
      $launcher = {
        param($psi)
        $fakeProc = [pscustomobject]@{ ExitCode = 2 }
        $fakeProc | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($ms) $true }
        $neverErr = [System.Threading.Tasks.TaskCompletionSource[string]]::new()
        [pscustomobject]@{
          Process = $fakeProc
          Out     = [System.Threading.Tasks.Task]::FromResult('')
          Err     = $neverErr.Task
        }
      }
      { Invoke-ProcessWithTimeout -FileName 'fake' -StreamDrainMs 100 -Launcher $launcher } | Should -Throw '*fake exited 2: stderr stream was not drained*'
    }
  }
  It 'passes each -ArgumentList element untouched, including spaces, pipes, semicolons, and quotes' {
    $dir = Get-WatchdogTestDir ('arglist-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $scriptPath = Join-Path $dir 'echo-args.ps1'
    '[Environment]::GetCommandLineArgs() | ConvertTo-Json -Compress' | Set-Content -LiteralPath $scriptPath
    InModuleScope Watchdog -Parameters @{ Script = $scriptPath } {
      param($Script)
      $pattern = 'python "my train.py" | tee out; --tag=''a b'''
      $r = Invoke-ProcessWithTimeout -FileName 'pwsh' -ArgumentList @(
        '-NoProfile', '-File', $Script, '-d', 'Ubuntu', '--exec', 'pkill', '-9', '-f', $pattern
      ) -TimeoutSec 30 -PassThru
      $r.ExitCode | Should -Be 0
      $r.StreamsDrained | Should -BeTrue
      $all = @($r.Out.Trim() | ConvertFrom-Json)
      $idx = [Array]::IndexOf($all, $Script)
      $idx | Should -BeGreaterOrEqual 0
      $got = @($all | Select-Object -Skip ($idx + 1))
      $got.Count | Should -Be 7
      $got[0] | Should -Be '-d'
      $got[1] | Should -Be 'Ubuntu'
      $got[2] | Should -Be '--exec'
      $got[3] | Should -Be 'pkill'
      $got[4] | Should -Be '-9'
      $got[5] | Should -Be '-f'
      $got[6] | Should -BeExactly $pattern
    }
  }
  It 'refuses combining -Arguments and -ArgumentList' {
    InModuleScope Watchdog {
      { Invoke-ProcessWithTimeout -FileName 'pwsh' -Arguments '-NoProfile' -ArgumentList @('-NoProfile') } | Should -Throw '*cannot be combined*'
    }
  }
  It 'kills and throws when the process outlives the timeout' {
    InModuleScope Watchdog {
      { Invoke-ProcessWithTimeout -FileName 'pwsh' -Arguments '-NoProfile -Command "Start-Sleep -Seconds 30"' -TimeoutSec 2 } | Should -Throw '*timed out after 2 s*'
    }
  }
  It 'runs WSL commands as root in the configured distro' {
    InModuleScope Watchdog {
      Mock Invoke-ProcessWithTimeout { 'out' }
      Invoke-WslRootCommand -Distro 'Ubuntu' -Command 'echo hi' -TimeoutSec 5 | Should -Be 'out'
      Should -Invoke Invoke-ProcessWithTimeout -Times 1 -Exactly -ParameterFilter { $FileName -eq 'wsl.exe' -and $Arguments -eq '-d Ubuntu -u root -e sh -c "echo hi"' -and $TimeoutSec -eq 5 }
    }
  }
  It 'lists the largest processes by working set' {
    InModuleScope Watchdog {
      Mock Get-Process {
        @(
          [pscustomobject]@{ ProcessName = 'chrome'; WorkingSet64 = 2GB },
          [pscustomobject]@{ ProcessName = 'chrome'; WorkingSet64 = 1GB },
          [pscustomobject]@{ ProcessName = 'claude'; WorkingSet64 = 6GB },
          [pscustomobject]@{ ProcessName = 'idle'; WorkingSet64 = 1MB }
        )
      }
      @(Get-WslTopProcesses -Count 2) | Should -Be @('claude 6.0GB', 'chrome 3.0GB')
    }
  }
}
