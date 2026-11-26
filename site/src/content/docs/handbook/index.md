---
title: watchdog Handbook
description: How to run watchdog, the Windows GPU safety net for long jobs, and how to read what it records.
sidebar:
  order: 0
---

watchdog puts a hard ceiling under long GPU jobs on Windows. It checks your NVIDIA card's VRAM and
temperature and your system RAM every 2 seconds. When a limit you set stays crossed for three checks in a
row, it stops only the Python interpreters you listed, records what it saw, and tells you plainly when it
could not protect you.

Version 1 is **Windows-only** (PowerShell 7). Linux is planned for a later version.

## How it works

1. **Sample.** Every `IntervalSec` (2 s by default): GPU temperature, power and VRAM from `nvidia-smi`, and
   system RAM from Windows. Each sample goes to `_watchdog_log.csv` under your `Root` folder.
2. **Wait for a pattern.** A limit has to be crossed `BreachSamples` times in a row (3 by default) before
   anything happens. Each crossing on the way is logged as a warning, with the processes holding VRAM.
3. **Stop what you listed.** On a sustained breach it stops the `python` processes whose path is in
   `Targets`, plus an optional WSL `pkill` pattern. If nothing matched, it writes `_watchdog_NO_TARGET`: a
   protection gap, not a success.
4. **Prove it is alive.** The loop rewrites `_watchdog_HEARTBEAT` every sample. `watchdog status` and the
   optional scheduled poller judge liveness from that file.

## The one liveness check

```powershell
pwsh -File .\watchdog.ps1 status
```

Exit **0** running · **1** not running · **2** stale (it died hard).

Use this command rather than looking for the process by name: the checking command's own command line
contains the same text and matches itself, so a dead watchdog can look alive.

## In this handbook

- [Getting started](./getting-started/): requirements, install, first start with consent.
- [Daily use](./usage/): status, start, stop, and the Claude Code session hook.
- [Configuration](./configuration/): every setting, its default, and the WSL cache release.
- [Reference](./reference/): commands, exit codes, cmdlets, files under `Root`, error codes.
- [Operations](./operations/): warnings, a dead watchdog, a stop that killed nothing, recovery.
- [Security](./security/): what watchdog touches, what it never touches, and consent.
