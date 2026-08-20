# Scorecard

**Repo:** mcp-tool-shop-org/watchdog
**Date:** 2026-08-20
**Type tags:** `[all]` `[cli]` `[complex]` (Windows PowerShell module)

## Pre-Remediation Assessment

Four loose scripts in `E:/AI/training/`. No module, no config, no tests, CSV truncated on start, no poller.

| Category | Score | Notes |
|----------|-------|-------|
| A. Security | 4/10 | Kill path existed; no -AllowKill; paths hardcoded |
| B. Error Handling | 5/10 | Exit codes on status/start; no structured shape |
| C. Operator Docs | 3/10 | Comments in scripts only |
| D. Shipping Hygiene | 1/10 | No verify, no CI |
| E. Identity (soft) | 0/10 | Empty GitHub repo |
| **Overall** | **13/50** | |

## Key Gaps

1. Hardcoded Robot paths (blocks public).
2. Nothing polls; death mid-session is invisible.
3. CSV truncate + hidden Start-Process destroyed the 2026-08-20 forensic trail.
4. No unit tests; integration test needs the rig.
5. Discoverability: the right status script existed and was not reached for.

## Post-Remediation

| Category | Before | After |
|----------|--------|-------|
| A. Security | 4/10 | 9/10 |
| B. Error Handling | 5/10 | 9/10 |
| C. Operator Docs | 3/10 | 9/10 |
| D. Shipping Hygiene | 1/10 | 8/10 |
| E. Identity (soft) | 0/10 | 9/10 |
| **Overall** | 13/50 | 44/50 |
