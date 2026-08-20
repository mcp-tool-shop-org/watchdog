# Scar tissue — dated incidents still in the origin scripts

These are not folklore. Each one produced a fix that is still in
`origin/`. A rewrite that drops the comment drops the lesson.

## 2026-06-12 — nvidia-smi parse crash

`origin/_watchdog.ps1` `Parse-GpuSample`. nvidia-smi emitted warning/info
lines, multiple lines, or stringified as `Object[]` during a driver
hiccup. `.Split()` on that killed the loop at 03:29:53. Filter to lines
shaped like `temp,power,vram`, take the first; anything else throws into
the per-sample catch instead of dying. Sample errors log to the KILL log
and as `state=sample_error` in the CSV; they never kill the loop.

This is the clean unit-test seam (W-06): fixture strings, including the
malformed multi-line output that caused it.

## 2026-06-24 — hard kill, five weeks unprotected

`origin/_watchdog_status.ps1` header. The watchdog tripped (killed
ComfyUI on a VRAM breach), kept running, then was hard-killed ~10h
later. A hard kill cannot write `_watchdog_DEAD`, and nothing else
surfaced the absence — the rig ran with no VRAM protection for 5+ weeks.
A dead watchdog and a healthy one look identical unless you ask.

The only reliable signal is heartbeat age. Do not process-match on
`_watchdog` — the checking command's own command line contains that
string and self-matches.

## 2026-08-01 — ai-toolkit unguarded

`origin/_watchdog.ps1` kill list. ai-toolkit runs were entirely
unguarded: the watchdog would log a breach and kill nothing, so every
LoRA train since ai-toolkit landed could spill/overheat past the ceiling
with no hard abort. Added
`E:\AI\ai-toolkit\venv\Scripts\python.exe` (py 3.11.15 / torch 2.9.1+cu128).

## 2026-08-04 — 153 ABORTs, nothing killed, no holder named

`origin/_watchdog.ps1` `_watchdog_NO_TARGET` + `Get-VramHolders`.
09:12–09:17 logged 153 ABORTs with VRAM pinned at 31.9 GB, zero kills,
and never named the holder. A breach that kills nothing is a protection
*gap*, not the mechanism working.

Per-process VRAM: nvidia-smi's `used_gpu_memory` reads `[N/A]` under
WDDM on this rig, so holders come from the `\GPU Process Memory`
counter set (~1.3s per call; breach path only, never the normal loop).
Best-effort: any failure degrades to a note and must never kill the loop.

## 2026-08-20 — died after one sample; operators hand-rolled a worse check

Started 12:56:37, wrote one CSV sample at 12:56:38, died hard. Discovered
at 13:29 — 33 minutes of unprotected GPU — because a row count looked
wrong for a 2-second interval. Two Claude sessions doing GPU work both
believed it was alive. One read the heartbeat, computed a 9-minute age,
and called it fresh against a `StaleSec` of 15.

The tooling was already correct: `_watchdog_status.ps1` would have
returned exit 2; the SessionStart hook fired and warned. The failure was
not a missing capability. It is the product problem this repo exists to
solve:

1. Nothing polls. Liveness is pull-only and fires once at session start.
2. Discoverability. If the only correct check is a script path someone
   has to remember, it will keep being re-derived badly.
3. No forensics. Hidden `Start-Process` discards stderr; the next start
   truncates the CSV (W-01), so the evidence of *why* it died was
   destroyed by the restart that fixed it.

Restarted 2026-08-20 13:32 EDT and is beating. Do not touch the live
files as a side effect of this repo.
