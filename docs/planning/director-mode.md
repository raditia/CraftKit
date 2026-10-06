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
  3. The new hook prompts (does not block) when the main turn edits a second distinct source file; it passes for subagent (sidechain) edits, task-notification turns, and single-file edits. Behavioral `check.sh` fixtures cover all four cases; the ask case is confirmed failing before the hook exists.
  4. Edits landed by a background agent get verified: the agent's contract carries the project's verify command and its result. On the notification turn of an agent that edited source, the Stop gate blocks until the verify command has run (`check.sh` fixture), and the live runs show "not verified" rather than "done" when it has not.
  5. Cursor and Gemini installed output changes only by the removal of blocks meant for other tools (`CRAFTKIT-DIRECTOR`, and for Cursor also `CRAFTKIT-CODEX`, which leaks into it today): a `sync.sh` diff on a fixture HOME, with those blocks stripped from the `main` side, is empty.
  6. `bash check.sh` exits 0 and a second consecutive `sync.sh` reports `(up to date)` everywhere.
- **In scope:**
  - Keep rule #12 in `rules/using-agent-skills.md` unchanged for every tool, and add a `CRAFTKIT-DIRECTOR` marker block after it that supersedes its "Main task" row for Claude and Codex (pattern: `adapters/claude.sh:81` strips `CRAFTKIT-CODEX`). The block carries: delegate threshold (main works directly on answers, a lookup in a known file, an edit confined to one file; everything multi-file, multi-step, long-running, or an orchestrator command goes to a background agent), agent contract (goal, inputs, output, done check, verify command), isolation (one editing agent in the main checkout, concurrent editors `isolation: worktree`, read-only agents unrestricted), refinement relay (tweak → `SendMessage`, pivot → `TaskStop` + respawn), integration (review against the contract, confirm verify, merge worktrees).
  - Routing-hook text in `hooks/craftkit-routing.js` mirrors the rule (one line).
  - New hook `hooks/gate-delegate.js` (PreToolUse, soft prompt), reusing `craftkit-transcript.js` for `sidechain` / `notification` / turn edits; `_CRAFTKIT_HOOKS` row in `adapters/claude.sh`; README Enforcement-gates entry.
  - Extend `hooks/gate-verify-on-stop.js`: on a task-notification turn, collect dirty files changed since the finished agent was spawned, not since the turn began.
  - Strip `CRAFTKIT-DIRECTOR` in the Gemini adapter, and both `CRAFTKIT-DIRECTOR` and `CRAFTKIT-CODEX` in the Cursor adapter (`adapters/cursor.sh:37-39` filters no blocks today).
  - Codex: the Codex runtime section of `using-agent-skills.md` gets the same threshold and contract, worded to the Codex primitives that verification confirms exist.
  - `check.sh` behavioral fixtures for the hook and the background-verify report.
- **Out of scope:**
  - Cursor and Gemini behavior.
  - `/team-build`.
  - Internals of `/parallel-*`, `/fix`, `/define`: they are launched in the background, not rewritten.
  - A hard-blocking gate, a queue/scheduler for tasks, a dashboard of running agents.
- **Constraints:** bash 3.2 for adapters; hooks are Node with absolute non-version-pinned node path (check.sh); no em-dashes in prose; README sync matrix; shipped agent profiles set `omitClaudeMd: true` (`check.sh:2054` checks only `agents/*.md`), so for them the verify command arrives only through the contract payload; a generic agent's CLAUDE.md loading is not guaranteed either way, so the contract always carries it.
- **Key decisions:**
  - Always-on, chosen by task size, not an opt-in mode: the author wants the behavior without remembering a switch; the threshold keeps trivial turns cheap.
  - Hook fires on the 2nd source file, not the 1st (plan-roaster suggested the 1st): the 1st would prompt on the single-file edits the threshold allows. If the measured delegate rate misses the bar, escalate to a prompt-time check rather than a 1st-edit trigger.
  - Soft prompt, not block: integration and merge edits are legitimate main-session multi-file work, and a soft prompt lets them through with one click. Task-notification turns are exempt outright, since that is where integration usually happens (`hooks/gate-skill-first.js:50` already exempts them the same way).
  - Background-edit verification is enforced in the Stop gate, with the contract as the first line: the gate collects dirty files whose mtime/ctime is at or after `turn.startedAt`, only when the turn delegated or wrote through the shell (`hooks/gate-verify-on-stop.js:74-75,109`). A background agent's edits land after the spawning turn ends and before the notification turn starts, so neither turn sees them. Measuring from the finished agent's spawn time on the notification turn closes that. Stop is the only event guaranteed to run on a reply-only turn; a PreToolUse ask would never fire there (cross-review, consensus). Corrects an earlier wrong "turn-start snapshot" description.
  - One writer in the main checkout, worktree for concurrent editors: keeps rule #12's existing "separate worktrees" law without paying a merge on every solo task.
- **Risks & open questions:**
  - Codex background agents and mid-run messaging are UNVERIFIED. The first task checks the Codex docs/CLI; if Codex lacks non-blocking spawn or messaging, its section degrades to "delegate, wait, integrate" and criterion 1 is Claude-only.
  - Mid-size tasks pay a subagent round-trip and cold context; measure on one real task before tuning the threshold.
  - Worktree merges can conflict; the rule says the main session surfaces a conflict to the user rather than resolving it silently.
  - A user-typed integration turn ("merge the worktrees") gets a false soft prompt; accepted cost, one click. Docs/planning edits never count toward the second file.
  - Finding the finished agent's spawn time from the notification (matching its tool-use id to the spawning call in the main transcript) is unproven; T4b establishes it, or falls back to the session's oldest still-running background spawn.
  - Cursor sessions lose the `CRAFTKIT-CODEX` text they carry today; it was Codex-only guidance, so this is a fix, but it is a visible Cursor change.
- **Acceptance:**
  - [ ] `CRAFTKIT-DIRECTOR` block added after rule #12 with threshold, contract, isolation, relay, integration; rule #12 itself unchanged; token-audited.
  - [ ] Routing hook carries one director line; check.sh routing checks still pass.
  - [ ] `gate-delegate.js` prompts on 2nd source file in a main turn; passes sidechain, notification, single-file; fixtures prove each.
  - [ ] Stop gate blocks a notification turn whose agent edited source with no verify run, and passes once verify ran; fixtures prove both.
  - [ ] Codex section updated to verified primitives, or degradation stated.
  - [ ] Cursor/Gemini installed output changes only by stripped foreign blocks.
  - [ ] README hook + rule rows updated; CHANGELOG + version bump.
  - [ ] `bash check.sh` exit 0; `sync.sh` twice, second run all `(up to date)`.

## Task Plan
**Updated:** 2026-10-06 · **By:** /plan

| ID | Task | Acceptance | Depends on | TCs | Executes via |
|----|------|-----------|-----------|-----|--------------|
| T1 | Establish whether Codex supports non-blocking subagent spawn and mid-run messaging to a running subagent | Cited note in `docs/research/` answering both yes/no from primary sources (Codex docs or CLI source) | none | none | /research |
| T2 | Add a `CRAFTKIT-DIRECTOR` block after rule #12 (rule #12 unchanged); strip it in the Gemini adapter, and strip it plus `CRAFTKIT-CODEX` in the Cursor adapter. Claude primitives only; Codex wording goes in T6 | `bash check.sh` exit 0, plus a new check that the Claude block carries `CRAFTKIT-DIRECTOR` and Gemini/Cursor output does not; no em-dash | none | none | direct edit |
| T2b | Measure: sync the draft, run 5 multi-file and 5 single-file canned prompts in live Claude Code; record delegated, follow-up answered mid-run, refinement relayed, "not verified" reported | Rates written into this file; bar: ≥4/5 multi-file delegate, ≤1/5 single-file delegate. Miss → add a prompt-time task to T4 before continuing | T2, T3 | none | manual (author) |
| T3 | Add one director line to `hooks/craftkit-routing.js` mirroring T2 | `bash check.sh` routing checks pass; line names threshold + background delegation | T2 | none | direct edit |
| T4 | Add `hooks/gate-delegate.js` (PreToolUse, soft ask) using `craftkit-transcript.js`; `_CRAFTKIT_HOOKS` row in `adapters/claude.sh`; README Enforcement-gates entry | New `check.sh` behavioral check: asks on 2nd distinct source file in a main turn; passes sidechain, notification, single-file, docs/planning edits. The ask case confirmed failing before the hook exists | T2b | none | direct edit, then /code-quality |
| T4b | Extend `gate-verify-on-stop.js`: on a task-notification turn, measure dirty files from the finished agent's spawn time (tool-use id → spawning call timestamp) instead of `turn.startedAt` | `check.sh` fixtures: notification turn after an agent edited source, no verify run → blocks (confirmed failing first); verify run → passes; agent edited nothing → passes. Spawn time not found → fall back to the oldest running background spawn, stated in the hook | T2b | none | direct edit, then /code-quality |
| T5 | Add a `check.sh` content check that rule #12 keeps the verify-command contract field and the "not verified" report wording | Check fails when either phrase is removed, passes with T2's text | T2 | none | direct edit |
| T6 | Update the Codex runtime section of `using-agent-skills.md` to T1's verified primitives, or state the delegate-wait-integrate degradation | Section names only primitives T1 confirmed; `bash check.sh` exit 0 | T1, T2 | none | direct edit |
| T7 | Prove Cursor and Gemini output changed only by stripped foreign blocks | `sync.sh` into a fixture HOME on `main` and on the branch; strip `CRAFTKIT-CODEX` from `main`'s Cursor output, then `diff -r` of Cursor rules and `~/GEMINI.md` is empty | T2, T3, T6 | none | direct (bash) |
| T8 | README rule/hook rows, CHANGELOG section, version bump in `package.json` + README header | `bash check.sh` version and README checks pass | T4, T4b, T5, T6 | none | direct edit |
| T9 | Final gate: `check.sh`, `sync.sh` twice, re-run T2b's prompts with hooks installed | `bash check.sh` exit 0; second `sync.sh` all `(up to date)`; T2b bar still met | T7, T8 | none | /parallel-ship |

**Parallelizable now:** T1, T2
**Critical path:** T2 → T3 → T2b → T4 → T8 → T9
**Cross-review:** 2026-10-06, claude + codex, 1 error 2 warnings 2 suggestions folded: rule #12 kept with an added director block, Cursor strips foreign blocks, notification verify moved to the Stop gate, mechanism corrected.
**Roaster:** 5/10 (2026-10-06). Folded: measurement task T2b, notification-turn verify check T4b, Codex wording isolated to T6, director marker block for criterion 5. Partly rejected: 1st-edit hook trigger (contradicts the single-file threshold).

## Decisions
_(pointers appended by /adr)_
