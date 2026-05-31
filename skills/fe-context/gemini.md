## Feature Context Skill

**Response style:** Brief. Minimal tokens. Bullets over prose. No filler.
**Commands:** Use `rtk` prefix — `rtk git diff`, `rtk git log`, `rtk git status`.
**Context first:** Read relevant files and understand existing code and patterns before acting. Ask if anything is unclear — never assume.

When generating or updating feature context, collect changes from three layers:

**Staged (uncommitted):** `rtk git diff --cached --name-status` + `rtk git diff --cached`
**Committed, not pushed:** `rtk git log @{u}..HEAD --oneline` + `rtk git diff @{u}..HEAD`
**Pushed vs base:** `rtk git log main...@{u} --oneline` + `rtk git diff main...@{u}`

Find the project root (nearest `package.json`). Create or update `docs/context.md` there:

```markdown
# Feature Context
**Branch:** <branch> | **Base:** <base>

## Summary
<2-4 sentences on what is being built>

## Changed Files
### Staged | ### Committed, not pushed | ### Pushed on branch
<table per layer>

## Key Changes
<bullets>

## Architecture Patterns in Use
<Entry/View/Presenter/Model/Resource involved; state, styling, tracking>

## Test Coverage Needed
<files/functions that are new or changed and lack tests>
```

If `docs/context.md` already exists, update only changed sections — preserve manually added notes.

**Lookup rule:** For all other tasks, check for `docs/context.md` in the project root first. If present, read it before doing anything else. If absent, tell the user to run `/fe-context` first.
