---
slug: config-toggles
status: shipped
created: 2026-10-12
---

# Config toggles: user-chosen extras and gate groups

## Spec
**Updated:** 2026-10-12T00:00:00Z · **By:** /spec

- **Objective:** Teammates get every optional tool and every enforcement gate whether they want it or not, and the only escape today is env vars that a `git pull` sync never sees. Give them one saved config that each sync honors, so customizing craftkit no longer means forking it.
- **Users & job:** Teammates installing `@raditia/craftkit` through npm or a git clone. The job: pick which extras get installed and which gates enforce, once, and have that choice hold across every later update.
- **Success:**
  1. With no config file present, a sync produces installed output identical to v1.58.0 except the T13 spawn-label text (fixture-HOME diff in `check.sh`).
  2. A choice written to the config survives a post-merge sync run with an empty environment.
  3. Turning a toggle off removes everything it installed on the next sync, and a second sync reports `(up to date)` everywhere.
  4. With a gate group off, its hooks are absent from `~/.claude/settings.json`; Codex gates are read at runtime from `~/.craftkit-state/gate-*`, and `~/.codex/hooks.json` is unchanged. None of the group's marked rule prose appears in any of the 4 tools' installed rule output.
  5. No code path prompts when stdin is not a TTY (postinstall, post-merge, CI). Asserted by running sync with `</dev/null`.
  6. `check.sh` runs a sync with each toggle off and asserts 3 and 4, and the check fails when the strip or teardown is removed.
- **In scope:**
  - Config file `~/.craftkit-state/config`, `key=value` lines, parsed bash 3.2 safe.
  - Keys: `humanizer`, `playwright` (default off), `dashboard` (default off), `gates.routing`, `gates.director`, `gates.verify`.
  - Precedence: env var > config file > built-in default. Existing `CRAFTKIT_DASHBOARD` and `CRAFTKIT_DELEGATE` stay as env aliases; the existing `~/.craftkit-state/dashboard` file is read as `dashboard=on` and migrated into the config.
  - Interactive checklist in `install.sh` when stdin is a TTY and no config exists; `bash sync.sh --configure` re-runs it and then syncs.
  - Playwright toggle: on installs `@playwright/cli` globally plus `playwright-cli install --skills=agents -g`; off removes the skill folder it installed (the global npm package is removed only if craftkit installed it).
  - Humanizer toggle: off removes `~/.agents/skills/humanizer` and the `~/.claude/skills/humanizer` symlink.
  - Marked sections in rules (e.g. `<!-- craftkit-gate: verify -->` ... `<!-- /craftkit-gate -->`) stripped by the shared renderer (`sync.sh:craftkit_render_injected` path) for every adapter when that group is off.
  - Subagent spawn labels: every spawn instruction requires a task-specific Agent `description`, so the agent list shows the work instead of `general-purpose` (user request 2026-10-12; independent of the toggles).
  - README configuration section, CHANGELOG, minor version bump; fix the stale caveman comment at `install.sh:24`.
- **Out of scope:** rtk toggle (rtk stays mandatory); read-size / read-cap gates (always-on token protection); per-hook toggles; team-wide presets; the fe-visual-verify skill and Figma loop (separate `/define`); caveman (a Claude plugin craftkit does not install).
- **Constraints:** bash 3.2 (no associative arrays); idempotent sync, second run is a no-op; no prompt on non-TTY paths; `ensure_tools` interactivity stays behind `AGENTIC_SETUP=1`; Codex hook changes need the user to re-trust with `/hooks`; `bash check.sh` exit 0; no em-dashes in prose.
- **Key decisions:**
  - Config lives in `~/.craftkit-state/` beside the existing state files (`sync.sh:10`), not `~/.craftkit/`, which is rebuilt staging.
  - Unset key keeps today's per-tool default. `gates.director` unset is Claude on, Codex off (`hooks/craftkit-codex.js:170`); an explicit value applies to both tools.
  - Gate off removes the hook and its marked prose, not the hook alone, so no tool reads text about a gate that no longer exists.
  - `gates.routing` off keeps `craftkit-routing.js` registered in a reduced mode that injects only the model-tier and installed-skills lines, because rule `using-agent-skills` Model routing depends on the tier line. Skill-first and announce gates are unregistered.
  - Humanizer off needs no skill changes: `/pr-message` and `/docs` already check presence and skip (`commands/pr-message.md:106`, `skills/docs/SKILL.md:47`).
  - Toggles are coarse (3 gate groups) so `check.sh` can cover every one-off state.
- **Risks & open questions:**
  - Marking the gate prose is manual: a future rule edit that mentions a gate outside its markers leaks stale text. Mitigation: `check.sh` greps installed output with each group off for the gate's hook filename.
  - Uninstalling the global `@playwright/cli` could remove a copy the user installed themselves. Record ownership in state at install time; never remove an unowned copy.
  - Playwright install needs network outside the Claude Code sandbox and Node 20+. On failure: warn and complete the sync.
  - Some rule prose (e.g. rule 12a director mode) may also be referenced from commands or hooks; the strip must cover every installed surface, not only the managed block.
- **Acceptance:**
  - [ ] Given no config, when sync runs, then installed output is identical to v1.58.0 except the T13 spawn-label text.
  - [ ] Given `gates.verify=off`, when sync runs, then `gate-verify-on-stop.js` is unregistered and no installed rule file in any tool contains the verify-gate prose.
  - [ ] Given `gates.director=off`, when sync runs, then the delegate gate is gone from Claude, Codex reads it as off at runtime from `~/.craftkit-state/gate-*` with `hooks.json` unchanged, and rule 12a is absent from all 4 tools.
  - [ ] Given `gates.routing=off`, when a prompt is submitted, then the hook output carries the tier line and no skill-first gate text, and the skill-first and announce hooks are unregistered.
  - [ ] Given `playwright=on` then `playwright=off`, when sync runs twice after the flip, then the craftkit-installed skill is removed and the second run reports `(up to date)`.
  - [ ] Given `humanizer=off`, when sync runs, then both humanizer paths are gone and `/pr-message` reports `Humanized: SKIPPED`.
  - [ ] Given `CRAFTKIT_DASHBOARD=1` in env and `dashboard=off` in config, when sync runs, then the dashboard installs (env wins).
  - [ ] Given an existing `~/.craftkit-state/dashboard` file and no config, when sync runs, then the config has `dashboard=on` and behavior is unchanged.
  - [ ] Given stdin `</dev/null`, when `install.sh` or `sync.sh` runs, then nothing prompts and defaults apply.
  - [ ] Given `bash sync.sh --configure` on a TTY, when the user changes a box, then the config updates and the same run syncs it.
  - [ ] Given an unknown key or value, when sync runs, then it warns once and keeps the prior setting.
  - [ ] `bash check.sh` exits 0, and each new check fails when its guarded behavior is removed.

## Task Plan
**Updated:** 2026-10-12T00:00:00Z · **By:** /plan

Reuse, not new machinery: rule 12a already sits in a `CRAFTKIT-DIRECTOR` marker block (`rules/using-agent-skills.md:346`) that Cursor and Gemini strip per adapter (check 23c), and the dashboard already shows the opt-in hook pattern (`adapters/claude.sh:40`, `_claude_prune_hooks`). Rules do not pass through `craftkit_render_injected`, so gate stripping needs its own shared call in each adapter's rule install.

| ID | Task | Acceptance | Depends on | TCs | Executes via |
|----|------|-----------|-----------|-----|--------------|
| T1 | Add `craftkit_config_resolve` to `sync.sh`: parse `~/.craftkit-state/config` (bash 3.2), apply env > file > default, warn on bad lines, migrate the `dashboard` state file. Define the contract hooks read at runtime: one file per resolved gate value in `~/.craftkit-state/` | Fixture: config + env combos resolve as specced; bad line warns once and keeps prior value; legacy file migrates; state files written | none | TC-002, TC-012, TC-013, TC-016 | /build |
| T2 | Replace `craftkit_dashboard_resolve` with a T1 read; keep `CRAFTKIT_DASHBOARD` as an env alias | Existing dashboard check still passes; no config produces the same output as before | T1 | TC-001, TC-012 | /build |
| T3 | Inventory first, then wrap. Add a `check.sh` scan that renders all 4 tools with each group off and greps rendered rules **and** `hooks/*.js` emit text for gate vocabulary (`MANDATORY GATE`, `Director mode`, `Stop hook`, `ListAgents`, `TaskStop`, gate hook filenames). Wrap or move every hit into `CRAFTKIT-GATE-VERIFY`, `CRAFTKIT-GATE-ROUTING`, or the existing `CRAFTKIT-DIRECTOR` block. Known hits: `rules/using-agent-skills.md:34-37`, `:304`, `:342-349`, `:385` | Scan exits clean with every group off; marker names equal T1's group names | T1 | TC-004, TC-005 | /build |
| T4 | Add shared `craftkit_strip_gate_blocks` in `sync.sh`, called from every adapter's rule install (Claude, Codex, Cursor, Gemini). Group off: drop the block and its content. Group on: drop only the new VERIFY/ROUTING marker lines, so output stays byte-identical. DIRECTOR markers stay where check 23c expects them | Fixture diffs no-config output against the rendered previous release tag (`git show <prev tag>:rules/...`); group-off fixtures have no block content in any tool | T1, T3 | TC-001, TC-004, TC-005, TC-017 | /build |
| T5 | Claude hooks: drop each off group's rows from `_CRAFTKIT_HOOKS` (verify: `gate-verify-on-stop.js`; director: `gate-delegate.js`; routing: `gate-skill-first.js`, `gate-announce-honored.js`) so `_claude_prune_hooks` unregisters them; keep user-narrowed matchers. Owns the `adapters/claude.sh` hook-wiring edit | settings.json fixture loses exactly the off group's hooks; re-on restores them; narrowed matcher kept with a note | T1 | TC-004, TC-005, TC-017, TC-018 | /build |
| T6 | `craftkit-routing.js` reads T1's state files: routing off emits only the tier and installed-skills lines; director off drops the `Director mode:` line (`hooks/craftkit-routing.js:144`). Both on: byte-identical to today | Hook fed a fixture prompt per state: expected lines present or absent; all on matches today's output | T1, T5 | TC-005, TC-007 | /build |
| T7 | Codex: `gates.director` explicit value overrides `CRAFTKIT_DELEGATE`; unset keeps it off. `gates.verify` off skips its verify gate in `craftkit-codex.js`. Update `scripts/test-codex.py` | test-codex.py passes for unset, on, and off | T1 | TC-005, TC-006 | /build |
| T8 | Humanizer toggle: move its install in `ensure_tools` behind the config; off removes `~/.agents/skills/humanizer` and the `~/.claude/skills/humanizer` symlink on every sync, not only under `AGENTIC_SETUP` | Fixture: off removes both paths; second sync is a no-op | T1 | TC-003, TC-011 | /build |
| T9a | Playwright install: on runs `npm i -g @playwright/cli@latest` and `playwright-cli install --skills=agents -g`, records ownership in state; missing npm or Node < 20 warns and sync completes | Fixture with stubbed npm/playwright-cli: installs, records ownership; missing npm warns, `Sync complete.` printed | T1 | TC-008, TC-010 | /build |
| T9b | Playwright teardown: off removes the owned skill, and the package only if owned; second sync is a no-op | Fixture: on then off removes owned items; a preinstalled copy stays; second run `(up to date)` | T9a | TC-008, TC-009 | /build |
| T10 | Checklist: `install.sh` (TTY and no config) and `sync.sh --configure` show the 6 toggles with current values, write the config, then sync. Non-TTY never prompts | `</dev/null` runs never block; manual TTY run flips one box and applies it | T1 | TC-014, TC-015 | /build |
| T11 | `check.sh`: one check per toggle off (fixture HOME), the no-config baseline, and a toggle-back-on case. Add a mutation harness that sed-removes the strip and teardown calls in a temp copy and asserts each check fails | `bash check.sh` exits 0; harness shows each new check failing on its mutation | T2, T3, T4, T5, T6, T7, T8, T9b, T10 | TC-001, TC-003, TC-017, TC-019 | /build |
| T12 | README configuration section and Enforcement gates update, `install.sh:24` caveman comment fix, minor bump (package.json + README header + CHANGELOG) | check.sh version and README checks pass; `bash sync.sh` twice, second run `(up to date)` | T11 | TC-003 | /build |
| T13 | Specific subagent labels. First verify which field the agent list shows: `ListAgents` showed the `subagent_type` (`plan-roaster`), and an untyped spawn falls back to `general-purpose`; whether the task panel also shows `description`, or a `name` field exists in this build, is [UNVERIFIED]. Then require the strongest available label: a named craftkit agent type where one fits, otherwise a task-specific `description` (and `name` if supported). Require a 3-5 word task-specific `description` in every spawn instruction: rule 12a contract, the director line in `hooks/craftkit-routing.js:144`, and each `commands/*.md` / `skills/*/SKILL.md` spawn site (`ideate`, `research`, `parallel-*`, `define`). Pattern: `<verb> <object>`, e.g. `Review EVPMR layers`, never `general-purpose` or `agent` | check.sh greps every spawn instruction for a `description` requirement; a test spawn shows the label in the agent list | none | none | /build |

**Parallelizable now:** T1, T13
**Critical path:** T1 → T3 → T4 → T11 → T12

**Roaster (plan-roaster, 5/10) folded in:** gate prose also lives outside the planned blocks and in hook emit text (`hooks/craftkit-routing.js:144`), so T3 now starts with a vocabulary scan rather than a hook-filename grep; T4 strips the new marker lines when a group is on so TC-001 holds; T6 depends on T5 and gains director-off; T9 split; T11 automates TC-019 with a mutation harness.

## Decisions
_(pointers appended by /adr)_
