---
title: watchdog Handbook
description: Operational handbook for the Windows VRAM watchdog.
sidebar:
  order: 0
---

watchdog samples NVIDIA GPU temp, power, and VRAM plus system RAM every
2 seconds. After 3 consecutive breaches it kills only the interpreters
you listed.

v1 is **Windows-only** (PowerShell 7). Linux is a later version.

## The only correct check

```powershell
pwsh -File .\watchdog.ps1 status
```

Exit **0** running · **1** no heartbeat · **2** stale (died hard).

Do not process-match on `_watchdog`. Do not invent a heartbeat-age
check. A dead watchdog and a healthy one look identical unless you ask.

## Next

- [Install](./getting-started/)
- [Daily use](./usage/)
- [Config](./configuration/)
- [Commands](./reference/)
- [Warn / critical / recovery](./operations/)
- [Threat model](./security/)
