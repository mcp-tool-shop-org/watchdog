# watchdog — PowerShell VRAM watchdog

Product: Windows-only PowerShell module. Live process on this rig is
still `E:/AI/training/_watchdog*.ps1` until the Director approves cutover.
**Do not move, rename, or edit those files.**

```
pwsh -NoProfile -File E:\AI\training\_watchdog_status.ps1
```

Exit 0 running · 1 no heartbeat · 2 stale.

## Extraction, not greenfield

`origin/` is a SHA-256 freeze of the four live scripts as of 2026-08-20.
`src/Watchdog/` is the product. Dated scar tissue in comments is
load-bearing. See `docs/incidents.md`.

## Director decisions (2026-08-20)

- Public once paths are config (they are). Name is **watchdog**.
- `saltroad_watchdog.ps1` is out of scope.
- PowerShell module. Windows v1; Linux later.
- No default Root or kill list. Fail closed. `-AllowKill` required.
- 31200 of 32607 is the 32 GB example. Do not raise it to silence ComfyUI.

## Tests

`pwsh -File .\verify.ps1` — no GPU. Hardware abort is `tests/dogfood`.
