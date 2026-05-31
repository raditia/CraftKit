---
description: Generate and maintain docs/context.md using context hierarchy — all other skills read it instead of re-scanning the project
alwaysApply: false
---

Respond briefly — minimal tokens, bullets over prose, no filler. Use `rtk` prefix for terminal commands.
Before acting, read relevant files to understand existing patterns. Ask if anything is unclear — never assume.

---

## Context hierarchy

Structure everything across five levels — from most persistent to most transient:

1. **Rules** — project-wide conventions (Entry/View/Presenter/Model/Resource, Token styling, RTK commands) — always in skills
2. **Spec / this file** — what is being built, constraints, key decisions — `docs/context.md`
3. **Relevant source files** — only files touched by this branch
4. **Errors / test state** — failing tests, lint errors, TypeScript errors
5. **Conversation history** — accumulates; compact when switching major tasks

**Selective include:** only load what is relevant to the current diff. Do not summarise the whole project. Target < 2,000 lines of focused context.

---

## When generating or updating feature context

**Collect changes:**
- Staged: `rtk git diff --cached --name-status` + `rtk git diff --cached`
- Committed not pushed: `rtk git log @{u}..HEAD --oneline` + `rtk git diff @{u}..HEAD`
- Pushed vs base: `rtk git log main...@{u} --oneline` + `rtk git diff main...@{u}`

**Inline plan before generating:** emit a brief plan, pause if anything seems wrong.

**Conflict detection — before writing, scan the diff for:**
- View files with useState/useEffect/API calls
- Presenter files returning JSX
- Inline styles or magic numbers instead of Token.*
- eslint-disable without documented reason

For each conflict found, surface it explicitly — do NOT silently resolve:
```
CONFLICT: file:line — found X, expected Y per pattern
Options: A) ... B) ... → Awaiting direction.
```

**Write `docs/context.md`** (find project root via nearest `package.json`):
- L2: Feature summary, constraints, key decisions
- L3: Changed files by layer (staged/committed/pushed), key changes with file refs
- L2: Architecture patterns in use (which EVPMR files; state; styling; tracking)
- L4: Known issues (lint errors, TypeScript errors, failing tests)
- L2: Conflicts / ambiguities (unresolved, not silently fixed)
- L3: Test coverage needed

If file exists, update changed sections only — preserve manually added notes.
Note context budget at the top. Flag if > 2,000 lines.

---

## When other tasks are requested

Read `docs/context.md` first. Use **selective include** — only load the sections relevant to the current task, not the whole file. If ambiguity exists in the context, surface it rather than guessing.

Anti-patterns to avoid:
- **Context starvation** — acting without loading context.md → hallucinated APIs, wrong patterns
- **Context flooding** — loading entire project files not relevant to the task
- **Stale context** — using context.md from a different task without refreshing
- **Silent confusion** — guessing when context conflicts with code
