BeforeAll {
  . (Join-Path $PSScriptRoot 'Helpers.ps1')
}

Describe 'Parse-GpuSample' {
  It 'parses a clean csv line' {
    $raw = Get-Content (Join-Path $PSScriptRoot 'fixtures\nvidia-smi-ok.txt')
    $g = Parse-GpuSample $raw
    $g.Temp | Should -Be 74
    $g.Power | Should -Be '220.12'
    $g.Vram | Should -Be 20480
  }

  It 'skips warning lines and takes the first shaped temp,power,vram line (2026-06-12)' {
    $raw = Get-Content (Join-Path $PSScriptRoot 'fixtures\nvidia-smi-warning-then-ok.txt')
    $g = Parse-GpuSample $raw
    $g.Temp | Should -Be 75
    $g.Vram | Should -Be 8192
  }

  It 'throws on the malformed multi-line output that killed the loop on 2026-06-12' {
    $raw = Get-Content (Join-Path $PSScriptRoot 'fixtures\nvidia-smi-malformed.txt')
    { Parse-GpuSample $raw } | Should -Throw -ExpectedMessage '*no parseable GPU line*'
  }

  It 'throws when nvidia-smi stringifies as Object[] with no shaped line' {
    $raw = @('foo', 'bar', 12)
    { Parse-GpuSample $raw } | Should -Throw -ExpectedMessage '*no parseable GPU line*'
  }

  It 'accepts whitespace around fields' {
    $g = Parse-GpuSample @('  87 ,  99.0 ,  31200  ')
    $g.Temp | Should -Be 87
    $g.Vram | Should -Be 31200
  }
}
