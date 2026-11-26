<p align="center">
  <a href="README.md">English</a> | <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/watchdog/readme.png" alt="watchdog" width="400">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/watchdog/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://codecov.io/gh/mcp-tool-shop-org/watchdog"><img src="https://codecov.io/gh/mcp-tool-shop-org/watchdog/graph/badge.svg" alt="Coverage"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
  <a href="https://mcp-tool-shop-org.github.io/watchdog/"><img src="https://img.shields.io/badge/Landing_Page-live-blue" alt="Landing Page"></a>
</p>

# watchdog

**A hard ceiling for long GPU jobs on Windows.** watchdog checks your NVIDIA card's VRAM and temperature and your
system RAM every 2 seconds. When a limit stays crossed for three checks in a row, it stops the Python interpreters
you allowed it to stop, and nothing else.

You start a training run or a big render, walk away, and a leak, an oversized batch or a hot card turns it into a
frozen desktop. watchdog is the small process that stays awake for you: it enforces the limits you set, records
what it saw, and tells you plainly when it could not protect you.

## What you get

- **Limits you choose.** VRAM in MiB, RAM in percent, GPU temperature in °C. There are no hidden defaults.
- **Targeted stops.** Only the interpreter paths you list (plus an optional WSL process pattern) can be stopped.
  Every other Python process on the machine is left alone.
- **No false comfort.** A breach that matched none of your listed processes is written down as a protection gap,
  and the processes holding the VRAM are named.
- **A watchdog for the watchdog.** An optional scheduled task checks the heartbeat once a minute and marks the
  watchdog dead from the outside if it stopped. It never restarts anything on its own.
- **A clear liveness answer.** `watchdog status` exits 0 (running), 1 (not running) or 2 (died hard).
- **A record of every run.** A CSV of samples, a kill log, a console transcript and a crash log, all kept under
  one folder you choose.
- **Optional WSL memory return.** If WSL's file cache crowds Windows memory, the poller can drop that cache. It
  never stops a process and never starts a stopped distro.

## Quick start

Requirements: Windows, PowerShell 7 or newer, and an NVIDIA driver with `nvidia-smi` on `PATH`.

```powershell
git clone https://github.com/mcp-tool-shop-org/watchdog.git
cd watchdog
mkdir $HOME\.watchdog
copy src\Watchdog\config\watchdog.example.psd1 $HOME\.watchdog\config.psd1
notepad $HOME\.watchdog\config.psd1      # set Root, Targets and your three limits

pwsh -File .\watchdog.ps1 start -AllowKill
pwsh -File .\watchdog.ps1 status        # exit 0 = protected
```

`-AllowKill` is your consent: watchdog will not start without it, or without `AllowKill = $true` in the config.
To install it as a module and add the outside check:

```powershell
Import-Module .\src\Watchdog\Watchdog.psd1
Install-Watchdog          # copy the module to your CurrentUser module path
Register-WatchdogPoll     # scheduled task: detects a dead watchdog, never restarts it
```

## How it works

1. **Sample.** Every `IntervalSec` (2 s by default) it reads GPU temperature, power and VRAM from `nvidia-smi`, and
   system RAM from Windows.
2. **Wait for a pattern, not a spike.** A limit has to be crossed `BreachSamples` times in a row (3 by default)
   before anything happens. Warnings are logged on the way.
3. **Stop only what you listed.** On a sustained breach it stops the `python` processes whose path is in `Targets`,
   and runs the optional WSL `pkill` pattern. It records what it stopped, or that it stopped nothing.
4. **Prove it is alive.** The loop rewrites a heartbeat file every sample. `watchdog status` and the scheduled
   poller judge liveness from that heartbeat, so a dead watchdog can never look healthy.

## Commands

| Command | What it does |
|---|---|
| `watchdog status` | Liveness check. Exit 0 running, 1 not running, 2 died hard. |
| `watchdog start -AllowKill` | Stops any old loop cleanly, starts a new one in the background, and waits for its heartbeat. |
| `watchdog stop` | Asks the loop to stop through a sentinel file and waits for it. |
| `watchdog poll` | One outside check, as run by the scheduled task. |
| `watchdog install` / `uninstall` | Copy or remove the module. `install -Poll` also registers the scheduled check. |
| `watchdog help` / `version` | Flags, exit codes and the version. |

`start` refuses with exit 3 if VRAM is already over your ceiling (use `-Force` only if you mean it). `status -Hook`
prints a Claude Code SessionStart message and always exits 0, so a dead watchdog is reported without breaking the
session. Full reference: [handbook → Reference](https://mcp-tool-shop-org.github.io/watchdog/handbook/reference/).

## Configuration

watchdog will not start without a config. It looks in `-ConfigPath`, then `$env:WATCHDOG_CONFIG`, then
`./watchdog.config.psd1`, then `~/.watchdog/config.psd1`.

| Required | Meaning |
|---|---|
| `Root` | Absolute folder for the heartbeat, logs and sentinels. watchdog writes nowhere else. |
| `Targets` | Absolute interpreter paths it may stop. |
| `VramKillMiB` | VRAM ceiling in MiB. For a 32 GB card, `31200` leaves about 1.4 GB of headroom. |
| `RamKillPct` | System RAM ceiling in percent. |
| `TempKillC` | GPU temperature ceiling in °C. |

If a job trips the VRAM ceiling in normal use, cap the job (for ComfyUI, `--reserve-vram`) rather than raising the
ceiling. Every other setting, including the WSL cache release, is in
[handbook → Configuration](https://mcp-tool-shop-org.github.io/watchdog/handbook/configuration/).

## Safety

- **Consent first.** Nothing is ever stopped without `-AllowKill` or `AllowKill = $true`.
- **Touched:** files under `Root`, the process list, GPU counters; and, only if you enable them, a WSL `pkill`
  pattern and the WSL page-cache drop.
- **Not touched:** your source trees, checkpoints, credentials and the network. No telemetry leaves the machine.
- **The one irreversible action is the stop itself.** A stopped job loses whatever it had not saved. What is lost,
  and how to recover, is in [docs/compensators.md](docs/compensators.md).

See [SECURITY.md](SECURITY.md) to report a vulnerability.

## Platform

Version 1 is Windows-only: it relies on PowerShell 7, `nvidia-smi`, the Windows GPU process-memory counters and,
optionally, WSL. Linux support is planned for a later version.

## Development

```powershell
pwsh -File .\verify.ps1             # unit tests, no GPU needed
pwsh -File .\verify.ps1 -Coverage   # adds line coverage; CI fails below 90%
```

Every stop, launch and scheduled-task call in the tests is mocked, so running them never touches real processes.
The pre-extraction scripts are kept, hash-pinned, under [`origin/`](origin/), and the incidents that shaped the
design are in [docs/incidents.md](docs/incidents.md).

## License

MIT. See [LICENSE](LICENSE).

Built by [MCP Tool Shop](https://mcp-tool-shop.github.io/).
