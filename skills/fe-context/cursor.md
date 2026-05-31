---
description: Generate and maintain docs/context.md from branch changes for all other skills to consume
alwaysApply: false
---

Respond briefly — minimal tokens, bullets over prose, no filler. Use `rtk` prefix for terminal commands.
Before acting, read the relevant files to understand existing code and patterns. Ask if anything is unclear — never assume.

When asked to generate or update feature context:

## What to collect

Run these commands to gather changes across all three layers:

**Staged (uncommitted):** `rtk git diff --cached --name-status` + `rtk git diff --cached`
**Committed, not pushed:** `rtk git log @{u}..HEAD --oneline` + `rtk git diff @{u}..HEAD`
**Pushed on branch vs base:** `rtk git log main...@{u} --oneline` + `rtk git diff main...@{u}`

## What to write

Find the project root (nearest `package.json`). Create or update `docs/context.md` there with:

- **Summary** — 2-4 sentences on what is being built
- **Changed files** — grouped by layer (staged / committed-not-pushed / pushed)
- **Key changes** — bullets: what was added, modified, removed
- **Architecture patterns in use** — which Entry/View/Presenter/Model/Resource files; state, styling, tracking
- **Test coverage needed** — files/functions that are new or changed and lack tests

If `docs/context.md` already exists, update sections that changed — preserve any manually added notes.

## When other tasks are requested

Always check for `docs/context.md` in the project root first. If present, read it before doing anything else — do not re-scan the project. If absent, tell the user to run `/fe-context` first.
