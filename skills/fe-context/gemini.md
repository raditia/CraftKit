## Feature Context Skill

**Response style:** Brief. Minimal tokens. Bullets over prose. No filler.
**Commands:** Use `rtk` prefix — `rtk git diff`, `rtk git log`, `rtk git status`.
**Context first:** Read relevant files and understand existing patterns before acting. Ask if anything is unclear — never assume.

---

## Context hierarchy

Structure context from most persistent to most transient:

| Level | What | Where |
|-------|------|--------|
| 1 — Rules | Project conventions (EVPMR pattern, Token styling, RTK) | Skills files |
| 2 — Spec | What's being built, constraints, decisions | `docs/context.md` |
| 3 — Source | Only files touched by this branch | Diff |
| 4 — Errors | Failing tests, lint errors, TypeScript errors | Run on demand |
| 5 — History | Conversation; compact when switching tasks | Session |

**Selective include:** only load what is relevant to the current diff. Target < 2,000 lines of focused context.

---

## Generating or updating feature context

**Inline plan first:** emit a brief plan before executing, pause if anything seems off.

**Collect changes:**
- Staged: `rtk git diff --cached --name-status` + `rtk git diff --cached`
- Committed not pushed: `rtk git log @{u}..HEAD --oneline` + `rtk git diff @{u}..HEAD`
- Pushed vs base: `rtk git log main...@{u} --oneline` + `rtk git diff main...@{u}`

**Conflict detection — scan the diff before writing. Surface each violation explicitly:**
```
CONFLICT: file:line
  Found: [what the diff shows]
  Expected: [what the pattern requires]
  Options: A) ... B) ...
  → Awaiting direction.
```
Never silently resolve conflicts. Never invent missing requirements — ask.

**Write `docs/context.md`** (project root = nearest `package.json`):

```markdown
# Feature Context
**Branch:** <branch> | **Base:** <base> | **Budget:** ~<lines> lines (target < 2,000)

## L2 — Summary
<2-4 sentences on what is being built>

## L2 — Constraints & Key Decisions
<bullets>

## L3 — Changed Files
### Staged | ### Committed, not pushed | ### Pushed
<table per layer: file, change type, role (Entry/View/Presenter/Model/Resource/test)>

## L3 — Key Changes
<bullets with file refs>

## L2 — Architecture Patterns in Use
<EVPMR files involved; state approach; Token styling; tracking events>

## L4 — Known Issues
<lint errors, TypeScript errors, failing tests — empty if none>

## L2 — Conflicts / Ambiguities
<unresolved conflicts — not silently fixed>

## L3 — Test Coverage Needed
<new or changed files/functions lacking tests>

## L2 — Suggested Skill Updates
<patterns observed not yet in any skill>
```

If file exists, update changed sections only — preserve manually added notes.

---

## Consuming context in other tasks

Read `docs/context.md` using selective include — only the sections relevant to the current task. Surface ambiguity rather than guessing.

**Anti-patterns:**
- **Context starvation** — acting without loading context → hallucinated patterns
- **Context flooding** — loading entire files not relevant to the task
- **Stale context** — using context.md from a different task without refreshing
- **Silent confusion** — guessing when context conflicts with code; always surface and ask
