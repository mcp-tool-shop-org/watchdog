# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes       |

## Reporting a Vulnerability

Email: **64996768+mcp-tool-shop@users.noreply.github.com**

Include:

- Description of the vulnerability
- Steps to reproduce
- Version affected
- Potential impact (especially: unexpected process kill, write outside `Root`, config that enables kill without consent)

### Response timeline

| Action | Target |
|--------|--------|
| Acknowledge report | 48 hours |
| Assess severity | 7 days |
| Release fix | 30 days |

## Scope

Watchdog is a **local Windows** PowerShell module. It samples NVIDIA GPU temp/power/VRAM and system RAM, and on a sustained breach it **kills configured interpreter processes**.

- **Data touched:** files under the configured `Root` (heartbeat, CSV telemetry, kill log, console/crash logs, STOP/TRIPPED/DEAD/NO_TARGET sentinels); process list and GPU counters; optional WSL `pkill` of a configured pattern.
- **Data NOT touched:** source trees, model weights, training checkpoints, credentials, cloud APIs.
- **No network egress.** nvidia-smi and WDDM counters are local. WSL interop is local.
- **No secrets handling.** Config is a PowerShell data file of paths and integers.
- **No telemetry** is collected or sent anywhere off-box.
- **Kill consent:** `Start-Watchdog` requires `-AllowKill` (or `AllowKill = $true` in config). The poller detects death; it never restarts and never kills.
- **Writes** are constrained to `Root`. Relative `Root` / `Targets` paths are rejected.

## Threat model (summary)

The irreversible action is an ABORT. A false positive destroys in-flight GPU work with unsaved state. A false negative (dead watchdog, empty kill list, heartbeat check someone hand-rolled) leaves the host unprotected. See [docs/compensators.md](docs/compensators.md).
