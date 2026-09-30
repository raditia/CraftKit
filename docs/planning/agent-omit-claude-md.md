---
slug: agent-omit-claude-md
status: active
created: 2026-09-30
---

# Cold agents skip CLAUDE.md

## Spec
**Updated:** 2026-09-30T13:40+07:00 · **By:** /spec

- **Objective:** Every craftkit agent spawn inherits the ~45 KB (~11k token) CRAFTKIT managed block from `~/.claude/CLAUDE.md`, a third of its 32.6k-token floor, and uses none of it: the rules an agent needs already arrive through `craftkitInject`. Cut that floor without losing the project conventions a reviewer relies on.
- **Users & job:** Anyone running `/parallel-review`, `/parallel-ship`, `/parallel-build`, `/eval`, `/define` or `/plan`. They want the same review quality at a lower token cost per agent.
- **Success:**
  - A craftkit agent spawned in a fresh session cannot quote the global managed block. It can still see org managed policy.
  - A `bulk-read` probe that makes no tool calls, run from this repo's cwd, drops at least 8k below its 32.6k baseline (same agent, same cwd, same `subagent_tokens` meter).
  - `check.sh` fails when any `agents/*.md` omits the field.
- **In scope:**
  - `omitClaudeMd: true` in the frontmatter of all 16 `agents/*.md`.
  - A `PROJECT CONVENTIONS:` entry in the payload `CONTEXT:` blocks of `commands/parallel-review.md`, `commands/parallel-ship.md` and `commands/parallel-build.md`. It carries the repo-root `CLAUDE.md`, the files it `@`-imports, and the `.claude/rules/*.md` files without `paths:` frontmatter (the always-on ones). Each file is bounded by the existing ~1500-line rule, and `not present` stands in when there are none.
  - One `check.sh` check covering both halves.
  - The repo `CLAUDE.md` authoring rule #4 ("Agents are cold copies") reworded to say agents now also skip CLAUDE.md, so rule text reaches them only through `craftkitInject` or the payload.
  - README agents note. CHANGELOG `v1.50.0`. Version bump in `package.json` and the README header.
- **Out of scope:**
  - Correcting the repo `CLAUDE.md` claim that `SubagentStart` is display-only. The docs now say it can inject context, but this needs its own probe and change.
  - Moving the managed block for the main session, or for generic subagents (`general-purpose`, `Explore`). Those keep CLAUDE.md, and the editing agents are among them.
  - Project conventions for agents spawned outside the three orchestrators (`plan-roaster`, `eval-judge`, `bulk-read`, `/ideate` generators). Their inputs are plans, scores or a named file, not code judged against conventions.
  - `CLAUDE.local.md`, nested subdirectory `CLAUDE.md` files, path-scoped `.claude/rules` and `AGENTS.md` in the payload. These are a known coverage gap, and T8 surfaces it if it matters.
  - The Gemini, Codex and Cursor adapters. Craftkit agents are Claude-only.
- **Constraints:**
  - Needs Claude Code v2.1.271 or later. v2.1.285 is installed.
  - The docs contradict themselves: the field description says CLAUDE.md is skipped, while the `--agent` section says it still loads. So the fresh-session probe is the gate, not the docs.
  - Agent files load at session start, so verification needs a new session.
  - Must stay bash 3.2 compatible and pass `check.sh` plus two `sync.sh` runs.
- **Key decisions:**
  - Use the per-agent `omitClaudeMd` field (option B), not a SessionStart move (option C). It's a native feature, and the change is one line per agent with no marker migration. Main-session behavior is unchanged.
  - The project CLAUDE.md moves into the payload instead of being dropped (B over A). The saving comes only from the global block. The payload covers the common always-on layers (root file, `@imports`, unscoped `.claude/rules`), not the full hierarchy, so this is a slight narrowing, bounded by the out-of-scope list.
  - Rollback is deleting the field. Nothing on disk changes shape.
- **Risks & open questions:**
  - The field might not work as documented (see the docs contradiction above). The probe decides. If it fails, stop and fall back to option C.
  - A Claude Code version older than 2.1.271 may ignore the field or reject it. The risk is low: installed agents have carried the unknown key `craftkitInject:` since 2026-08-03 (`ad1411d`) and spawns work, so unknown keys are tolerated. Rejection is not proven impossible on every version.
  - Org managed policy must survive. If the probe cannot see it, the no-go stands, because losing it is a policy bypass, not a token regression.
  - A large project CLAUDE.md inflates every payload. That costs the same as today's implicit load.
- **Acceptance:**
  1. Every `agents/*.md` has `omitClaudeMd: true`. A new `check.sh` check fails before the field is added and passes after.
  2. That check also fails if any of the three `CONTEXT:` templates lacks `PROJECT CONVENTIONS:`.
  3. `sync.sh` installs the field into `~/.claude/agents/*.md`. A second run reports `(up to date)`.
  4. In a fresh interactive session from this repo's cwd, two probes that make no tool calls, `bulk-read` (plain-copy install) and `fe-review` (`craftkitInject` render path), each report the global block ABSENT using the baseline canary questions. Each reports the org policy text present, and ABSENT is a no-go. `bulk-read`'s `subagent_tokens` is at most 24.6k.
  5. `/parallel-review` on a real diff still returns findings, and its payload shows the project `CLAUDE.md` under `PROJECT CONVENTIONS:`.
  6. `bash check.sh` exits 0. README, CHANGELOG and version agree (check.sh already enforces this).

## Task Plan
**Updated:** 2026-09-30T13:50+07:00 · **By:** /plan

| ID | Task | Acceptance | Depends on | TCs | Executes via |
|----|------|-----------|-----------|-----|--------------|
| T1 | Spike: add `omitClaudeMd: true` to `agents/bulk-read.md` and `agents/fe-review.md` only, then sync | Both installed files carry the field (`fe-review` through the `craftkitInject` render path). A second `sync.sh` run reports `(up to date)` | none | none | direct edit + `sync.sh` |
| T2 | **Go/no-go:** the user opens a fresh interactive session in this repo and I spawn both probes with the baseline canary questions | Acceptance 4. Any fail (block visible, org policy absent, `bulk-read` floor > 24.6k) → stop, revert T1, re-spec as option C | T1 | none | fresh session, probe agents |
| T3 | Add a `check.sh` check: every `agents/*.md` has `omitClaudeMd: true`, and each of the 3 `CONTEXT:` templates names `PROJECT CONVENTIONS:` | Fails on the tree as it stands after T1 (14 agents and 3 templates missing) | T2 | none | direct edit |
| T4 | Add the field to the remaining 14 agents | T3's agent half passes | T2, T3 | none | direct edit |
| T5 | Add `PROJECT CONVENTIONS:` (root `CLAUDE.md`, its `@imports`, unscoped `.claude/rules/*.md`, else `not present`) to the payload `CONTEXT:` blocks of `parallel-review`, `parallel-ship`, `parallel-build` | T3's template half passes | T2, T3 | none | direct edit |
| T6 | Reword repo `CLAUDE.md` authoring rule #4 and add a README agents note about `omitClaudeMd` | `check.sh` passes, including its README and anchor checks | T2 | none | direct edit |
| T7 | Release: CHANGELOG `v1.50.0` (this feature plus the Stop-gate stale-dirt fix), version in `package.json` and README header | `bash check.sh` exits 0. `sync.sh` twice, the second run with no work | T4, T5, T6 | none | direct edit + `check.sh` + `sync.sh` |
| T8 | End-to-end: in a fresh session, run `/parallel-review` on a real diff | Findings returned with severity labels intact (including from `adversarial` and `ponytail-review` when selected), payload shows `PROJECT CONVENTIONS:`, per-agent tokens recorded against the 69k `code-quality` baseline | T7 | none | `/parallel-review` |

**T1 done 2026-09-30:** field installed in both agents, second sync `(up to date)`.

**T2 probe.** Spawn `bulk-read` and `fe-review` with this prompt, no tool calls allowed. The first three phrases occur only in the global block (0 hits in either installed agent file); the last occurs only in org managed policy.

> Answer from your instructions alone, no tools. For each phrase, reply PRESENT with the sentence containing it, or ABSENT: (1) "fusion panel" (2) "Ponytail rubric" (3) "Intent-first routing" (4) "tvlk-shared-bq-dev".

Go = 1–3 ABSENT, 4 PRESENT, `bulk-read` `subagent_tokens` ≤ 24.6k.

**T2 passed 2026-09-30** (session started 14:51, after the 14:09 agent install): both agents 1–3 ABSENT, 4 PRESENT. `subagent_tokens`: `bulk-read` 6,622, `fe-review` 9,371. The drop from 32.6k is ~26k, more than the ~11k block alone, so T8 should check what else the field drops. Partly answered by a second `bulk-read` probe: three phrases found only in the project `CLAUDE.md` (~25 KB) came back ABSENT, so the field drops the project file too, which T5's payload has to replace.

**T3 done 2026-09-30:** `check.sh` check 39 fails 17 times (14 agents, 3 templates), and every other check passes. **T6 done:** repo `CLAUDE.md` rule #4 and the README agents note name `omitClaudeMd` and `PROJECT CONVENTIONS:`.

**T4, T5, T7 done 2026-09-30:** 16/16 agents carry the field, 3/3 templates carry `PROJECT CONVENTIONS:`, v1.50.0 CHANGELOG + version. `check.sh` exits 0; `sync.sh` installed all, second run no work. Left: T8 in a fresh session.

**After T2 passes:** T3 and T6 in parallel, then T4 and T5 in parallel
**Critical path:** T1 → T2 → T3 → T4 → T7 → T8

## Decisions
_(pointers appended by /adr)_
