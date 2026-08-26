---
name: research
description: Delegate a question to a background agent that investigates primary sources only (official docs, source code, specs, first-party APIs) and writes a cited Markdown note into the repo. Use for topic research, API/doc fact-gathering, or reading legwork while you keep working. Adapted from mattpocock/skills research (MIT).
alwaysApply: false
---

**Model:** everyday.

---

## Method

1. Spawn a **background agent** (`general-purpose`) so the main session keeps working while it reads.
2. Agent brief:
   - Investigate against **primary sources** (official docs, source code, specs, first-party APIs), never a secondary write-up of them. Follow every claim back to the source that owns it.
   - Write findings to a single Markdown file, citing each claim's source (URL or `file:line`).
   - Save where the repo already keeps such notes (match the existing convention); if none exists, `docs/research/<slug>.md` and say so.
3. On completion, relay the file path plus a 3-line summary of findings, so the user does not have to open the file to know the answer.
