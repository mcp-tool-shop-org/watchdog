# watchdog — extraction in progress

This repo is the version-controlled product for the Robot-rig VRAM
watchdog. The live process is **not** here.

## Live process — do not touch

The watchdog protecting this rig runs from `E:/AI/training/`:

- `_watchdog.ps1` — sampling loop
- `_watchdog_start.ps1` — clean restart
- `_watchdog_status.ps1` — liveness
- `_watchdog_test.ps1` — local abort test

**Do not move, rename, or edit those files as part of work in this
repo.** Copy in, develop here. Cutover is a separate Director-approved
step, not a side effect of a commit.

Check liveness before and after anything that could affect the GPU:

```
pwsh -NoProfile -File E:\AI\training\_watchdog_status.ps1
```

Exit codes: `0` running · `1` no heartbeat · `2` stale (died hard).

## This is an extraction, not a greenfield build

`origin/` is a SHA-256-pinned freeze of the four scripts as of
2026-08-20. Dated scar tissue in those comments is load-bearing.
Rewriting from scratch and reintroducing a bug someone already paid for
is the failure mode.

See `docs/incidents.md`.

## Load-bearing thresholds

VRAM ceiling **31200 MiB of 32607**. Do not raise it to stop ComfyUI
trips — cap ComfyUI (`--reserve-vram`) instead. RAM 90%, temp 87 C, 3
consecutive breaches, 2 s interval.

A breach that kills nothing is a protection gap (`_watchdog_NO_TARGET`),
not the mechanism working.

## Open decisions

`docs/open-decisions.md`. Do not publish, rename, add `saltroad_watchdog`,
scaffold npm, or add a Linux product path until the Director answers.

## Compensators

This tool kills processes. An ABORT destroys in-flight training with
unsaved state. The compensators table is the product's safety argument,
not paperwork. No skip permitted on NAMED_COMPENSATORS.
