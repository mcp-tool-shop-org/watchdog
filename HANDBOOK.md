# Watchdog handbook

Daily ops for the VRAM watchdog. v1 is Windows-only. PowerShell 7.

## Daily

```powershell
pwsh -File .\watchdog.ps1 status
# exit 0 running · 1 no heartbeat · 2 stale (died hard)
```

Do not hand-roll a heartbeat-age check. Do not process-match on `_watchdog`.
The 2026-08-20 incident was two operators, hours apart, each deriving a
worse check while the right one sat on disk.

Install once:

```powershell
Copy-Item src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
# edit Root, Targets, VramKillMiB / RamKillPct / TempKillC
Import-Module .\src\Watchdog\Watchdog.psd1
Start-Watchdog -AllowKill
Register-WatchdogPoll   # detect-only, every PollIntervalSec; never restarts
```

## Warn

CSV `state=WARN(n/3)` or kill-log lines that name holders. The job is still
alive. If it is ComfyUI peeking at 31.2 GB, cap it (`--reserve-vram`). Do
not raise `VramKillMiB`.

## Critical

`watchdog status` exit 2 — heartbeat stale. GPU is unprotected.

1. Read `_watchdog_DEAD`, `_watchdog_console.log`, `_watchdog_crash.log`, tail of `_watchdog_log.csv`. The CSV is no longer truncated on start.
2. Check VRAM. If it is already at/over the ceiling, **do not** start. Cap the consumer first (start exit 3).
3. `watchdog start -AllowKill`
4. Confirm exit 0 and a moving heartbeat.

`_watchdog_NO_TARGET` means a breach fired and killed nothing. That is a
gap. Add the holder to `Targets`. The 2026-08-04 burst was this.

## Recovery after an ABORT

The job is dead. Last checkpoint is the recover point. Relaunch the
consumer so it stays under the envelope; then leave the watchdog running.
See [docs/compensators.md](docs/compensators.md).

## Stop

```powershell
pwsh -File .\watchdog.ps1 stop
```

STOP sentinel, then wait. Never kill by process name.

## Live studio instance

On the Robot rig the process that is protecting the GPU **right now** is
still `E:\AI\training\_watchdog*.ps1`. This module does not replace it
until the Director approves cutover.
