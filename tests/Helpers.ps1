$script:WatchdogRoot = Split-Path $PSScriptRoot -Parent
$script:WatchdogModule = Join-Path $script:WatchdogRoot 'src\Watchdog'
$script:WatchdogPrivate = Join-Path $script:WatchdogModule 'Private'
$script:WatchdogExample = Join-Path $script:WatchdogModule 'config\watchdog.example.psd1'

Get-ChildItem -Path (Join-Path $script:WatchdogPrivate '*.ps1') | ForEach-Object { . $_.FullName }

function Get-WatchdogTestDir([string]$Name) {
  $base = (Get-Item -LiteralPath $TestDrive).FullName
  Join-Path $base $Name
}

function New-WatchdogTestConfig {
  param(
    [string]$Root,
    [string[]]$Targets = @('C:\watchdog-test\python.exe'),
    [int]$VramKillMiB = 31200,
    [int]$RamKillPct = 90,
    [int]$TempKillC = 87,
    [int]$StaleSec = 15,
    [bool]$AllowKill = $false
  )
  $dir = Split-Path $Root -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
  $path = Join-Path $Root 'watchdog.config.psd1'
  $targetLines = ($Targets | ForEach-Object { "    '$_'" }) -join ",`n"
  @"
@{
  Root = '$($Root.Replace('\','\\'))'
  Targets = @(
$targetLines
  )
  VramKillMiB = $VramKillMiB
  RamKillPct = $RamKillPct
  TempKillC = $TempKillC
  StaleSec = $StaleSec
  AllowKill = $(if ($AllowKill) { '$true' } else { '$false' })
  IntervalSec = 2
  BreachSamples = 3
  WslKillPattern = ''
  PollIntervalSec = 30
}
"@ | Set-Content -Path $path
  $path
}
