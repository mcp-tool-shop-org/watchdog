<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/watchdog/readme.png" alt="watchdog" width="400">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
</p>

# watchdog

Windows VRAM / RAM / temp watchdog for NVIDIA GPUs. It samples every 2
seconds. After 3 consecutive breaches it kills **only** the interpreters
you listed — and it says so when a breach kills nothing.

```powershell
watchdog status    # exit 0 running · 1 no heartbeat · 2 stale (died hard)
watchdog start -AllowKill
watchdog stop
```

Do not hand-roll a heartbeat-age check. Do not process-match on
`_watchdog`. Those two mistakes are how a dead watchdog and a healthy
one look identical.

**v1 is Windows-only** (PowerShell 7, nvidia-smi, WDDM process-memory
counters, optional WSL `pkill`). Linux is a later version.

## Install

PowerShell 7.1+. Clone, copy the example config, edit it, start:

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1
pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status
```

Or import the module:

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Start-Watchdog -AllowKill
Get-WatchdogStatus
Register-WatchdogPoll   # scheduled task: detect death, never restart
```

`Install-Watchdog` copies the module into your CurrentUser module path.

## Config

There is **no default Root and no default kill list.** The module refuses
to start without a config. Search order: `-ConfigPath`,
`$env:WATCHDOG_CONFIG`, `./watchdog.config.psd1`, `~/.watchdog/config.psd1`.

Required fields: `Root`, `Targets`, `VramKillMiB`, `RamKillPct`,
`TempKillC`. Relative paths are rejected. Writes stay under `Root`.

`VramKillMiB = 31200` is the documented bound for a 32 GB card (~1.4 GB
below a 32607 MiB WDDM ceiling). Do **not** raise it to stop ComfyUI
trips — cap ComfyUI (`--reserve-vram`) instead.

## Commands

| Command | What it does |
|---|---|
| `watchdog status` | Liveness. The only correct check. |
| `watchdog start -AllowKill` | Sentinel-stop, wait, clear, detached launch, verify heartbeat |
| `watchdog stop` | STOP sentinel, wait. Never process-match. |
| `watchdog poll` | One-shot: if heartbeat is stale, write `_watchdog_DEAD` from the outside |
| `watchdog help` | Flags and exit codes |
| `watchdog version` | `1.0.0` |

`status` / `poll` exit codes: **0** running · **1** no heartbeat · **2**
stale. `start` also uses **3** (VRAM already over ceiling), **4** (old
loop did not stop), **5** (no heartbeat after launch).

`-Hook` on status emits Claude Code SessionStart JSON and always exits 0
so a dead watchdog cannot break session start.

## What it kills

Only `python` processes whose `Path` is in `Targets`, plus an optional
WSL `pkill -f` pattern (empty = disabled). Other Python is spared. A
breach that matches nothing writes `_watchdog_NO_TARGET` — that is a
protection **gap**, not success.

Consent: `-AllowKill` (or `AllowKill = $true` in config). The poller
never kills and never auto-restarts; auto-restart can abort a live job.

## Threat model

- **Touched:** files under `Root` (heartbeat, CSV, kill/console/crash logs, sentinels); process list; GPU counters; optional local WSL pkill.
- **Not touched:** your source tree, checkpoints, credentials, the network.
- **Permissions:** the user who starts it can kill the configured interpreters. There is no extra service account.
- **No telemetry** leaves the machine. No secrets in logs.
- **Irreversible action:** ABORT. See [docs/compensators.md](docs/compensators.md).

## Tests

```powershell
pwsh -File .\verify.ps1
```

32 unit tests, no GPU. Parser fixtures include the malformed nvidia-smi
output that killed the loop on 2026-06-12. The hardware abort test stays
local and is not greened in CI.

## Origin

This is an extraction of a watchdog that already ran on a 5090. The
pre-extraction scripts are frozen under [`origin/`](origin/) with
SHA-256 pins. Dated incidents (parse crash, five-week hole, unguarded
ai-toolkit, 153 empty ABORTs, one-sample death) are in
[docs/incidents.md](docs/incidents.md).

## License

MIT. See [LICENSE](LICENSE). Supported: 1.x.

Built by [MCP Tool Shop](https://mcp-tool-shop.github.io/).
