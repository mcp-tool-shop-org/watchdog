---
title: Reference
description: Commands, exit codes, module cmdlets.
sidebar:
  order: 4
---

## CLI

```
watchdog status   [-ConfigPath <path>] [-Brief] [-Hook]
watchdog start    [-ConfigPath <path>] -AllowKill [-Force]
watchdog stop     [-ConfigPath <path>]
watchdog poll     [-ConfigPath <path>]
watchdog install  [-ConfigPath <path>] [-Poll]
watchdog uninstall
watchdog help
watchdog version
```

## Exit codes

**status / poll:** 0 running · 1 no heartbeat · 2 stale (died hard)

**start:** 0 up · 1 usage/config · 3 VRAM already over ceiling · 4 old loop did not stop · 5 launch failed

**Hook mode** always exits 0.

## Module cmdlets

`Get-WatchdogStatus`, `Start-Watchdog`, `Stop-Watchdog`,
`Invoke-WatchdogPoll`, `Register-WatchdogPoll`, `Unregister-WatchdogPoll`,
`Get-WatchdogConfig`, `Install-Watchdog`, `Uninstall-Watchdog`

PowerShell 7. Module version **1.0.0**. Manifest:
`src/Watchdog/Watchdog.psd1`.

## Errors

User-facing errors are `code`, `message`, `hint`, `cause?`, `retryable?`.
Example: `CONFIG_ALLOWKILL_REQUIRED`, `CONFIG_MISSING`,
`STATE_VRAM_ALREADY_OVER`, `RUNTIME_LAUNCH_FAILED`.
