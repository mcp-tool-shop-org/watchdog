---
title: Operations
description: Warn, critical, recovery after ABORT, NO_TARGET gap.
sidebar:
  order: 5
---

## Warn

Kill log lines `WARN(n/3)` plus VRAM holders. The job is still alive. If
it is ComfyUI near 31.2 GB, cap it. Do not raise `VramKillMiB`.

## Critical — heartbeat stale (exit 2)

The GPU is unprotected. A hard kill cannot write `_watchdog_DEAD`; the
poller can.

1. Read `_watchdog_DEAD`, `_watchdog_console.log`, `_watchdog_crash.log`, the CSV tail. The CSV is **not** truncated on the next start.
2. Check VRAM. If already over the ceiling, do not start (exit 3). Cap the consumer first.
3. `watchdog start -AllowKill`
4. Confirm exit 0.

## `_watchdog_NO_TARGET`

A breach fired and killed nothing. That is a **gap**. Add the holder to
`Targets`. The 2026-08-04 burst logged 153 ABORTs at 31.9 GB with zero
kills and no named holder — `Get-VramHolders` exists because of that.

## After an ABORT

The job is dead. Last flushed checkpoint is the recover point. Relaunch
the consumer under the envelope. The watchdog does not restart training.
See [docs/compensators.md](https://github.com/mcp-tool-shop-org/watchdog/blob/main/docs/compensators.md).

## WSL cache log

With `WslCacheRelease` on, `_watchdog_wslcache.log` under `Root` records:

- `heartbeat` once per clock hour, with Windows used, free and `vmmemWSL`
  (proof the release check is alive);
- `DROPPED`, with the cache size dropped and memory before and after;
- `no drop`, when the VM was large but its cache was small, meaning real
  process memory is holding it;
- `skip`, when the VM was large but `WslDistro` was not running (another
  distro is holding the VM up). A run of skips logs one line, and at most
  one an hour;
- `ALERT`, with the top five processes, when Windows is still at or above
  `WslCacheAlertPct` after a drop. That memory is held by processes, not
  cache, and the watchdog will not free it. Find the process;
- `ERROR`, when a `wsl.exe` call failed or timed out. The poll carries on.

## Replacing an existing watchdog script

If a machine already runs a copy of the old `_watchdog.ps1`, stopping it
and starting this module is a deliberate change, not a side effect
of cloning the repo.
