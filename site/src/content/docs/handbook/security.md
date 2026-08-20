---
title: Security
description: Threat model, consent, write confinement.
sidebar:
  order: 6
---

- **Touched:** files under `Root`; process list; GPU counters; optional local WSL `pkill`.
- **Not touched:** source trees, checkpoints, credentials, the network.
- **No telemetry** leaves the machine.
- **No secrets** in config or logs (paths and integers).
- **Writes** stay under `Root`. Relative paths are rejected.
- **Consent:** `-AllowKill`. The poller never kills and never auto-restarts.

The irreversible action is ABORT. A false positive destroys in-flight
GPU work. A false negative (dead watchdog, empty kill list, a
hand-rolled heartbeat check) leaves the host unprotected.

Report issues to 64996768+mcp-tool-shop@users.noreply.github.com.
Acknowledge 48h / assess 7d / fix 30d. See [SECURITY.md](https://github.com/mcp-tool-shop-org/watchdog/blob/main/SECURITY.md).
