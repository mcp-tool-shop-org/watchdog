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
(WSL abort disabled).

## The 31200 bound

On a 32607 MiB card, 31200 leaves ~1.4 GB of WDDM headroom. ComfyUI
Qwen-Image inference can peak at 31.2–31.3 GB and **will** trip it. The
fix is to cap ComfyUI (`--reserve-vram`), not to raise this number.
