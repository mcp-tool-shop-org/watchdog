# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-11-24

### Changed

- The landing page and handbook are back on GitHub Pages (Pages could not be enabled while the repository was private). The deploy workflow pins every action to a commit SHA, audits the site's dependencies, and checks that the landing page and the handbook both return 200 after each deploy. The handbook documents the WSL cache release, its log, and the coverage bar.

### Added

- **WSL file-cache release (opt-in, `WslCacheRelease`).** The poller drops the Linux page cache when the WSL VM crowds Windows memory, reading memory from the Windows side so it never wakes a stopped VM, and acting only when `WslDistro` is already running, so a distro stopped while another one (a container engine's) keeps the VM up is never started. It has thresholds, a cooldown and a timeout, never kills a process, and logs to `_watchdog_wslcache.log` (hourly heartbeat, each drop, each run of skips, and an alert if Windows stays high).
- **Coverage bar of 90%.** `verify.ps1 -Coverage` measures line coverage of `src/Watchdog` and fails below 90%. CI runs it and uploads the JaCoCo report to Codecov through OIDC, with `codecov.yml` project and patch targets at 90%. Coverage went from 38% to 96%, with tests for the loop, status, start, stop, install, poll registration and helpers.

### Fixed

- The loop no longer dies when its heartbeat file is locked; it retries the write three times and logs a skipped write.
- `Register-WatchdogPoll` registers with a 60 s minimum interval and a 10-year repetition duration (Windows rejects `TimeSpan.MaxValue`), and throws unless the task exists afterwards.

### Security

- The CI workflow declares `permissions: contents: read` at the top level, so no job gets more than read access unless it sets its own.

## [1.0.0] - 2026-08-20

Extraction of a working VRAM watchdog from four PowerShell scripts into a
config-driven Windows PowerShell module. The loop, abort path, and dated
scar tissue are preserved under `origin/` (SHA-256 pinned) and carried
forward in `src/`. This is not a greenfield rewrite.

### Added

- PowerShell module `Watchdog` 1.0.0 with discoverable CLI: `watchdog status|start|stop|poll|install`
- Required config file: no default `Root`, no default kill list, no silent 5090 envelope
- `-AllowKill` consent on start
- External poller (`Invoke-WatchdogPoll` / scheduled task) that writes `_watchdog_DEAD` from the outside when the heartbeat is stale — detects, never restarts
- Child `Start-Transcript` to `_watchdog_console.log` and unhandled exceptions to `_watchdog_crash.log`
- Pester unit tests for parse, hysteresis, heartbeat age, CSV append, config fail-closed, poller, CLI (`./verify.ps1`)
- Windows CI (`windows-latest`, paths-gated)

### Fixed

- W-01 — CSV is no longer truncated on start; prior rows survive with a `restart` marker
- W-02 — CSV timestamps include a UTC date (`yyyy-MM-ddTHH:mm:ss.fffZ`), not `HH:mm:ss`
- W-03 — a hard death leaves console/crash logs plus a poller-written DEAD sentinel
- W-04 — heartbeat, kill log, and CSV share one UTC clock
- W-05 — rig paths are config, not source
- W-06 — `Parse-GpuSample` (and the 2026-06-12 malformed nvidia-smi fixture) is unit-tested without a GPU

### Changed

- WSL `pkill` is opt-in (`WslKillPattern` empty by default)
- Hardware envelope (`VramKillMiB`, `RamKillPct`, `TempKillC`) is required in config; 31200 remains the documented 32 GB / RTX 5090 example, not a hidden default
