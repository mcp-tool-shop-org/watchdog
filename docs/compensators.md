# Irreversible actions and compensators

This tool's purpose is to **kill processes**. An ABORT destroys in-flight
training, ComfyUI graphs, and TRELLIS jobs with unsaved state. The table
is the product's safety argument. No skip.

| Action | What is lost | Compensator | Post-rollback state | Owner | Undo window |
|---|---|---|---|---|---|
| ABORT kills guarded Windows interpreters (`Stop-Process -Force` on configured `Targets`) | In-flight GPU job. Weights/checkpoints only as far as the job had flushed. ComfyUI unsaved graphs. | Re-launch the job from the last checkpoint. If that was ComfyUI, relaunch **capped** (`--reserve-vram`) so the next peak does not trip 31200. Do not raise the ceiling. | Process is gone. Heartbeat keeps beating. `_watchdog_TRIPPED` names reasons + acts. | Operator who started the GPU job | none — unsaved state is gone |
| ABORT `wsl pkill -9 -f` of `WslKillPattern` | Matching WSL training process, same as above | Same as row 1. Pattern is opt-in and empty by default. | WSL process gone if the distro was already up (a cold VM is not started mid-emergency) | Operator | none |
| ABORT fires and kills **nothing** | **Protection gap**, not success. GPU stays over ceiling. 2026-08-04: 153 ABORTs, VRAM 31.9 GB, zero kills, no holder named. | `_watchdog_NO_TARGET` is written. Operator must add the holding interpreter to `Targets` (or stop it by hand) and restart the watchdog. `Get-VramHolders` names the PID on the breach path. | Job still running. Sentinel says so. | Operator + whoever owns the kill list | until the holder is on `Targets` |
| `Start-Watchdog -Force` while VRAM is already over the ceiling | The running GPU job, within ~`IntervalSec * BreachSamples` seconds | Don't. Cap the consumer first. `-Force` is the named override; default start **refuses** (exit 3). | Same as ABORT | Operator who passed `-Force` | none |
| `Start-Watchdog` without waiting for the old loop (if someone process-matches) | Two loops, or the starter kills itself | Encoded procedure: STOP sentinel, wait, *then* clear, *then* launch. Never process-match on `_watchdog`. | One loop, verified heartbeat | `Start-Watchdog` | n/a if the procedure is used |
| Poller declares DEAD | Nothing killed. The GPU is already unprotected. | `watchdog start -AllowKill` after reading VRAM. If VRAM is near the ceiling, cap the consumer first. Poller **never auto-restarts**. | `_watchdog_DEAD` from the outside; console/crash tail preserved | Operator | until someone starts it |
| `Install-Watchdog` copies the module; `Register-WatchdogPoll` registers a scheduled task | User module path + a CurrentUser task that only polls | `Uninstall-Watchdog` / `Unregister-WatchdogPoll`. Config and `Root` telemetry are **not** deleted. | Module copy gone; telemetry remains | Operator | forever |
| Cutover from `E:/AI/training/_watchdog*.ps1` to this module | Live protection if the old loop is stopped and the new one is not verified | Director-approved only. Stop via sentinel, start the module with the Robot config, verify `watchdog status` exit 0. Keep the old scripts on disk until that heartbeat is proven. | One loop, from this repo | Director | until the old files are deleted (they must not be, as a side effect of this repo) |

## What an ABORT kills

Only processes whose `Path` is in `Targets` (Windows `python` with that exact interpreter path) plus an optional WSL pattern. Other python is spared. That targeting is load-bearing.

## What state is lost

Whatever the killed job had not flushed. There is no snapshot, no drain, no polite Ctrl+C. The 2 s × 3 sample hysteresis is the only grace.

## Who owns recovery

The operator who started the GPU job. The watchdog owns the abort. It does not own restarting training.

## Consent

`Start-Watchdog` refuses without `-AllowKill` (or `AllowKill = $true` in config). That gate is tested and can fail.
