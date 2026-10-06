---
slug: director-mode
status: active
created: 2026-10-06
---

# Director mode: main session delegates, chat stays open

## Spec
**Updated:** 2026-10-06 · **By:** /spec

- **Objective:** Make the main session the thinker: it routes, delegates and integrates, so any task above a size threshold runs in background subagents and the user can send a new task or a refinement while work is in flight.
- **Users & job:** Engineers running CraftKit in Claude Code or Codex who want to keep talking to the session while it works, and steer running work without waiting for it to finish.
- **Success:**
  1. Observed over 5 canned multi-file and 5 single-file prompts in live Claude Code: at least 4/5 multi-file prompts end the main turn after a background spawn and answer a follow-up mid-run; at most 1/5 single-file prompts delegate.
  2. Observed over the same runs: every refinement sent mid-run is relayed with `SendMessage` or answered with a stop-and-respawn, and the main reply names which in one line.
  3. The new hook prompts (does not block) when the main turn edits a second distinct source file; it passes for subagent (sidechain) edits, task-notification turns, and single-file edits. Behavioral `check.sh` fixtures cover all four cases, and each fails before the hook exists.
  4. Edits landed by a background agent get verified: the agent's contract carries the project's verify command and its result. On the notification turn of an agent that edited source with no verify result, a soft hook asks for one (`check.sh` fixture), and the live runs show "not verified" rather than "done" in that case.
  5. Cursor and Gemini installed output is byte-identical before and after this change (`sync.sh` diff on a fixture HOME), because director text lives in a `CRAFTKIT-DIRECTOR` marker block their adapters strip.
  6. `bash check.sh` exits 0 and a second consecutive `sync.sh` reports `(up to date)` everywhere.
- **In scope:**
  - Rewrite rule #12 in `rules/using-agent-skills.md`, director text inside a `CRAFTKIT-DIRECTOR` marker block (pattern: `adapters/claude.sh:81` strips `CRAFTKIT-CODEX`): delegate threshold (main works directly on answers, a lookup in a known file, an edit confined to one file; everything multi-file, multi-step, long-running, or an orchestrator command goes to a background agent), agent contract (goal, inputs, output, done check, verify command), isolation (one editing agent in the main checkout, concurrent editors `isolation: worktree`, read-only agents unrestricted), refinement relay (tweak → `SendMessage`, pivot → `TaskStop` + respawn), integration (review against the contract, confirm verify, merge worktrees).
  - Routing-hook text in `hooks/craftkit-routing.js` mirrors the rule (one line).
  - New hook `hooks/gate-delegate.js` (PreToolUse, soft prompt), reusing `craftkit-transcript.js` for `sidechain` / `notification` / turn edits; `_CRAFTKIT_HOOKS` row in `adapters/claude.sh`; README Enforcement-gates entry.
  - Codex: the Codex runtime section of `using-agent-skills.md` gets the same threshold and contract, worded to the Codex primitives that verification confirms exist.
  - `check.sh` behavioral fixtures for the hook and the background-verify report.
- **Out of scope:**
  - Cursor and Gemini behavior.
  - `/team-build`.
  - Internals of `/parallel-*`, `/fix`, `/define`: they are launched in the background, not rewritten.
  - A hard-blocking gate, a queue/scheduler for tasks, a dashboard of running agents.
  - Changing `gate-verify-on-stop.js` snapshot logic (the background gap is closed by the contract, not by the Stop hook).
- **Constraints:** bash 3.2 for adapters; hooks are Node with absolute non-version-pinned node path (check.sh); no em-dashes in prose; README sync matrix; the agent profile `omitClaudeMd: true` means agents learn the verify command only through the contract payload.
- **Key decisions:**
  - Always-on, chosen by task size, not an opt-in mode: the author wants the behavior without remembering a switch; the threshold keeps trivial turns cheap.
  - Hook fires on the 2nd source file, not the 1st (plan-roaster suggested the 1st): the 1st would prompt on the single-file edits the threshold allows. If the measured delegate rate misses the bar, escalate to a prompt-time check rather than a 1st-edit trigger.
  - Soft prompt, not block: integration and merge edits are legitimate main-session multi-file work, and a soft prompt lets them through with one click. Task-notification turns are exempt outright, since that is where integration usually happens (`hooks/gate-skill-first.js:50` already exempts them the same way).
  - Background-edit verification lives in the agent contract, not the Stop hook: the Stop hook diffs against a turn-start snapshot (`hooks/gate-verify-on-stop.js:45-56`), and a background agent's edits fall between turns, so no snapshot change fixes it without false positives on unrelated dirty files.
  - One writer in the main checkout, worktree for concurrent editors: keeps rule #12's existing "separate worktrees" law without paying a merge on every solo task.
- **Risks & open questions:**
  - Codex background agents and mid-run messaging are UNVERIFIED. The first task checks the Codex docs/CLI; if Codex lacks non-blocking spawn or messaging, its section degrades to "delegate, wait, integrate" and criterion 1 is Claude-only.
  - Mid-size tasks pay a subagent round-trip and cold context; measure on one real task before tuning the threshold.
  - Worktree merges can conflict; the rule says the main session surfaces a conflict to the user rather than resolving it silently.
  - A user-typed integration turn ("merge the worktrees") gets a false soft prompt; accepted cost, one click. Docs/planning edits never count toward the second file.
  - Reading a subagent's edits from its transcript (for the notification-turn check) is unproven; T4b establishes it or falls back to the agent's reported file list.
- **Acceptance:**
  - [ ] Rule #12 rewritten with threshold, contract, isolation, relay, integration; token-audited, no duplicate of existing #12 text.
  - [ ] Routing hook carries one director line; check.sh routing checks still pass.
  - [ ] `gate-delegate.js` prompts on 2nd source file in a main turn; passes sidechain, notification, single-file; fixtures prove each.
  - [ ] Background-agent report without a passing verify result is reported "not verified"; fixture proves it.
  - [ ] Codex section updated to verified primitives, or degradation stated.
  - [ ] Cursor/Gemini installed output unchanged.
  - [ ] README hook + rule rows updated; CHANGELOG + version bump.
  - [ ] `bash check.sh` exit 0; `sync.sh` twice, second run all `(up to date)`.

## Task Plan
**Updated:** 2026-10-06 · **By:** /plan

| ID | Task | Acceptance | Depends on | TCs | Executes via |
|----|------|-----------|-----------|-----|--------------|
| T1 | Establish whether Codex supports non-blocking subagent spawn and mid-run messaging to a running subagent | Cited note in `docs/research/` answering both yes/no from primary sources (Codex docs or CLI source) | none | none | /research |
| T2 | Rewrite rule #12 in `rules/using-agent-skills.md` with director text in a `CRAFTKIT-DIRECTOR` block; strip that block in the Gemini and Cursor adapters (check whether Cursor strips `CRAFTKIT-CODEX` today). Claude primitives only; Codex wording goes in T6 | `bash check.sh` exit 0; no text duplicated from other always-on rules; no em-dash | none | none | direct edit |
| T2b | Measure: sync the draft, run 5 multi-file and 5 single-file canned prompts in live Claude Code; record delegated, follow-up answered mid-run, refinement relayed, "not verified" reported | Rates written into this file; bar: ≥4/5 multi-file delegate, ≤1/5 single-file delegate. Miss → add a prompt-time task to T4 before continuing | T2, T3 | none | manual (author) |
| T3 | Add one director line to `hooks/craftkit-routing.js` mirroring T2 | `bash check.sh` routing checks pass; line names threshold + background delegation | T2 | none | direct edit |
| T4 | Add `hooks/gate-delegate.js` (PreToolUse, soft ask) using `craftkit-transcript.js`; `_CRAFTKIT_HOOKS` row in `adapters/claude.sh`; README Enforcement-gates entry | New `check.sh` behavioral check: asks on 2nd distinct source file in a main turn; passes sidechain, notification, single-file, docs/planning edits. Confirmed failing before the hook exists | T2b | none | direct edit, then /code-quality |
| T4b | Soft check on an agent's notification turn: agent edited source and its report has no verify result → ask for it | `check.sh` fixture: notification turn with edits and no verify result asks; with a verify result passes. Confirmed failing first. Transcript cannot show subagent edits → fall back to the agent's reported file list, stated in the hook | T2b | none | direct edit, then /code-quality |
| T5 | Add a `check.sh` content check that rule #12 keeps the verify-command contract field and the "not verified" report wording | Check fails when either phrase is removed, passes with T2's text | T2 | none | direct edit |
| T6 | Update the Codex runtime section of `using-agent-skills.md` to T1's verified primitives, or state the delegate-wait-integrate degradation | Section names only primitives T1 confirmed; `bash check.sh` exit 0 | T1, T2 | none | direct edit |
| T7 | Prove Cursor and Gemini installed output is unchanged | `sync.sh` into a fixture HOME on `main` and on the branch; `diff -r` of Cursor rules and `~/GEMINI.md` is empty | T2, T3, T6 | none | direct (bash) |
| T8 | README rule/hook rows, CHANGELOG section, version bump in `package.json` + README header | `bash check.sh` version and README checks pass | T4, T4b, T5, T6 | none | direct edit |
| T9 | Final gate: `check.sh`, `sync.sh` twice, re-run T2b's prompts with hooks installed | `bash check.sh` exit 0; second `sync.sh` all `(up to date)`; T2b bar still met | T7, T8 | none | /parallel-ship |

**Parallelizable now:** T1, T2
**Critical path:** T2 → T3 → T2b → T4 → T8 → T9
**Roaster:** 5/10 (2026-10-06). Folded: measurement task T2b, notification-turn verify check T4b, Codex wording isolated to T6, director marker block for criterion 5. Partly rejected: 1st-edit hook trigger (contradicts the single-file threshold).

## Decisions
_(pointers appended by /adr)_
