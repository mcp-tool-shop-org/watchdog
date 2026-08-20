# Origin snapshot — 2026-08-20

Byte-identical copies of the four live VRAM-watchdog scripts from
`E:/AI/training/`. Copied, not rewritten. SHA-256 matches the source
files at copy time. The live copies were **not** moved, renamed, or
edited.

`saltroad_watchdog.ps1` is **not** in this snapshot. It shares a filename
prefix and nothing else (RunPod cost/artifact poller). Out of scope
pending the Director's call in §5.

The live watchdog continues to run from `E:/AI/training/`. This directory
is the forensic freeze so a later extraction cannot lose dated scar tissue.

| File | Lines | Bytes | SHA-256 |
|---|---:|---:|---|
| `_watchdog.ps1` | 154 | 9565 | `07EE55817EFBFE4AFC0ED14754CC2361AE95D2753548DA7F1AEF0FEEC0DAC214` |
| `_watchdog_start.ps1` | 101 | 5041 | `1C3FE987C801B8220CBEB9A56D79687F380547CB9DF642F17ABCDB0CAE9670F0` |
| `_watchdog_status.ps1` | 100 | 4852 | `C5DEA715266A0963FD49CD713AB0A4484CCAF1EE618E27F4E878A4FB96901A01` |
| `_watchdog_test.ps1` | 39 | 2444 | `97E096C31FA61A4439304AB575C6AC51A1E749394FE2F1BC9D1D8E14A4D0902A` |

Source last-write times (not touched by the copy):

- `_watchdog.ps1` — 2026-08-04 18:36:14
- `_watchdog_start.ps1` — 2026-08-04 18:36:25
- `_watchdog_status.ps1` — 2026-08-01 20:20:59
- `_watchdog_test.ps1` — 2026-06-07 06:12:05

`_watchdog_test.ps1` measures 39 lines on disk (kickoff said 38; likely a trailing-newline count). The hash is the authority.
