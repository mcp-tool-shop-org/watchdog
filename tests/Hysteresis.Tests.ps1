BeforeAll {
  . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'Update-WatchdogBreach' {
  It 'stays ok and resets when there are no reasons' {
    $s = Update-WatchdogBreach -Count 2 -Reasons @() -BreachSamples 3
    $s.Count | Should -Be 0
    $s.State | Should -Be 'ok'
    $s.ShouldAbort | Should -BeFalse
  }

  It 'warns at 1/3 and 2/3 and does not abort' {
    $a = Update-WatchdogBreach -Count 0 -Reasons @('VRAM 31200MiB>=31200') -BreachSamples 3
    $a.State | Should -Be 'WARN(1/3)'
    $a.ShouldAbort | Should -BeFalse
    $b = Update-WatchdogBreach -Count 1 -Reasons @('VRAM 31200MiB>=31200') -BreachSamples 3
    $b.State | Should -Be 'WARN(2/3)'
    $b.ShouldAbort | Should -BeFalse
  }

  It 'aborts on the third consecutive breach (the gate that must be able to fire)' {
    $s = Update-WatchdogBreach -Count 2 -Reasons @('VRAM 31200MiB>=31200') -BreachSamples 3
    $s.State | Should -Be 'KILL'
    $s.ShouldAbort | Should -BeTrue
    $s.Count | Should -Be 3
  }

  It 'does not abort on a single spike' {
    $s = Update-WatchdogBreach -Count 0 -Reasons @('TEMP 90C>=87C') -BreachSamples 3
    $s.ShouldAbort | Should -BeFalse
  }
}
