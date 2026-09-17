---
name: fe-context
description: Derive the branch's change context from git and emit it into the turn: staged, committed and pushed changes, mapped to EVPMR layers. Writes no file. Run at the start of any other fe-* skill, or once in a workflow's Phase 0 and pass the result down.
alwaysApply: false
---

**Commands:** `rtk git diff`, `rtk git log`, `rtk git status`, `rtk ls .`
**Model:** cheapest tier (see the plan-aware Model routing table in `using-agent-skills`). Escalate to everyday if diff spans > 10 files with complex interdependencies.

---

> **Core behaviors:** Surface conflicts; never silently resolve them. Emit an inline plan before executing. Verify output before claiming done. See `/using-agent-skills`.

---

# Feature Context Engineering

Feed the right information at the right time. This skill derives what the branch changed, from git, **into the turn**. It stores nothing (ADR-0002): a recorded git fact is stale the moment the next commit lands, and the cache it replaced could not see staged work at all. Intent lives per feature under `docs/planning/` (ADR-0001), which this skill does not touch.

## Context hierarchy

| Level | What | Where |
|-------|------|--------|
| 1. Rules | Project conventions (EVPMR, Token styling, RTK) | Skills files |
| 2. Intent | What's being built, constraints, key decisions | `docs/planning/<slug>.md` |
| 3. Source | Only files touched by this branch | Diff output |
| 4. Errors | Failing tests, lint errors, TypeScript errors | On demand |
| 5. History | Conversation; compact when switching major tasks | Session |

**Selective include:** only include what is relevant to the diff. Hard limit: **< 600 lines / ~800 tokens**. Do not dump entire unrelated files. Summarize rather than paste full file contents.

---

## Step 0: Inline plan

Emit this before proceeding:
```
PLAN:
1. Find project root (nearest package.json)
2. Detect base branch
3. Collect: staged → committed-not-pushed → pushed-on-branch
4. Analyse diff, map to hierarchy levels
5. Surface any conflicts or ambiguities
6. Emit the derived context into the turn, writing no file
7. Verify output
→ Proceeding unless redirected.
```

---

## Step 1: Find project root

Walk up from CWD to the nearest `package.json` directory. All paths relative to it.

---

## Step 2: Detect base branch

```bash
git remote show origin | grep "HEAD branch"
```
Default to `main` if the command fails.

---

## Step 3: Collect changes

**A. Staged (uncommitted):**
```bash
rtk git diff --cached --name-status
rtk git diff --cached
```

**B. Committed, not yet pushed:**
```bash
rtk git log @{u}..HEAD --oneline
rtk git diff @{u}..HEAD
```
If `@{u}` errors (no upstream), skip and note it.

**C. Pushed on branch vs base:**
```bash
rtk git log main...@{u} --oneline
rtk git diff main...@{u}
```

---

## Step 4: Conflict detection

Before writing anything, scan the diff for violations:
- `View*.tsx` with `useState` / `useEffect` / API hooks
- `Presenter*.ts` returning JSX
- Inline styles or magic numbers instead of `Token.*`
- `// eslint-disable` without a documented reason

For each violation found, **do not silently resolve**:
```
CONFLICT: file:line
  Found: [what the diff shows]
  Expected: [what the pattern requires]
  Options: A) ... B) ...
  → Awaiting direction.
```

If requirements are missing or ambiguous, stop and ask; do not invent.

---

## Step 5: Emit the derived context

**Write no file.** Emit the block below into the turn, for the skill or workflow that asked. In a
workflow, derive once in Phase 0 and pass it down; a per-skill re-derivation of the same diff is
the same content paid for twice.

Keep it under ~600 lines / ~800 tokens. Summarize aggressively; never paste whole files.

```markdown
DERIVED CONTEXT
Branch: {{branch}} | Base: {{base}} | HEAD: {{short sha}}

## Feature Summary
{{2-4 sentences: what is being built, user-facing purpose, scope}}

## Changed Files
### A. Staged (uncommitted)
| File | Change | Role |
|------|--------|------|
### B. Committed, not pushed
| File | Change | Role |
|------|--------|------|
### C. Pushed on branch
| File | Change | Role |
|------|--------|------|

## Key Changes
{{bullets with file refs: what was added, modified, removed}}

## Architecture Patterns in Use
- **Structure:** {{which Entry/View/Presenter/Model/Resource files involved}}
- **State:** {{hooks, React Query, Redux usage}}
- **Styling:** {{Token values and StyleSheet patterns in play}}
- **Tracking:** {{tracker events being added}}

## Known Issues
{{lint errors, TypeScript errors, failing tests. Empty if none.}}

## Conflicts / Ambiguities
{{Unresolved conflicts surfaced above. Not silently fixed.}}

## Test Coverage Needed
{{new or changed files and functions that lack tests}}
```

No `Generated:` timestamp and no recorded baseline commit, because nothing persists to go stale
against. Freshness is not a property this output can lack: it is derived from the working tree as
it stands when asked.

**A legacy `docs/context.md` is migrated, then deleted.** Move any `<!-- BEGIN PLANNING -->` block
into the feature's intent file (ADR-0001), then remove the file. Leaving it behind means the next
reader trusts a snapshot nobody refreshes.

---

## Step 6: Verify

- [ ] All three layers (A/B/C) represented or noted as empty
- [ ] Conflicts in the Conflicts section, not silently resolved
- [ ] Under ~600 lines; summarize aggressively if over
- [ ] No unrelated files dumped in
- [ ] No file written

Report: layers covered, conflict count, line count.

---

## Anti-patterns

| Anti-pattern | Problem | Fix |
|---|---|---|
| Context starvation | Acting without deriving context → wrong patterns | Derive at the start of the task |
| Context flooding | Loading entire files not relevant to the task | Selective include: only diff-relevant content |
| Storing the output | A recorded git fact is stale on the next commit, and cannot see staged work | Emit into the turn; write no file (ADR-0002) |
| Silent confusion | Guessing when context conflicts with code | Surface with CONFUSION: format, wait for answer |
