---
title: Getting started
description: Install the PowerShell module, write a config, start with consent.
sidebar:
  order: 1
---

## Requirements

- Windows
- PowerShell 7 (`pwsh`)
- `nvidia-smi` on PATH
- A directory you own for telemetry (`Root`)

## Install from a clone

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
```

Edit `Root`, `Targets`, `VramKillMiB`, `RamKillPct`, `TempKillC`. There
is no default kill list and no silent hardware envelope.

## Start

```powershell
pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status
```

`-AllowKill` is required unless the config already has `AllowKill = $true`.
Starting while VRAM is already over the ceiling **refuses** (exit 3)
unless you pass `-Force`.

## Optional poller

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Register-WatchdogPoll
```

A CurrentUser scheduled task. It writes `_watchdog_DEAD` if the heartbeat
goes stale. It never restarts the loop.

## Verify (no GPU)

```powershell
pwsh -File .\verify.ps1             # 175 unit tests
pwsh -File .\verify.ps1 -Coverage   # measures Private/ and Public/; fails below 90%
```

Every kill, watchdog launch, scheduled-task call and module copy in the tests is
mocked, so running them never touches existing machine processes or tasks; some
tests (`tests/Cli.Tests.ps1`, `tests/Helpers.Tests.ps1`) start short-lived `pwsh`
child processes. CI's own floor fails the build below 90% for the measured module
(`src/Watchdog/Private` and `src/Watchdog/Public` only; `Watchdog.psm1`,
`watchdog.ps1` and `watchdog-loop.ps1` are not measured) via
`verify.ps1 -MinCoverage 90`. CI uploads the report to Codecov, which checks
every change at 90% while Codecov's whole-module status allows one point below.
