---
feature: config-toggles
---

# Test cases: Config toggles

Automation `check.sh` means a behavioral fixture in `check.sh` (sync into a fixture HOME). It is outside the partial's enum on purpose: this repo has no jest/junit/quick suite.

| ID | Title | Steps | Expected | Source | Status | Automation |
|----|-------|-------|----------|--------|--------|------------|
| TC-001 | No config means no change on upgrade | 1. Fixture HOME, no config <br> 2. Sync with previous release, snapshot <br> 3. Sync with this release | Installed files byte-identical | spec:15 · spec:45 | approved | check.sh |
| TC-002 | Config survives post-merge sync | 1. Write `dashboard=on` to config <br> 2. Run sync under `env -i` | Dashboard installed | spec:16 | approved | check.sh |
| TC-003 | Off removes, second sync is a no-op | 1. Sync with all toggles on <br> 2. Turn each toggle off, sync twice | First run removes its files; second run reports `(up to date)` everywhere | spec:17 | approved | check.sh |
| TC-004 | Verify gate off | 1. Set `gates.verify=off` <br> 2. Sync | `gate-verify-on-stop.js` absent from settings.json; no verify-gate prose in any of the 4 tools' output | spec:18 · spec:46 | approved | check.sh |
| TC-005 | Director gate off in both tools | 1. Set `gates.director=off` <br> 2. Sync | Delegate gate absent from Claude and Codex; rule 12a absent from all 4 tools | spec:47 | approved | check.sh |
| TC-006 | Director unset keeps per-tool default | 1. Leave `gates.director` unset <br> 2. Sync | Claude delegate gate on; Codex off unless `CRAFTKIT_DELEGATE=on` | spec:Key decisions (director default) | approved | check.sh |
| TC-007 | Routing off runs a reduced hook | 1. Set `gates.routing=off` <br> 2. Sync <br> 3. Feed a prompt to `craftkit-routing.js` | Output carries the tier line and no skill-first text; skill-first and announce hooks unregistered | spec:48 | approved | check.sh |
| TC-008 | Playwright on then off | 1. Set `playwright=on`, sync <br> 2. Set `playwright=off`, sync twice | Skill installed, then removed; second run `(up to date)` | spec:49 | approved | check.sh |
| TC-009 | Unowned Playwright copy left alone | 1. Install `@playwright/cli` before craftkit <br> 2. Toggle on, then off | Global package stays; only the craftkit-owned skill is removed | spec:Risks (unowned copy) | approved | check.sh |
| TC-010 | Playwright install failure is non-fatal | 1. Set `playwright=on` with npm absent or Node < 20 <br> 2. Sync | Warning printed; sync still ends with `Sync complete.` | spec:Risks (network, Node 20+) | approved | check.sh |
| TC-011 | Humanizer off | 1. Set `humanizer=off` <br> 2. Sync <br> 3. Run `/pr-message` | Both humanizer paths removed; `/pr-message` reports `Humanized: SKIPPED` (step 3 manual) | spec:50 | approved | check.sh |
| TC-012 | Env var beats config | 1. Config `dashboard=off` <br> 2. Run `CRAFTKIT_DASHBOARD=1 bash sync.sh` | Dashboard installed | spec:51 | approved | check.sh |
| TC-013 | Legacy dashboard file migrates | 1. `~/.craftkit-state/dashboard` exists, no config <br> 2. Sync | Config contains `dashboard=on`; behavior unchanged | spec:52 | approved | check.sh |
| TC-014 | No prompt without a TTY | 1. Run `bash install.sh </dev/null` <br> 2. Run `bash sync.sh </dev/null` | No prompt, no hang; defaults apply | spec:19 · spec:53 | approved | check.sh |
| TC-015 | `--configure` updates and syncs | 1. Run `bash sync.sh --configure` on a TTY <br> 2. Flip one box | Config updated; the same run applies it | spec:54 | approved | manual |
| TC-016 | Unknown key or value | 1. Config has `gates.verify=maybe` and `foo=on` <br> 2. Sync | One warning per bad line; prior setting kept | spec:55 | approved | check.sh |
| TC-017 | Toggle back on restores | 1. Turn a gate group off, sync <br> 2. Turn it on, sync | Hook and prose restored; output matches TC-001 | inferred | approved | check.sh |
| TC-018 | User-narrowed matcher kept | 1. Hand-narrow the verify hook matcher <br> 2. Toggle the group off, then on | Note printed; user matcher not overwritten | inferred | approved | check.sh |
| TC-019 | check.sh guards fail when broken | 1. Remove the strip or teardown code <br> 2. Run `check.sh` | `check.sh` exits non-zero | spec:20 · spec:56 | approved | manual |
