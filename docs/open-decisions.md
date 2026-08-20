# Director decisions — 2026-08-20

Settled. Do not reopen in this repo without a new call.

| # | Question | Decision |
|---|---|---|
| 1 | Public or private? | **Public, once paths are config.** Hardcoded Robot paths are not an option. If a release still hardcodes them, it stays private. |
| 2 | Name | **`watchdog`.** That is the publish name. Do not rename to forge/guardian variants. |
| 3 | `saltroad_watchdog.ps1` | **Out of scope.** Left in `E:/AI/training/`. A RunPod/LoRA poller template is a later tool, not this product. |
| 4 | Distribution | **PowerShell module.** |
| 5 | Platform | **Windows-only in v1.** Linux is a later version, not a v1 path. |

## Consequences

- No default `Root` or kill-list paths. Config is required. Fail closed.
- `origin/` stays as a SHA-256 freeze of the pre-extraction scripts (those copies still contain Robot paths; they are forensic, not the product default).
- Module name: `Watchdog`. Cmdlets: `Get-WatchdogStatus`, `Start-Watchdog`, `Stop-Watchdog`.
- CI: `windows-latest` is justified. No Linux job in v1.
