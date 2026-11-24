---
title: Configuration
description: Required fields, search order, 31200 ceiling.
sidebar:
  order: 3
---

Search order:

1. `-ConfigPath`
2. `$env:WATCHDOG_CONFIG`
3. `./watchdog.config.psd1`
4. `~/.watchdog/config.psd1`

Missing config is a hard refuse (`CONFIG_MISSING`). Relative `Root` or
`Targets` paths are a hard refuse (`CONFIG_PATH_NOT_ABSOLUTE`).

## Required

| Field | Why |
|---|---|
| `Root` | Absolute directory for heartbeat, CSV, logs, sentinels. Writes never leave it. |
| `Targets` | Absolute interpreter paths the abort may kill. Empty list is a protection gap. |
| `VramKillMiB` | No silent default. 31200 is the documented 32 GB / RTX 5090 example. |
| `RamKillPct` | System RAM percent. |
| `TempKillC` | GPU temp Celsius. |

## Defaults if omitted

`IntervalSec = 2`, `BreachSamples = 3`, `StaleSec = 15`,
`PollIntervalSec = 30`, `AllowKill = $false`, `WslKillPattern = ''`
(WSL abort disabled), `WslCacheRelease = $false`.

`Register-WatchdogPoll` registers the poller every
`max(60, PollIntervalSec)` seconds: Windows scheduled-task repetition
cannot go below one minute.

## WSL file-cache release (opt-in)

The WSL VM (`vmmemWSL`) keeps Linux file cache from large reads, such as
container image pulls. WSL's `autoMemoryReclaim` only gives it back when
the VM is idle, and a running container engine keeps it busy. With
`WslCacheRelease = $true`, each poll:

1. reads `vmmemWSL` and Windows memory from the Windows side (a stopped VM
   is never started);
2. acts when `vmmemWSL >= WslCacheHighGB`, or when Windows used
   `>= WslCacheWinHighPct` and `vmmemWSL >= WslCacheMinGB`, at most once
   per `WslCacheCooldownSec`;
3. skips, and logs a `skip` line, when `WslDistro` is not running. Another
   distro (a container engine's) can keep the VM up while yours is stopped,
   and `wsl -d` would start it; listing the running distros starts nothing,
   and the listing has the same `WslCacheTimeoutSec` timeout as every other
   `wsl.exe` call;
4. drops the page cache in `WslDistro` (`sync; echo 1 > /proc/sys/vm/drop_caches`
   as root) only if the Linux cache is `>= WslCacheMinCacheGB`.

It never kills a process, and a failure is logged, never thrown into the
poll. The poll checks the watchdog's heartbeat first and runs the release
after it, so the release can never delay the report of a dead loop.

| Field | Default | Meaning |
|---|---|---|
| `WslCacheRelease` | `$false` | Turns the feature on. |
| `WslCacheHighGB` | `16` | Act when `vmmemWSL` reaches this many GB. |
| `WslCacheMinGB` | `8` | With Windows under pressure, act from this size. |
| `WslCacheWinHighPct` | `80` | Windows memory used, in percent, that counts as pressure. |
| `WslCacheMinCacheGB` | `6` | Do not drop a cache smaller than this. |
| `WslCacheAlertPct` | `90` | Log an `ALERT` if Windows is still at or above this after a drop. |
| `WslCacheCooldownSec` | `300` | Minimum time between drops. |
| `WslCacheTimeoutSec` | `90` | Hard timeout for each `wsl.exe` call. |
| `WslCacheSettleSec` | `10` | Wait before re-reading memory after a drop. |

Each value must be a positive number (`WslCacheSettleSec` may be 0), and
the two percentages at most 100; anything else is `CONFIG_INVALID`.

## The 31200 bound

On a 32607 MiB card, 31200 leaves ~1.4 GB of WDDM headroom. ComfyUI
Qwen-Image inference can peak at 31.2–31.3 GB and **will** trip it. The
fix is to cap ComfyUI (`--reserve-vram`), not to raise this number.
