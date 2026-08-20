# Ship Gate

> No repo is "done" until every applicable line is checked.

**Tags:** `[all]` `[cli]` `[complex]` — Windows PowerShell module, not npm/pypi/mcp

---

## A. Security Baseline

- [x] `[all]` SECURITY.md exists (report email, supported versions, response timeline) (2026-08-20)
- [x] `[all]` README includes threat model paragraph (data touched, data NOT touched, permissions required) (2026-08-20)
- [x] `[all]` No secrets, tokens, or credentials in source or diagnostics output (2026-08-20)
- [x] `[all]` No telemetry by default — state it explicitly even if obvious (2026-08-20)

### Default safety posture

- [x] `[cli|mcp|desktop]` Dangerous actions (kill, delete, restart) require explicit `--allow-*` flag — `Start-Watchdog -AllowKill`; poller never kills or restarts (2026-08-20)
- [x] `[cli|mcp|desktop]` File operations constrained to known directories — writes only under config `Root`; relative Root/Targets rejected (2026-08-20)
- [ ] `[mcp]` SKIP: not an MCP server
- [ ] `[mcp]` SKIP: not an MCP server

## B. Error Handling

- [x] `[all]` Errors follow the Structured Error Shape: `code`, `message`, `hint`, `cause?`, `retryable?` (2026-08-20)
- [x] `[cli]` Exit codes: status/poll keep the liveness contract 0 running · 1 no heartbeat · 2 stale; start uses 1 usage · 3 VRAM already over · 4 stop timeout · 5 launch failed (origin contract, documented in `--help`) (2026-08-20)
- [x] `[cli]` No raw stack traces without `--debug` (`$DebugPreference` / `-IncludeStack`) (2026-08-20)
- [ ] `[mcp]` SKIP: not an MCP server
- [ ] `[mcp]` SKIP: not an MCP server
- [ ] `[desktop]` SKIP: not a desktop app
- [ ] `[vscode]` SKIP: not a VS Code extension

## C. Operator Docs

- [x] `[all]` README is current: what it does, install, usage, supported platforms + runtime versions (2026-08-20)
- [x] `[all]` CHANGELOG.md (Keep a Changelog format) (2026-08-20)
- [x] `[all]` LICENSE file present and repo states support status (2026-08-20)
- [x] `[cli]` `--help` output accurate for all commands and flags (`watchdog help`) (2026-08-20)
- [x] `[cli|mcp|desktop]` Logging levels: default sample/status output; `-Verbose` on cmdlets; `$DebugPreference='Continue'` for stacks; no secrets to redact (2026-08-20)
- [ ] `[mcp]` SKIP: not an MCP server
- [x] `[complex]` HANDBOOK.md: daily ops, warn/critical response, recovery procedures (2026-08-20)

## D. Shipping Hygiene

- [x] `[all]` `verify` script exists (test + build + smoke in one command) — `./verify.ps1` (2026-08-20)
- [x] `[all]` Version in manifest matches git tag — `Watchdog.psd1` ModuleVersion 1.0.0, tag `v1.0.0` (2026-08-20)
- [ ] `[all]` SKIP: no shipped package dependencies to scan; Pester is installed in CI from PSGallery and is not a runtime dep. Ecosystem-appropriate scan is "none".
- [ ] `[all]` SKIP: automated dependency updates — org policy is no Dependabot unless requested; this module has no lockfile of runtime deps.
- [ ] `[npm]` SKIP: not an npm package
- [ ] `[npm]` SKIP: not an npm package
- [ ] `[npm]` SKIP: not an npm package
- [ ] `[pypi]` SKIP: not a Python project
- [ ] `[vsix]` SKIP: not a VS Code extension
- [ ] `[desktop]` SKIP: not a desktop app

## E. Identity (soft gate — does not block ship)

- [x] `[all]` Logo in README header (2026-08-20)
- [x] `[all]` Translations (polyglot-mcp, 8 languages) (2026-08-20)
- [x] `[org]` Landing page (@mcptoolshop/site-theme) (2026-08-20)
- [x] `[all]` GitHub repo metadata: description, homepage, topics (2026-08-20)

---

## Gate Rules

**Hard gate (A–D):** Must pass before any version is tagged or published.
If a section doesn't apply, mark `SKIP:` with justification — don't leave it unchecked.

**Soft gate (E):** Should be done. Product ships without it, but isn't "whole."
