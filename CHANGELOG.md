# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.3] - 2026-11-26

A live watchdog is no longer reported dead after one bad heartbeat read, and the README, landing page and handbook are rewritten as a proper front door.

### Fixed

- `Get-WatchdogHeartbeatState` (used by `status`, `poll`, `start` and `stop`) no longer declares the watchdog stale on a single failed read. It reads with full sharing; an empty read (`Set-Content` truncates before it writes) or an IO-locked read is retried (5 x 50 ms by default), and if it stays that way the age comes from the heartbeat's `LastWriteTime` (`Source = 'mtime'`). A partial or malformed read is retried too, and content that still does not parse is STALE (`Source = 'unparseable'`), never aged by `LastWriteTime`. A file deleted mid-read by a clean stop is `NOT_RUNNING`.
- A heartbeat timestamp must carry an explicit offset (`Z` or `+hh:mm`); one cut off before its offset used to parse as local time and could read as hours fresh on a dead loop. An age more than 5 s in the future (a clock stepped back) is STALE, and only an age inside the window counts as RUNNING (a `NaN` age is STALE).
- The heartbeat path is resolved through the PowerShell provider, so a caller sitting on a non-FileSystem drive (`Env:`, `HKLM:`) no longer errors.

### Changed

- README, landing page and handbook welcome page rewritten around what watchdog does for the user, with a quick start, how it works, commands, the required config and safety; the stated requirement is PowerShell 7, matching the manifest (`7.0`). The README is translated into 7 languages, with the product name protected from translation.
- Public docs no longer carry internal deployment notes (a live-instance section, a local path, internal role labels and machine nicknames).
- The logo has a transparent background.

## [1.1.2] - 2026-11-24

### Fixed

- `Invoke-WatchdogPoll` now creates `Root` before reading the heartbeat, reports the underlying cause via `GetBaseException()`, returns a structured error naming `Root` on failure, and uses `-LiteralPath` on the poll's own files (`Console`, `Crash`, `Dead`, `Kill`, `PollStamp`) so a standalone poll works on a new or bracket-containing `Root`; heartbeat state reads and other cmdlets still assume `Root` has no wildcard characters.
- `Register-WatchdogPoll` now verifies that `Root` is writable with a uniquely named probe file (cleaned up in `finally` even if probing or probe deletion fails) before creating or registering the scheduled task, reporting when `Root` is not writable or the probe file could not be removed.
- `Unregister-WatchdogPoll` now calls `Get-ScheduledTask` with `-ErrorAction Stop`, treats only `ObjectNotFound` / `CmdletizationQuery_NotFound*` as absent, and throws with an elevation hint when querying or unregistering is refused; every scheduled-task call passes `-TaskPath '\'`.
- `Invoke-ProcessWithTimeout` now waits at most 5 s per stream after exit (configurable via `-StreamDrainMs`), avoids `.Result` on incomplete stream tasks, adds `StreamsDrained` to `-PassThru`, and reports an undrained stderr stream instead of blocking on failure; `Test-WslDistroRunning` also treats `StreamsDrained = $false` as not running.
- The loop's emergency WSL abort path now runs `Test-WslDistroRunning` (`4 s` timeout, `1 s` stream drains) and `Invoke-ProcessWithTimeout` (`5 s` timeout, `1 s` stream drains, `-ArgumentList` passing `wsl.exe -d <distro> --exec pkill -9 -f -- <pattern>`) inside `try`/`catch` while refreshing the heartbeat before and after each WSL call, so no distro shell parses `WslKillPattern`, `--` prevents leading-dash patterns from being parsed as `pkill` options, and a slow WSL call cannot push heartbeat age past `StaleSec`.
- `watchdog-loop.ps1` and `Invoke-WatchdogLoop` now enforce kill consent directly: both accept `-AllowKill` and otherwise require boolean `$true` on config `AllowKill`, running in detect-only mode when consent is absent (skipping Windows and WSL kills and logging `kill skipped: no consent` while still starting and continuing to loop on `AllowKill = $false`); `Start-Watchdog` forwards `-AllowKill` to `watchdog-loop.ps1`.
- The loop's heartbeat-skip log line now records the caught exception's first-line message instead of assuming a locked file.
- `Invoke-WslCacheRelease` now passes `-ErrorAction Stop` when writing `.hb` and `.last` state files so write failures are logged as errors while preserving its non-throwing contract.
- Config validation now rejects `NaN`, `±Infinity`, negative or out-of-range numbers, booleans/arrays/hex strings on numeric fields, values rounding to `0` (`<= 0.5`) on `Min = 1` integer fields, and non-boolean `AllowKill` or `WslCacheRelease` values (such as quoted `'false'`, `'true'`, `0`, `1`, or `$null`) without echoing input values in refusal messages.

### Changed

- `PollIntervalSec` now defaults to `60` (matching the Windows Task Scheduler minimum); the handbook documents that when a WSL cache release hits `WslCacheTimeoutSec` after the current liveness check and poll stamp complete, Task Scheduler `-MultipleInstances IgnoreNew` skips the next poll tick, so the cost is one delayed check.
- `ci.yml` now triggers on `codecov.yml` changes and skips the OIDC Codecov upload job on fork pull requests.
- `pages.yml` removes unused `contents: read` permission from the `deploy` job.
- Coverage docs clarify that `verify.ps1` measures `src/Watchdog/Private` and `src/Watchdog/Public` only and fails below 90%, Codecov checks patches at 90% and allows a 1% whole-module threshold, and unit tests spawn short-lived `pwsh` child processes in CLI and helper tests.

### Upgrade Notes

If you are upgrading an existing configuration from `1.1.1`, `Resolve-WatchdogConfig` now refuses (`CONFIG_INVALID`) these previously tolerated or silently coerced values:

- **Strict booleans (`AllowKill`, `WslCacheRelease`):** only unquoted `$true` or `$false` is accepted when present. Quoted `'false'`, `'true'`, integers `0` / `1`, `$null`, or any other type is refused (quoted `'false'` on `AllowKill` previously evaluated truthy).
- **Minimum `1` on core and timer integer keys:** `VramKillMiB`, `RamKillPct`, `TempKillC`, `IntervalSec`, `BreachSamples`, `StaleSec`, `PollIntervalSec`, `WslCacheCooldownSec`, and `WslCacheTimeoutSec` must be finite numbers that round to at least `1` and at most `[int]::MaxValue`. Values `<= 0.5` (including `0` and fractions that round to `0` on `[int]` cast), negatives, numbers above `[int]::MaxValue`, `NaN`, `±Infinity`, hex text (`0x...`), booleans, arrays, and `$null` are refused (`WslCacheSettleSec` still allows `0`, refusing `< 0` and non-numeric/out-of-range inputs).
- **WSL cache thresholds (`WslCacheHighGB`, `WslCacheMinGB`, `WslCacheWinHighPct`, `WslCacheMinCacheGB`, `WslCacheAlertPct`):** must be finite positive numbers (`> 0`); `<= 0`, `NaN`, `±Infinity`, hex text, booleans, arrays, and `$null` are refused, and `WslCacheWinHighPct` / `WslCacheAlertPct` must be `<= 100`.

## [1.1.1] - 2026-11-24

### Fixed

- The poll task now starts. `Register-WatchdogPoll` registered a bare `pwsh`, which Task Scheduler looks up on the machine PATH only; with PowerShell installed from the Microsoft Store (an execution alias in the user's WindowsApps folder), every trigger ended with 0x80070002 (file not found) and the poller never ran. It now registers the absolute `pwsh` path, started through `conhost --headless` so no window flashes on each poll. It refuses to report success unless the task holds the new action and its first run proves that the poll ran: every poll now writes `_watchdog_poll_last.json` (when the poll began, when it wrote the stamp, its state and exit code) under `Root` right after its liveness check and before the cache release, and only a stamp that carries this registration's token (the task's action passes it to the poll), from a poll that began after the check, counts: a manual poll or another registration's run cannot stand in, and conhost exits 0 even when `pwsh` never starts. The check clears the previous stamp first and compares Unix milliseconds (`utc_ms`), so the reading does not depend on the local time zone. It throws with an elevation hint when Task Scheduler refuses the registration, and it creates `Root` before registering anything and refuses a `Root` that is not a folder. Registering before the loop runs makes that first poll report the loop as not running, which writes `_watchdog_DEAD`; `Start-Watchdog` clears it.
- The Pages workflow deploys from `main` only. The `github-pages` environment lets only `main` deploy, so v1.1.0's release-event deploy was refused; site changes reach `main` in the release PR.

## [1.1.0] - 2026-11-24

### Changed

- The landing page and handbook are back on GitHub Pages (Pages could not be enabled while the repository was private). The deploy workflow pins every action to a commit SHA, audits the site's dependencies, and checks that the landing page and the handbook both return 200 after each deploy. The handbook documents the WSL cache release, its log, and the coverage bar.

### Added

- **WSL file-cache release (opt-in, `WslCacheRelease`).** The poller drops the Linux page cache when the WSL VM crowds Windows memory, reading memory from the Windows side so it never wakes a stopped VM, and acting only when `WslDistro` is already running, so a distro stopped while another one (a container engine's) keeps the VM up is never started. It has thresholds and a cooldown, puts a timeout on every `wsl.exe` call, and runs after the poll's liveness check, so it can never delay the report of a dead loop. It never kills a process, and logs to `_watchdog_wslcache.log` (hourly heartbeat, each drop, each run of skips, and an alert if Windows stays high).
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
