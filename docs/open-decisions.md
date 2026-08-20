# Decisions for the Director — do not decide in this repo

These five are load-bearing for layout, license surface, and CI. Product
work past the origin freeze waits on them.

## 1. Public or private?

Currently **private**. Org tools are normally public, but this one
hardcodes Robot-rig paths and encodes the 5090 hardware envelope
(32607 MiB, WDDM counters, WSL Ubuntu, four absolute interpreter paths).

Recommendation to weigh, not a decision: keep private until paths are
config (W-05) and the envelope is a profile, not the source. Then the
usual public default can apply.

## 2. Name and scope

The GitHub repo is `watchdog`, which is extremely generic for any
published artifact. Candidates: `vram-watchdog`, `rig-guardian`, keep
`watchdog` as an internal private name.

Ask before anything is published under the current name. Do not set the
GitHub description or npm name until this is settled.

## 3. Does `saltroad_watchdog.ps1` belong here?

Default assumption: **out of scope**. It polls RunPod cost and artifacts
over SSH. Shares a filename prefix and nothing else. Left where it is
(`E:/AI/training/saltroad_watchdog.ps1`). Confirm.

## 4. Distribution shape

This affects the whole repo layout.

- Plain scripts plus an installer
- A PowerShell module (`Watchdog.psm1` / `vram-watchdog`)
- The studio's usual npm wrapper (`@mcptoolshop/...`)

Recommendation to weigh: PowerShell module for the product (status /
start / sample are native pwsh), with an optional npm bin later if the
studio install story needs it. Do not scaffold `package.json` until this
is called.

## 5. Windows-only, or a Linux/WSL path too?

It depends on `nvidia-smi`, WDDM performance counters, and WSL interop.
A Linux host path would need a different holder source than `\GPU Process
Memory(*)\Dedicated Usage` and a different RAM source than
`Win32_OperatingSystem`.

Kickoff already justifies `windows-latest` in CI despite the org Linux
default. A Linux/WSL *product* path is a separate scope call.
