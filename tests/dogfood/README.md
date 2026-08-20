# GPU dogfood — not CI

`origin/_watchdog_test.ps1` is the live abort test: it spawns a real venv
python, runs a real always-trip watchdog, and kills real processes. It
needs this rig.

CI has no GPU. The valuable tests (parse, hysteresis, heartbeat age,
CSV append, config fail-closed, poller DEAD write, -AllowKill) run in
`./verify.ps1` without hardware.

Do not run the origin abort test from this repo against `E:/AI/training`
as a side effect of development. Cutover is a Director-approved step.
The live watchdog protecting the rig is still the scripts in
`E:/AI/training/`.
