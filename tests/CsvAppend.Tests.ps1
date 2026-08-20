BeforeAll {
  . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'Initialize-WatchdogCsv (W-01, W-02)' {
  It 'creates a header when the file does not exist' {
    $path = Join-Path $TestDrive 'new.csv'
    $r = Initialize-WatchdogCsv -Path $path -Timestamp '2026-08-20T18:00:00.000Z'
    $r | Should -Be 'created'
    @(Get-Content $path)[0] | Should -Be 'timestamp,gpu_temp_c,gpu_power_w,vram_mib,ram_pct,ram_gb,sd_python_pids,state'
  }

  It 'does not truncate prior telemetry on a second start' {
    $path = Join-Path $TestDrive 'keep.csv'
    Initialize-WatchdogCsv -Path $path -Timestamp '2026-08-20T12:56:38.000Z'
    '2026-08-20T12:56:38.000Z,74,200,20480,40,32,1234,ok' | Add-Content $path
    $r = Initialize-WatchdogCsv -Path $path -Timestamp '2026-08-20T13:32:00.000Z'
    $r | Should -Be 'appended'
    $rows = Get-Content $path
    $rows.Count | Should -Be 3
    $rows[1] | Should -Match '12:56:38'
    $rows[2] | Should -Match 'restart'
  }
}
