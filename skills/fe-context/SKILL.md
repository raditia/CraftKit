---
name: fe-context
description: Generate or update docs/context.md from staged/committed/pushed branch changes. Run this before any other fe-* skill.
alwaysApply: false
---

**Commands:** `rtk git diff`, `rtk git log`, `rtk git status`, `rtk ls .`
**Model:** everyday — escalate if diff spans > 10 files with complex interdependencies

---

> **Core behaviors:** Surface conflicts — never silently resolve them. Emit an inline plan before executing. Verify output before claiming done. See `/using-agent-skills`.

---

# Feature Context Engineering

Feed the right information at the right time. `docs/context.md` is the single source of truth for what is being developed on this branch. All other skills read it instead of re-scanning the project.

## Context hierarchy

| Level | What | Where |
|-------|------|--------|
| 1 — Rules | Project conventions (EVPMR, Token styling, RTK) | Skills files |
| 2 — Spec | What's being built, constraints, key decisions | `docs/context.md` |
| 3 — Source | Only files touched by this branch | Diff output |
| 4 — Errors | Failing tests, lint errors, TypeScript errors | On demand |
| 5 — History | Conversation; compact when switching major tasks | Session |

**Selective include:** only include what is relevant to the diff. Hard limit: **< 600 lines / ~800 tokens**. Do not dump entire unrelated files. Summarize rather than paste full file contents.

---

## Step 0 — Inline plan

Emit this before proceeding:
```
PLAN:
1. Find project root (nearest package.json)
2. Detect base branch
3. Collect: staged → committed-not-pushed → pushed-on-branch
4. Analyse diff, map to hierarchy levels
5. Surface any conflicts or ambiguities
6. Write/update docs/context.md
7. Verify output
→ Proceeding unless redirected.
```

---

## Step 1 — Find project root

Walk up from CWD to the nearest `package.json` directory. All paths relative to it.

---

## Step 2 — Detect base branch

```bash
git remote show origin | grep "HEAD branch"
```
Default to `main` if the command fails.

---

## Step 3 — Collect changes

**A — Staged (uncommitted):**
```bash
rtk git diff --cached --name-status
rtk git diff --cached
```

**B — Committed, not yet pushed:**
```bash
rtk git log @{u}..HEAD --oneline
rtk git diff @{u}..HEAD
```
If `@{u}` errors (no upstream), skip and note it.

**C — Pushed on branch vs base:**
```bash
rtk git log main...@{u} --oneline
rtk git diff main...@{u}
```

---

## Step 4 — Conflict detection

Before writing anything, scan the diff for violations:
- `View*.tsx` with `useState` / `useEffect` / API hooks
- `Presenter*.ts` returning JSX
- Inline styles or magic numbers instead of `Token.*`
- `// eslint-disable` without a documented reason

For each violation found — **do not silently resolve**:
```
CONFLICT: file:line
  Found: [what the diff shows]
  Expected: [what the pattern requires]
  Options: A) ... B) ...
  → Awaiting direction.
```

If requirements are missing or ambiguous — stop and ask, do not invent.

---

## Step 5 — Write or update `docs/context.md`

Create `docs/` if needed. If file exists, update changed sections — preserve manually added notes.

```markdown
# Feature Context
<!-- managed by fe-context — regenerate with /fe-context -->
<!-- L1=rules(skills) L2=this file L3=source-files L4=errors/tests -->
**Generated:** {{ISO timestamp}}
**Branch:** {{branch}} | **Base:** {{base}} | **Budget:** ~{{lines}} lines (limit: 600)

---

## L2 — Feature Summary
{{2-4 sentences: what is being built, user-facing purpose, scope}}

## L2 — Constraints & Key Decisions
{{bullets: non-obvious decisions or constraints from this branch}}

## L3 — Changed Files

### A — Staged (uncommitted)
| File | Change | Role |
|------|--------|------|

### B — Committed, not pushed
| File | Change | Role |
|------|--------|------|

### C — Pushed on branch
| File | Change | Role |
|------|--------|------|

## L3 — Key Changes
{{bullets with file refs: what was added, modified, removed}}

## L2 — Architecture Patterns in Use
- **Structure:** {{which Entry/View/Presenter/Model/Resource files involved}}
- **State:** {{hooks, React Query, Redux usage}}
- **Styling:** {{Token values and StyleSheet patterns in play}}
- **Tracking:** {{tracker events being added}}

## L4 — Known Issues
{{lint errors, TypeScript errors, failing tests. Empty if none.}}

## L2 — Conflicts / Ambiguities
{{Unresolved conflicts surfaced above. Not silently fixed.}}

## L3 — Test Coverage Needed
{{Files/functions that are new or changed and lack tests}}

## L2 — Suggested Skill Updates
{{Patterns observed in the diff not yet covered by any skill}}
```

---

## Step 6 — Verify

- [ ] `docs/context.md` written at the correct project root
- [ ] All three layers (A/B/C) represented or noted as empty
- [ ] Conflicts in the Conflicts section — not silently resolved
- [ ] Context budget ≤ 600 lines — summarize aggressively if over
- [ ] No unrelated files dumped in

Report: path written, layers covered, conflict count, line count.

---

## Anti-patterns

| Anti-pattern | Problem | Fix |
|---|---|---|
| Context starvation | Acting without loading context → wrong patterns | Load docs/context.md before any task |
| Context flooding | Loading entire files not relevant to the task | Selective include — only diff-relevant content |
| Stale context | Using context.md from a different task | Re-run /fe-context when switching tasks |
| Silent confusion | Guessing when context conflicts with code | Surface with CONFUSION: format, wait for answer |
