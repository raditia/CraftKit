**Token mode:** caveman. Min tokens, max signal. Bullets > prose. No filler.
**Commands:** always prefix with `rtk` — `rtk git diff`, `rtk git log`, `rtk git status`, `rtk ls .`

---

**Context first:** Understand the branch and git state before generating anything. No assumptions.

---

Generate or update `docs/context.md` in the current working project root. This file is the single source of truth for what is being developed — all other skills read it instead of re-scanning the project.

---

## Step 0 — Inline plan

Before doing anything, emit this plan and pause if anything seems wrong:

```
PLAN:
1. Find project root (nearest package.json)
2. Detect base branch
3. Collect: staged changes → committed-not-pushed → pushed-on-branch
4. Analyse diff → map to context hierarchy levels
5. Surface any conflicts or ambiguities
6. Write/update docs/context.md
7. Verify output
→ Proceeding unless redirected.
```

---

## Step 1 — Find the project root

Walk up from CWD to the nearest directory containing `package.json`. All paths are relative to it.

---

## Step 2 — Detect base branch

```bash
git remote show origin | grep "HEAD branch"
```
Default to `main` if the command fails.

---

## Step 3 — Collect changes across three layers

**Layer A — Staged (uncommitted):**
```bash
rtk git diff --cached --name-status
rtk git diff --cached
```

**Layer B — Committed, not yet pushed:**
```bash
rtk git log @{u}..HEAD --oneline
rtk git diff @{u}..HEAD
```
If `@{u}` errors (no upstream set), skip and note it.

**Layer C — Pushed on branch vs base:**
```bash
rtk git log main...@{u} --oneline
rtk git diff main...@{u}
```
Replace `main` with the actual base branch.

---

## Step 4 — Map to the context hierarchy

Structure your analysis across these levels — the same levels that consumers of this file will navigate:

| Level | What it covers | Source |
|-------|---------------|--------|
| 1 — Rules | Project-wide conventions (EVPMR pattern, Token styling, RTK commands) | Already in skills |
| 2 — Spec / this feature | What is being built, constraints, key decisions | Derived from diff |
| 3 — Relevant source files | Only files touched by this branch | From diff file list |
| 4 — Errors / test state | Failing tests, lint errors, TypeScript errors | Run if relevant |

**Selective include rule:** only include what is directly relevant to the diff. Do not summarise the whole project. Aim for < 2,000 lines of focused context.

---

## Step 5 — Surface conflicts and ambiguities

Before writing the document, scan the diff for:

- A `View*.tsx` file with `useState`/`useEffect`/API calls — violation of pattern
- A `Presenter*.ts` returning JSX — violation of pattern
- A new dependency imported but not in `package.json`
- Styling that uses inline styles or magic numbers instead of `Token.*`
- Any `// eslint-disable` without a documented reason

For each conflict found, do NOT silently generate context around it. Surface it explicitly using this format:

```
CONFLICT: [file:line]
  Found: [what the diff shows]
  Expected: [what the pattern requires]
  Options:
    A) [option]
    B) [option]
  → Awaiting direction before proceeding.
```

If requirements are missing or ambiguous, stop and ask rather than invent.

---

## Step 6 — Write or update `docs/context.md`

Create `docs/` if it doesn't exist. If `docs/context.md` already exists, update changed sections only — preserve any manually annotated notes.

Use this exact format:

```markdown
# Feature Context
<!-- managed by fe-context — regenerate with /fe-context -->
<!-- context hierarchy: L1=rules(skills), L2=this file, L3=source files below, L4=errors/tests -->
**Generated:** {{ISO timestamp}}
**Branch:** {{branch name}}
**Base:** {{base branch}}
**Context budget:** ~{{line count}} lines (target < 2,000)

---

## L2 — Feature Summary
{{2-4 sentences: what is being built, user-facing purpose, scope}}

## L2 — Constraints & Key Decisions
{{bullets: non-obvious decisions or constraints introduced by this branch}}

## L3 — Changed Files

### A — Staged (uncommitted)
| File | Change | Role |
|------|--------|------|
| path/to/file.tsx | modified | View |

### B — Committed, not pushed
| File | Change | Role |
|------|--------|------|

### C — Pushed on branch
| File | Change | Role |
|------|--------|------|

## L3 — Key Changes
{{bullets: what was added, modified, removed — with file references}}

## L2 — Architecture Patterns in Use
- **Structure:** {{which Entry/View/Presenter/Model/Resource files are involved}}
- **State:** {{hooks, React Query, Redux usage}}
- **Styling:** {{Token values and StyleSheet patterns in play}}
- **Tracking:** {{tracker events being added}}

## L4 — Known Issues
{{Any lint errors, TypeScript errors, failing tests found during context collection. Empty if none.}}

## L2 — Conflicts / Ambiguities
{{Any places where the diff diverges from established patterns — surface for human decision.
  Format: CONFLICT: file:line — found X, expected Y}}

## L3 — Test Coverage Needed
{{Files/functions that are new or changed and lack tests}}

## L2 — Suggested Skill Updates
{{Patterns observed in the diff not yet covered by any skill}}
```

---

## Step 7 — Verify

After writing:
- [ ] Context.md exists at the correct project root
- [ ] All three change layers (A/B/C) are represented or explicitly noted as empty
- [ ] Any conflicts are surfaced in the Conflicts section, not silently resolved
- [ ] Context budget is noted — flag if > 2,000 lines
- [ ] No entire unrelated files dumped in — only diff-relevant content

Report: path written, layers covered, conflict count, line count.
