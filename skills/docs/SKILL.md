---
name: docs
description: Produce feature documentation in two registers from one source of truth — a technical version for engineers and a non-technical version for stakeholders — as Confluence-paste-ready markdown, then run both through /humanizer to strip AI-writing tells. Use after a feature ships or a spec is settled. Adapted from addyosmani/agent-skills documentation (MIT).
alwaysApply: false
---

**Model:** cheapest for the draft — escalate to everyday if technical accuracy depends on subtle system behavior. The `/humanizer` pass runs on its own model.

> **Core behaviors:** Same facts, two registers — never let the audiences disagree. Document the *why*, not just the what. See `/using-agent-skills`.
> **Explains, doesn't decide.** `/docs` describes what exists/was built. Decisions belong in `/adr`; requirements in `/spec`.

---

## When to use

A feature is built or a spec is settled and two audiences need it: engineers who will maintain/extend it, and stakeholders (PM, support, leadership) who need to understand what it does and why — without the code.

Source of truth, in priority order: the `docs/context.md` PLANNING block (`/spec` + `/plan`), any `docs/adr/*`, then the actual code/diff. Read them before writing — do not invent capabilities.

---

## Two registers, one truth

Write both from the same facts. They must never contradict — the stakeholder version is a *lossy projection* of the technical one, not a different story.

| | Technical (engineers) | Non-technical (stakeholders) |
|---|---|---|
| **Audience** | Maintainers, reviewers, future you | PM, support, leadership |
| **Answers** | How it works, how to extend, how it fails | What it does, who it's for, why it matters |
| **Includes** | Architecture, data flow, APIs, edge cases, gotchas, how to run/test | User-facing behavior, benefits, limits, rollout, support notes |
| **Excludes** | Marketing framing | Code, jargon, internal type names |
| **File** | `docs/<feature>.md` | `docs/<feature>-overview.md` |

Rules:
- No jargon in the stakeholder version without a plain-language gloss. If a term can't be said plainly, it probably doesn't belong there.
- Every stakeholder claim traces to a real technical fact — no aspirational capability.
- Both document the *why* (pull from `/adr` and the spec's Key Decisions), not only the *what*.

---

## Humanize pass — required when available

Both documents are AI-drafted → run each through the humanizer to strip AI-writing tells.

```bash
test -f ~/.claude/skills/humanizer/SKILL.md && echo "humanizer: present" || echo "humanizer: absent"
```

- **Present** → invoke `/humanizer` on each doc. Instruct it to preserve markdown structure verbatim — headings, tables, and inline `code` pass through untouched. Use the humanized output as final.
- **Absent** → note it and ship the un-humanized draft. (Only Claude Code and OpenCode expose `/humanizer`; on Cursor/Copilot/Gemini/Codex/Crush this step is a no-op by design — same as `/pr-message`.)

Optional voice match: if the user points to a writing sample, pass it to `/humanizer` for voice calibration.

---

## Output format — Confluence-paste-ready markdown

Both documents are **plain markdown meant to be pasted into Confluence** (via the editor's `/Markdown` insert or the `+` → *Markdown* option). Write markdown that survives that paste — stick to constructs Confluence maps cleanly:

| Use | Avoid (Confluence mangles or drops) |
|-----|-------------------------------------|
| `#`–`####` headings, `**bold**`, `*italic*` | Raw HTML tags (`<div>`, `<br>`, `<details>`) |
| GitHub-style pipe tables with a header row | HTML tables, merged/nested cells |
| Fenced code blocks with a language (```ts) | Indented (4-space) code blocks — become paragraphs |
| Standard `-` bullets, `1.` ordered lists | Deep nesting (> 3 levels) — flattens |
| `[text](url)` links, inline `code` | Footnotes, task-list checkboxes, emoji shortcodes |

Rules: one H1 per doc; don't skip heading levels; blank line before every table and code fence; relative links (`docs/adr/0001-x.md`) → make absolute or drop, they won't resolve in Confluence.

## Deliver

1. **Write files** — `docs/<feature>.md` (technical) and `docs/<feature>-overview.md` (stakeholder).
2. **Also print each full doc to the chat in one fenced block per doc** — so the raw markdown can be copied straight into Confluence without opening the file. Fence with `markdown` and note "select-all inside this block → paste into Confluence".

```
DOCS — <feature>
Technical:    docs/<feature>.md          (printed below for copy)
Stakeholder:  docs/<feature>-overview.md (printed below for copy)
Format:       Confluence-paste-ready markdown ✓
Humanized:    YES / SKIPPED (humanizer absent)
Consistency:  stakeholder claims trace to technical facts ✓
```
