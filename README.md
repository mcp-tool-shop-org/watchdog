# watchdog

VRAM watchdog for the Robot rig (RTX 5090). It samples GPU temp / power /
VRAM and system RAM every 2 seconds, and after 3 consecutive breaches it
kills the guarded interpreters — sd-scripts, trellis2-env, ComfyUI
embedded Python, ai-toolkit — plus a WSL `pkill -f` pattern.

**This repo is an extraction, not a greenfield build.** The live process
still runs from `E:/AI/training/`. Nothing in this tree drives the GPU
until the Director approves a cutover.

Status on 2026-08-20: Repo-First gate. Origin scripts frozen under
`origin/`. Product layout, publish surface, and CI wait on five Director
decisions in [`docs/open-decisions.md`](docs/open-decisions.md).

## Live check (the only correct one)

```powershell
pwsh -NoProfile -File E:\AI\training\_watchdog_status.ps1
```

Exit `0` running · `1` no heartbeat · `2` stale (died hard). Do not
hand-roll a heartbeat-age check. The 2026-08-20 incident was two
operators, hours apart, each deriving a worse one while this script sat
on disk.

## What is in this repo today

| Path | What it is |
|---|---|
| `origin/` | Byte-identical freeze of the four live scripts, SHA-256 pinned |
| `docs/incidents.md` | Dated scar tissue those scripts still carry |
| `docs/open-decisions.md` | Five calls the Director owns |
| `LICENSE` | MIT, from the GitHub repo create |

Runtime artifacts (`_watchdog_HEARTBEAT`, `_watchdog_log.csv`,
`_watchdog_KILL.log`, the STOP/TRIPPED/DEAD/NO_TARGET sentinels) stay
next to the live process. They are not product source.

`saltroad_watchdog.ps1` is unrelated (RunPod poller). Not copied.

## Proposed layout (not built — waits on §5)

```
watchdog/
  origin/                 frozen 2026-08-20 scripts (this commit)
  src/                    extraction of origin/, then the W-0x fixes
    Watchdog.ps1          sampling loop — copy first, then patch
    Start.ps1
    Status.ps1
    Test-Abort.ps1        hardware dogfood, not CI
  config/
    robot.psd1            rig paths, kill list, 31200 ceiling
  tests/
    ParseGpuSample.Tests.ps1
    Hysteresis.Tests.ps1
    HeartbeatAge.Tests.ps1
    Sentinel.Tests.ps1
    fixtures/nvidia-smi-malformed.txt   the 2026-06-12 crash
  docs/
    incidents.md
    compensators.md       ABORT safety argument — required, no skip
    open-decisions.md
  .github/workflows/
    ci.yml                windows-latest, Pester, no GPU; paths-gated
```

`src/` is not created until the Director answers name, distribution
shape, and Windows-only vs Linux. Copying `origin/` into `src/` is the
first product commit after that — not a rewrite.

## Known defects (measured, not yet fixed)

| ID | Defect |
|---|---|
| W-01 | CSV truncated on every start (`Set-Content $csv`) |
| W-02 | CSV rows carry no date (`HH:mm:ss` only) |
| W-03 | Hard death leaves no diagnostic (hidden `Start-Process` discards stderr) |
| W-04 | Three timestamp formats, none UTC |
| W-05 | Rig paths hardcoded |
| W-06 | No unit tests; the integration test cannot run in CI |

## Thresholds (load-bearing)

VRAM **31200 MiB of 32607**. Do not raise this to stop ComfyUI trips —
cap ComfyUI (`--reserve-vram`) instead. RAM 90%, temp 87 C, 3 consecutive
breaches, 2 s interval.

## License

MIT. See [LICENSE](LICENSE).
