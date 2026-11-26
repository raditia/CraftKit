---
name: untangle-codebase
description: Refactor a whole codebase or named area to expose hidden coupling, separate unrelated responsibilities, and remove surplus structure. Use when asked to untangle a codebase end to end; includes a decision log, implementation, and independent review.
---

**Model:** everyday. Escalate architecture decisions with significant tradeoffs per `using-agent-skills`.

> `/ponytail-audit` reports repository bloat without editing. `/code-quality` handles a focused review or simplification. This skill carries structural refactoring through implementation and verification.

## 1. Establish scope

Use the requested area or concern; otherwise cover the repository. Read project conventions and record the starting revision plus existing staged, unstaged, and untracked changes. Preserve pre-existing work; resolve overlapping edits before dependent changes. Establish the existing test/build/lint baseline before changing source. Preserve the project's architecture contracts: colocation improves discovery within those contracts, rather than replacing EVPMR, MVP, or MVVM-C with a different architecture.

Offer these optional additions unless the user already chose them:

| Addition | What it does |
|----------|--------------|
| Comments | Remove comments that only restate the code. |
| Tests | Remove tests that wouldn't catch a real bug, and fix the ones that fail without one. |

Ask which additions to include, using the host's question tool when available. Continue the structural investigation while awaiting the answer; apply only selected additions. Without an answer, leave optional cleanup out. Updating tests affected by the refactor remains part of preserving behavior.

## 2. Inventory before editing

Ask of each boundary: **should these pieces change together?** Record concrete problems with `file:line` evidence and a change scenario that demonstrates the cost.

| Category | Look for |
|----------|----------|
| Hidden links | Duplicated rules or values; globals or files connecting modules implicitly; scattered feature changes; undocumented call order or conventions |
| Needless links | Callers depending on internals; stable code depending on volatile details; general helpers carrying one caller's vocabulary; interfaces that expose every internal change |
| Surplus | Pass-through wrappers without a contract of their own; unused extension points; dead code with no static, dynamic, configuration, or external consumers |

Inventory special cases too: value-specific branches, caller-specific parameters, swallowed exceptions, retries, sleeps, and disabled tests. Each is a question about requirements, not proof of a defect. Explain what it protects before proposing removal. The protected list and `flag:` / `ponytail:` contracts in `karpathy-guidelines` still apply.

Use Git history, when available, as evidence of what changes together. Generate dependency maps or stripped source skeletons only when useful, in scratch space without overwriting source. Inspect function bodies before making decisions about their behavior.

Keep a decision log at the project's existing planning location, or `docs/planning/untangle-codebase.md` if none exists. Record scope, baseline revision and existing failures, selected additions, problems, decisions, verification, and unresolved items. Refresh evidence when the tree changes; follow the grounding rule.

## 3. Design fixes around causes

Group problems under the smallest structural fix that resolves their shared cause. Bring things that change together behind a coherent boundary, separate independent responsibilities, and direct dependencies toward stable contracts. Reuse existing abstractions first; a new interface needs actual consumers or variation that justify it.

For each fix, record why it improves a representative change, affected callers and contracts, and the check that will prove behavior is preserved. Prefer deletion or a local boundary adjustment over a framework rewrite. Surface conflicts with project conventions and decisions needing user input before dependent edits.

Example decision-log entry:

```text
Fix: Let the existing dialog restore focus to its opener.
Problems:
  - ui/LogoutDialog.tsx:30 waits 100ms before focusing the input.
  - ui/SettingsDialog.tsx:61 sets a global skipRefocus flag for nested dialogs.
Verify: Closing nested dialogs restores focus to the correct opener; keyboard navigation still works.
Status: pending
```

## 4. Implement and verify in increments

Work through the evidence-backed list in dependency order, keeping each increment reviewable and running its checks before proceeding. Remove special cases only when the redesign preserves the requirement they served. Keep necessary exceptions and record why they remain. A bug discovered during restructuring needs a regression check and an explicit behavior-change note; unrelated bug work stays outside scope.

If Comments was selected, remove implementation narration. Keep external constraints, non-obvious rationale, public API documentation, and protected markers. Remove workaround explanations only when their workaround is gone.

If Tests was selected, do that cleanup last so the suite remains a safety net during restructuring. Replace internal-coupling assertions with observable behavior checks. Remove a test only after showing it cannot catch a regression or that another test protects the same behavior. Retain smoke tests and basic assertions; follow project coverage gates.

## 5. Independently inspect and repeat

Use read-only subagents to inspect the final structure for hidden links, needless links, surplus, and unexplained special cases. Follow `using-agent-skills` for native runtime execution and model routing. Give each worker a bounded area, the baseline and final diff, full relevant source contents, project conventions, the decision log, verification results, and the grounding/protected-marker rules. Cold reviewers report missing material as `not provided`; investigation workers may read their assigned files. Collect every result and verify findings before editing.

If native spawning is unavailable, perform the same checks sequentially and report the missing independent review. Repeat implementation and review while actionable findings remain within scope. A blocked requirement or check is an unresolved item, not a reason to expand scope or claim completion.

Done means every inventory item is fixed or explicitly retained with a reason, representative changes cross fewer hidden boundaries, final project gates pass, and no actionable in-scope review finding remains. Report actual checks, behavior changes, retained exceptions, and review gaps. Failed or unavailable verification means the result is incomplete.

## Attribution

Adapted from [caldoai/skills: untangle-codebase](https://github.com/caldoai/skills/blob/main/skills/untangle-codebase/SKILL.md). CraftKit adds project architecture boundaries, incremental verification, evidence requirements, and native-runtime review handling.

<!--
MIT License

Copyright (c) 2026 Maze

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
-->
