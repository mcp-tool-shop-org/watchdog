---
title: Daily use
description: Status, start, stop. Never process-match.
sidebar:
  order: 2
---

```powershell
watchdog status          # the only correct liveness check
watchdog start -AllowKill
watchdog stop
watchdog poll            # one-shot; what the scheduled task runs
```

## Stop procedure

`watchdog stop` creates `_watchdog_STOP` and waits for the heartbeat to
go stale. The loop clears its own heartbeat on a clean stop.

**Never** `Get-Process` for `_watchdog`. The checking command's own
command line contains that string and self-matches.

## Start procedure (load-bearing order)

1. Request stop via the STOP sentinel
2. Wait for the old loop to exit
3. *Then* clear STOP / TRIPPED / DEAD
4. Relaunch detached
5. Verify the heartbeat actually appears

Removing STOP before the old loop notices it leaves two watchdogs.
`Start-Watchdog` encodes this so it is not re-derived.

## SessionStart hook

`watchdog status -Hook` emits Claude Code SessionStart JSON and always
exits 0 so a dead watchdog cannot break session start. Quiet when
healthy, loud when not. It is still pull-once — register the poller for
mid-session death.
