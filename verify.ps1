# verify — unit tests only. GPU abort dogfood is tests/dogfood and is not this command.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Get-Module Pester -ListAvailable | Where-Object { $_.Version.Major -ge 5 })) {
  Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
  Install-Module Pester -Force -SkipPublisherCheck -MinimumVersion 5.5.0 -Scope CurrentUser
}

Import-Module Pester -MinimumVersion 5.5.0
$cfg = New-PesterConfiguration
$cfg.Run.Path = Join-Path $PSScriptRoot 'tests'
$cfg.Run.Exit = $true
$cfg.Filter.ExcludeTag = @('dogfood')
$cfg.Output.Verbosity = 'Detailed'
Invoke-Pester -Configuration $cfg
