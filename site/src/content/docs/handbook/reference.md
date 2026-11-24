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

PowerShell 7. Module version **1.1.2**. Manifest:
`src/Watchdog/Watchdog.psd1`.

## Files under Root

`_watchdog_HEARTBEAT`, `_watchdog_log.csv`, `_watchdog_KILL.log`,
`_watchdog_console.log`, `_watchdog_crash.log`, `_watchdog_poll_last.json`
(when the last poll began and wrote it, its state and exit code, and for the
scheduled task's polls its registration token), the sentinels
`_watchdog_DEAD`, `_watchdog_STOP`, `_watchdog_TRIPPED`,
`_watchdog_NO_TARGET`, and with `WslCacheRelease` on,
`_watchdog_wslcache.log` (rotated to `.1` at 1 MB), `_watchdog_wslcache.last`
(time of the last drop) and `_watchdog_wslcache.hb` (hour of the last
heartbeat line).

## Errors

User-facing errors are `code`, `message`, `hint`, `cause?`, `retryable?`.
Example: `CONFIG_ALLOWKILL_REQUIRED`, `CONFIG_MISSING`, `CONFIG_INVALID`,
`STATE_VRAM_ALREADY_OVER`, `RUNTIME_LAUNCH_FAILED`.
