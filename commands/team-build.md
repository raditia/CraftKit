---
name: team-build
description: Experimental agent-teams build — this session acts as team lead (escalated model) coordinating everyday-model teammates through a shared task list. Teammates implement files in parallel and message each other directly. Platform-routed (RN/web EVPMR, Android MVP, iOS MVVM-C).
---

**Commands:** platform gates — see Phase 5
**Model:** lead = escalated (`claude-opus-4-8`), teammates = everyday (`claude-sonnet-5`)

> Triggered by: `/team-build` **only** — never auto-routed. "build feature X" in natural language still routes to `/parallel-build`. This command is an explicit opt-in: it requires the experimental agent-teams feature and costs roughly (1 + teammate count) × a solo build in tokens.

**Why teams:** subagents fit one-shot report-back work; teams fit collaborative implementation — task claiming, dependency auto-resolve, direct teammate messaging (full rationale: README).

---

## Phase −1 — Preflight (hard gates)

0. **Harness.** Agent teams are a **Claude Code runtime feature** (teammate spawn, shared task list, mailbox) — not a model capability. Running under any other synced tool (Cursor, Copilot, Gemini CLI, Codex CLI, Crush) → stop and fall back: `/parallel-build` where the tool has subagents (Cursor background agents, Gemini shell-parallel headless calls per the fusion-panel table in `using-agent-skills`), else sequential `/build`.
1. **Feature flag.** Check `echo "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"`. If not `1` → stop and instruct:
   ```json
   // settings.json
   { "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
   ```
   Restart the session after enabling. Do not proceed degraded — fall back to `/parallel-build` if the user declines.
2. **Lead model.** The team lead is *this* session — a command cannot switch it. If the session runs the everyday tier, warn: lead work is judgment-heavy (task DAG design, contradiction adjudication, synthesis) and merits `claude-opus-4-8` (`/model`). Proceed on everyday only with explicit user OK. *(Deliberate exception to the model-routing "never ask the user to switch" rule — inline escalation spawns cover targeted questions, not a session-long lead role.)*
3. **Session caveats — tell the user before spawning:**
   - `/resume` and `/rewind` do not restore in-process teammates — a long build interrupted mid-team restarts its coordination from the task list, not the conversation.
   - One team per session; teammates cannot spawn background subagents.
   - All teammates inherit the lead's permission mode at spawn.

---

## Phase 0 — Platform routing

Detect platform from project root + target module (same detection as `/build` Step 0):

| Platform | Scaffold | Implement guided by | Review | Tests |
|----------|----------|--------------------|--------|-------|
| RN / web (EVPMR) | `/fe-scaffold` | `/fe-patterns` + `/fe-performance` | `fe-review` **agent type** | `/fe-test` (≥93%) |
| Android (MVP) | `/android-scaffold` | `/android-patterns` + `/android-performance` | `/android-review` skill | `/android-test` |
| iOS (MVVM-C) | `/ios-scaffold` | `/ios-patterns` + `/ios-performance` | `/ios-review` skill | `/ios-test` |

FE reviewer teammate is spawned **from the `fe-review` agent definition** (`"spawn a teammate using the fe-review agent type"` — its tools allowlist and model are honored). Native platforms have no cold agent — spawn a plain teammate and instruct it to run the review skill (teammates are full sessions with all skills installed).

---

## Phase 1 — Context + scaffold (lead, sequential)

Scaffold **before** spawning the team — the scaffold's file list *is* the ownership map, and letting teammates scaffold concurrently invites file conflicts.

- FE: `/fe-context` then `/fe-scaffold` (surface assumptions first).
- Native: read a real sibling screen; `/android-context` / `/ios-context` only for multi-screen scope. Then the platform scaffold skill.

**Gate:** all scaffold files exist, platform typecheck passes.

---

## Phase 2 — Task DAG (lead writes the shared task list)

**Ownership law: one file, one owner, for the whole session.** Two teammates editing the same file causes silent overwrites — this is the feature's main hazard. Cross-file wiring that touches shared files (Dagger component, Bazel `BUILD`, navigation registry) is always a single dedicated task with one owner.

Create tasks with these dependencies (the task system auto-unblocks dependents):

**FE (EVPMR)**

| Task | Files | Depends on | Owner |
|------|-------|-----------|-------|
| T1 model | `Model*.ts` | — | impl-a |
| T2 resource | `Resource*.ts` | — | impl-b |
| T3 presenter | `Presenter*.ts` | T1 | impl-a |
| T4 view + entry | `View*.tsx`, `Entry*.tsx` | T2, T3 | impl-b |
| T5 review | read-only | T3, T4 | reviewer |
| T6 tests | `__tests__/*` | T5 | tester |

**iOS (MVVM-C)**

| Task | Files | Depends on | Owner |
|------|-------|-----------|-------|
| T1 contract | `*Contract.swift` | — | impl-a |
| T2 fetcher | `*Fetcher.swift` stub | — | impl-b |
| T3 viewmodel | `*ViewModel.swift` | T1, T2 | impl-a |
| T4 view + vc | `*View.swift`, `*ViewController.swift` | T1 | impl-b |
| T5 factory + coordinator wiring | `*Factory.swift`, coordinator edit | T3, T4 | impl-a |
| T6 review | read-only (`/ios-review`) | T5 | reviewer |
| T7 tests | ViewModel Quick+Nimble specs | T6 | tester |

**Android (MVP)**

| Task | Files | Depends on | Owner |
|------|-------|-----------|-------|
| T1 viewmodel + navmodel | `*ViewModel.kt`, `*NavigationModel.kt` | — | impl-a |
| T2 repository | `*Repository.kt` stub | — | impl-b |
| T3 presenter | `*Presenter.kt` | T1, T2 | impl-a |
| T4 view | Activity/Fragment + layout | T1 | impl-b |
| T5 dagger wiring | feature component/module | T3, T4 | impl-a |
| T6 review | read-only (`/android-review`) | T5 | reviewer |
| T7 tests | Presenter JUnit+MockK | T6 | tester |

---

## Phase 3 — Spawn the team (staged)

Four teammates, everyday model, named **impl-a**, **impl-b**, **reviewer**, **tester** — spawned when their first task can run, not upfront:

1. **Now:** impl-a + impl-b.
2. **When the last implementation task completes:** reviewer.
3. **When the review task completes:** tester.

An early-spawned reviewer burns its activation with nothing to review, then idles emitting notifications the lead must triage — and idle teammates sometimes self-assign speculative work. The lead is already woken by task-completion notifications at each stage boundary, so staging adds no polling and no extra coordination logic.

Every implementer's spawn prompt must state:
1. Its owned files (from the DAG) — **never edit outside this set**.
2. The platform skills to apply while implementing (Phase 0 table).
3. Contract questions go **directly to the owning teammate** (e.g. impl-a owns the Model — impl-b messages impl-a about prop types), not to the lead.
4. Definition of done per task: owned files typecheck clean → mark the task complete. Unmarked tasks block dependents.
5. Do not spawn subagents (unsupported for teammates).

Reviewer: findings only, severity labels per `using-agent-skills`, never edits files. Tester: coverage bar per platform (`/fe-test` enforces ≥93%; native reports module's actual coverage).

---

## Phase 4 — Lead coordination loop

- **Do not poll.** Act on teammate idle notifications and mailbox messages.
- **Task-status lag** (known caveat): a teammate can finish work but fail to mark the task complete, blocking dependents. Idle teammate + in-progress task → nudge it; still stale → verify the files yourself and mark the task complete or reassign.
- **Dead teammate** (infra error): apply Step 5 of `using-agent-skills` in spirit — its axis is a coverage gap, never silently clean. Reassign its tasks to the surviving implementer or take them inline; if the reviewer died and no re-review ran, the verdict is `INCOMPLETE`.
- **Contradictions** (reviewer vs implementer, or impl-a vs impl-b on a contract): lead adjudicates per core behavior #9 (`using-agent-skills`).

---

## Phase 5 — Gates (lead, after all tasks complete)

| Platform | Gates |
|----------|-------|
| FE | `rtk tsc --noEmit` + `rtk lint` + `rtk test --testPathPattern="<feature>" --coverage` (≥93% all four metrics) |
| Android | `./gradlew :<module>:lintGeneralDebug` + `./gradlew :<module>:testGeneralDebugUnitTest` |
| iOS | `swiftlint` + `bazelisk test //Modules/<M>:<M>TestsBundle` |

Teammates verified their own files; the lead verifies the **integration** — gates run on the whole feature, not per-file.

---

## Phase 6 — Synthesize + report

```
TEAM BUILD COMPLETE
────────────────────────────────────────
Platform:   FE / Android / iOS
Team:       impl-a, impl-b, reviewer, tester  (everyday) | lead (this session)
Tasks:      N complete / N total  [list any reassigned or lead-completed]
Files:      [list, with owner]

FINDINGS (from reviewer)
[ERROR]      file:line — description
[WARNING]    ...
[SUGGESTION] ...

Gates:      typecheck PASS | lint PASS | tests PASS (N tests)
Coverage:   [per platform bar]
Verdict:    DONE / BLOCKED — <blockers> / INCOMPLETE — <axis unverified: dead teammate / unreviewed reassignment>
```

Team config is auto-removed at session end; the task list persists under `~/.claude/tasks/` for post-mortem.
