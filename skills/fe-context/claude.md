**Token mode:** caveman. Min tokens, max signal. Bullets > prose. No filler.
**Commands:** always prefix with `rtk` — `rtk git diff`, `rtk git log`, `rtk git status`, `rtk ls .`

---

**Context first:** Understand the branch and git state before generating anything. No assumptions.

---

Generate or update `docs/context.md` in the current working project root with a full picture of what is being developed on this branch.

---

## Step 1 — Find the project root

Walk up from the current working directory until you find a directory containing `package.json`. That is the project root. All further paths are relative to it.

## Step 2 — Determine base branch

```bash
git remote show origin | grep "HEAD branch"
```
Default to `main` if the command fails.

## Step 3 — Collect changes across all three layers

**Layer A — Staged (uncommitted):**
```bash
rtk git diff --cached --name-status    # files changed
rtk git diff --cached                  # full diff
```

**Layer B — Committed but not yet pushed:**
```bash
rtk git log @{u}..HEAD --oneline       # local commits not on remote
rtk git diff @{u}..HEAD                # their diff
```
If `@{u}` errors (no upstream set), skip Layer B and note it.

**Layer C — Pushed on branch vs base:**
```bash
rtk git log main...@{u} --oneline      # pushed commits ahead of base
rtk git diff main...@{u}              # their diff
```
Replace `main` with the actual base branch from Step 2.

## Step 4 — Analyze the combined diff

From all three layers, derive:
- **What is being built** — feature name, user-facing purpose, 2-4 sentence plain English summary
- **Changed files** — grouped by layer (A/B/C) and by role (Entry/View/Presenter/Model/Resource/test/config)
- **Key changes** — what was added, modified, or removed; new props, new states, new API calls, new routes
- **Architecture patterns in use** — which parts of Entry/View/Presenter/Model/Resource are involved; state management approach; styling; tracking
- **Test coverage needed** — which files/functions/branches are new or changed and lack tests

## Step 5 — Write or update `docs/context.md`

Create the `docs/` folder if it doesn't exist. If `docs/context.md` already exists, update only the sections that changed — preserve any sections the user has manually annotated.

Use this exact format:

```markdown
# Feature Context
<!-- managed by fe-context — regenerate with /fe-context -->
**Generated:** {{ISO timestamp}}
**Branch:** {{current branch name}}
**Base:** {{base branch}}

## Summary
{{2-4 sentence plain English description of what is being built}}

## Changed Files

### A — Staged (uncommitted)
| File | Change |
|------|--------|
| path/to/file.tsx | modified |

### B — Committed, not pushed
| File | Change |
|------|--------|

### C — Pushed on branch
| File | Change |
|------|--------|

## Key Changes
- {{bullet: what was added/changed/removed}}

## Architecture Patterns in Use
- **Structure:** {{which Entry/View/Presenter/Model/Resource files are involved}}
- **State:** {{hooks, Redux, React Query usage}}
- **Styling:** {{Token values, StyleSheet patterns in play}}
- **Tracking:** {{tracker events being added}}

## Test Coverage Needed
- {{file or function}} — {{cases to cover}}
```

## Step 6 — Report

Print: path to `docs/context.md`, which layers had changes, and the one-line summary of what was detected.
