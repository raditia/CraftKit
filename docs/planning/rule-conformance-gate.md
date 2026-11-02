---
slug: rule-conformance-gate
status: active
created: 2026-09-29
---

# Project rule conformance gate

## Spec
**Updated:** 2026-09-29 · **By:** /spec

- **Objective:** Check a turn's source diff against the repository's own instructions before the agent finishes. When a high-confidence violation is found, return the cited rule and offending file so the agent can repair the change during the same completion cycle.
- **Users & job:** Engineers who sync CraftKit into Claude Code or Codex and want project rules in `AGENTS.md` and `CLAUDE.md` enforced when a conventional linter cannot check them.
- **Success:**
  1. In both hosts, a fixture with a qualifying rule violation at score >= 0.8 produces a Stop block naming the rule id, the exact quoted source line and its source file:line, and the changed file. The agent can repair it and the next Stop attempt passes.
  2. A checked turn with a valid rubric adds at most 15 seconds at the 95th percentile in the sanctioned environment; a turn with no source diff makes no judge call and adds at most 100 ms at the 95th percentile. Measure at least 20 runs of each case per host and report cold and warm judge times separately.
  3. Given the same rubric, diff and judge verdict fixture, Claude Code and Codex produce the same band, feedback, event and two-block limit. Host-specific hook output may differ.
  4. A repository without `.craftkit/rubric.json` makes no judge call, creates no gate state or event log, and preserves current Stop behavior.
- **In scope:**
  - A turn-start git snapshot and a Stop-time diff, including staged, unstaged, untracked and commits made during the turn; pre-existing changes alone do not trigger judgment. Scope judgment to changed source files and applicable rubric rules.
  - A committed `.craftkit/rubric.json` with stable rule id, judge question, exact quoted instruction and source file:line, source hash, and optional scope globs. A new `/rubric` skill compiles it from project instructions on request; the gate never recompiles it.
  - One batched, read-only judge invocation for each changed diff at Stop through an available sanctioned CLI: `claude -p --model sonnet` using its configured `ANTHROPIC_BASE_URL`, or `codex exec --output-schema` using its configured account. Reuse the result when a repeated Stop sees the identical diff and rubric; after a repair changes the diff, judge the new version once. The judge returns typed JSON verdicts with rule id, score, changed file and evidence. The hook validates all fields before acting.
  - Banding per rule: score >= 0.8 blocks with repair instructions; 0.5 <= score < 0.8 produces a visible note; score < 0.5 is silent. Stop can block at most twice for one logical user turn, including its automatic continuations.
  - Source-hash drift detection. The gate warns `rubric stale`, identifies affected rules and logs the condition. Stale rules do not block until `/rubric` refreshes them.
  - Append-only, gitignored `.craftkit/events.jsonl` recording verdict metadata, skips, truncation, judge errors and timeouts. Logs omit diff content, full source text, credentials and CLI output. A local audit command judges existing files against applicable rubric rules; a local report lists rule ids that fired and current rubric rules that never fired.
  - Hook installation and removal in `adapters/claude.sh` and `adapters/codex.sh`, including Codex's required `/hooks` trust review after installation or changes. Node handles runtime hook logic; sync and adapters remain Bash 3.2 compatible.
- **Out of scope:**
  - Per-edit checks or separate edit and turn rule phases.
  - Historical calibration or automatic rule tuning.
  - Cursor and Gemini host hooks.
  - Other model providers, direct API calls, personal keys, automatic rubric recompilation or built-in default rules.
- **Constraints:**
  - Judge authorization comes only from the installed host CLI's sanctioned account and configuration. The gate supplies no credential and does not redirect company data to another provider.
  - Missing CLI, unavailable network, deadline, invalid JSON or invalid verdict schema fail open and log a miss; none is recorded as a pass. No git repository or missing turn-start snapshot logs `cannot-verify`. A malformed rubric gets a visible note and no block. A missing rubric is inert.
  - Set an overall judge deadline consistent with the 15-second added-latency target. When the diff exceeds the configured input limit, retain only changed files covered by applicable scope globs, truncate within that set, and record the truncated paths/size; never silently present a partial diff as complete.
  - The child judge must have tools and hooks disabled or otherwise be guarded against recursively firing the conformance gate. It must operate read-only and receive only the bounded rubric and diff.
  - A new hook must have an `_CRAFTKIT_HOOKS` row and an Enforcement gates README entry for check 24. A new skill must have a routing entry and README row. Add behavioral checks for both hosts, fail-open cases and hook installation. Run `bash check.sh`, then `bash sync.sh` twice, with the second sync entirely up to date.
- **Key decisions:**
  - The repository owns the questions and quoted lines. CraftKit ships the compiler and runner, with no default rubric, so projects choose what is enforceable.
  - The model grades all applicable rules for a diff in one batch. A repair requires a fresh verdict for the changed diff; this is the only case where one logical user request can need another model call. Local code handles thresholds, schema validation, scope matching, source-hash checks, logging and block budgets deterministically.
  - The hook snapshots git state at user-prompt submission, before the agent's edits. The implementation must prove that automatic Stop continuations retain the original baseline and block budget, especially in Codex where a block creates a continuation prompt.
  - Codex uses a user-scope hook definition in `~/.codex/hooks.json`; a changed definition requires `/hooks` review before it runs. Its Stop payload includes `session_id`, `cwd` and `turn_id`; a JSON `{"decision":"block","reason":"..."}` continues the agent. See [official OpenAI hook documentation](https://learn.chatgpt.com/docs/hooks). The local `codex exec --help` confirms `--output-schema <FILE>`.
  - Audit and report are explicit local commands, so a normal Stop check stays limited to the current turn's diff.
- **Risks & open questions:**
  - Cold `claude -p` latency with roughly ten rules is unverified. A synthetic local attempt on 2026-09-29 returned `Not logged in` after 2.8 seconds, so it measured authentication failure, not judge latency. Benchmark with a sanctioned authenticated account and representative diff before committing to the 15-second target. If the target is not met, revise the scope or latency target with the author; do not silently lengthen the Stop deadline.
  - Confirm the exact Claude Code and Codex turn-start payloads, hook timeout behavior and continuation identity with end-to-end fixtures. Codex's documented `turn_id` may change on continuation; the two-block counter must still cover one logical user request.
  - Judge scores can be wrong or inconsistent. Validate rule ids and changed-file evidence against the supplied input; retain the source quote in the rubric so block feedback is traceable. Audit representative false positives before rollout.
  - Large, partially truncated diffs can hide violations. Log truncation and make the result visibly incomplete; never claim the entire diff passed.
- **Acceptance:**
  - [ ] `/rubric` produces a schema-valid committed rubric from `AGENTS.md`/`CLAUDE.md`, with exact quotes, locations, hashes and optional scope globs; an explicit rerun can refresh it after a source change.
  - [ ] A scripted two-host fixture covers clean diff, block at 0.8, note at 0.5, silence below 0.5, repair and rejudgment on continuation, unchanged-diff verdict reuse, and no third block for the same logical turn.
  - [ ] Fixtures show that pre-existing edits are excluded and turn edits from staged, unstaged, untracked and committed states are included; no source diff and no rubric skip without a judge call.
  - [ ] Fixtures cover stale and malformed rubrics, no git/snapshot, missing CLI, timeout, network error, invalid JSON/schema, scoped and huge diffs, and child judge recursion. Each yields the specified feedback and event without an erroneous pass or block.
  - [ ] Audit judges existing in-scope files; report uses the event log to list fired rule ids and zero-fire current rule ids. Event logs are ignored by git and contain no diff or credentials.
  - [ ] Codex hook installation, removal, trust review and a real Stop block are exercised; Claude Code installation, removal and Stop block are exercised. Neither host runs an untrusted changed Codex hook silently.
  - [ ] Latency report includes at least 20 authenticated runs per host for checked and no-diff turns, p95, cold and warm times, and shows the success thresholds above.
  - [ ] `bash check.sh` passes, the first `bash sync.sh` succeeds, and the second reports every destination up to date. README documents the new hook and skill.

## Task Plan
_(owned by /plan)_

## Decisions
_(pointers appended by /adr)_
