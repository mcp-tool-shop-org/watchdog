# verify — unit tests only. GPU abort dogfood is tests/dogfood and is not this command.
#   pwsh -File .\verify.ps1            unit tests
#   pwsh -File .\verify.ps1 -Coverage  unit tests + line coverage of src/Watchdog/Private and src/Watchdog/Public
#                                      only (Watchdog.psm1, watchdog.ps1 and watchdog-loop.ps1 are not measured;
#                                      JaCoCo coverage.xml); fails below -MinCoverage (default 90), as CI does
param(
  [switch]$Coverage,
  [double]$MinCoverage = 90
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 })) {
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
  Install-Module Pester -Force -SkipPublisherCheck -MinimumVersion 5.5.0 -Scope CurrentUser
}

Import-Module Pester -MinimumVersion 5.5.0
$cfg = New-PesterConfiguration
$cfg.Run.Path = Join-Path $PSScriptRoot 'tests'
$cfg.Run.Exit = $false
$cfg.Run.PassThru = $true
$cfg.Filter.ExcludeTag = @('dogfood')
$cfg.Output.Verbosity = 'Detailed'

if ($Coverage) {
  # Product code only. origin/ is a SHA-256 freeze of the pre-extraction scripts (forensic, not shipped).
  $cfg.CodeCoverage.Enabled = $true
  $cfg.CodeCoverage.Path = @(
    (Join-Path $PSScriptRoot 'src\Watchdog\Private'),
    (Join-Path $PSScriptRoot 'src\Watchdog\Public')
  )
  $cfg.CodeCoverage.OutputFormat = 'JaCoCo'
  $cfg.CodeCoverage.OutputPath = Join-Path $PSScriptRoot 'coverage.xml'
  $cfg.CodeCoverage.CoveragePercentTarget = $MinCoverage
}

$result = Invoke-Pester -Configuration $cfg

if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
  Write-Host "verify: $($result.FailedCount) test(s) failed."
  exit 1
}
if ($Coverage) {
  $pct = [math]::Round($result.CodeCoverage.CoveragePercent, 2)
  if ($pct -lt $MinCoverage) {
    Write-Host "verify: line coverage $pct% is below the $MinCoverage% floor."
    exit 1
  }
  Write-Host "verify: line coverage $pct% (floor $MinCoverage%)."
}
exit 0
