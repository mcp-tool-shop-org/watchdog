# Workflow standards — watchdog CI

Scored against the six studio standards. Compensators: **no skip** (see
[compensators.md](compensators.md)).

| Standard | Score | Evidence | Remediation |
|---|---|---|---|
| PIN_PER_STEP | 2 | `npx @mcptoolshop/shipcheck@1.0.7`; CI pins Pester ≥5.5.0 from PSGallery; `actions/checkout@v4`. Module version is `1.0.0` in `Watchdog.psd1`. | P2 — pin checkout to a SHA if the org moves that way; Pester upper bound already avoided by MinimumVersion. |
| ANDON_AUTHORITY | 3 | `verify.ps1` runs Pester with `Run.Exit = $true`. CI fails the job on a red suite. `-AllowKill` is a real refuse (tested). `Parse-GpuSample` throw on the 2026-06-12 fixture is a real refuse (tested). Start refuses VRAM-already-over (exit 3). A gate that cannot trip is not used. | None. |
| NAMED_COMPENSATORS | 3 | [docs/compensators.md](compensators.md) covers ABORT kill, WSL pkill, NO_TARGET gap, `-Force` start, double-loop, poller DEAD, install, and live-script cutover. No skip. | Standing rule: any new kill/restart path adds a row in the same commit. |
| DECOMPOSE_BY_SECRETS | 2 | Private parse / hysteresis / heartbeat / csv / config change on different cadences from Public start/status/poll. `origin/` is a freeze that does not ship as the default. CI is one `ci.yml` (lint+test combined). | P3 — Linux sampler (later version) should land as a sibling of `Get-VramHolders`, not a rewrite of the loop. |
| UNCERTAINTY_GATED_HUMANS | 2 | `-AllowKill` and `-Force` are contrastive: default is refuse. Poller detects and will not restart (auto-restart is the uncertain, dangerous default). Cutover is Director-gated in HANDBOOK.md. | P2 — SessionStart `-Hook` is quiet when healthy; still pull-once per session. The scheduled poller is the mid-session gate. |
| EXTERNAL_VERIFIER | 2 | Pester is a different process from the loop. Fixtures include the malformed nvidia-smi that killed production. CI is GitHub-hosted Windows, not the Robot GPU. GPU abort remains dogfood and is not greened in CI. | P1 — do not add a fake GPU job that cannot trip. |

**Total: 14 / 18**
