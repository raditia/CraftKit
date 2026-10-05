---
name: context-source
description: Connect, replace, disconnect or inspect the team docs repos (PRDs, specs, SQL, meeting notes, decisions on GitHub) this project's planning consults. Use when the user wants to connect a docs repo, switch or remove one, or see which are connected. /interview, /spec and /plan then check asks against them.
alwaysApply: false
---

**Model:** cheapest, since every step is a helper call plus one file edit.

> **Lifecycle only.** Searching and citing happen inside `/interview`, `/spec` and `/plan`.

---

## Commands

Run from inside the project.

| Ask | Run |
|---|---|
| Connect a docs repo | `bash ~/.craftkit/bin/context-source.sh connect <url or owner/repo>` |
| Swap one for another | `bash ~/.craftkit/bin/context-source.sh replace <old> <new>` |
| Remove one | `bash ~/.craftkit/bin/context-source.sh disconnect <source>` |
| What is connected | `bash ~/.craftkit/bin/context-source.sh status` |
| Clean up projects that no longer exist | `bash ~/.craftkit/bin/context-source.sh forget-stale` |

1. **Run the command.** `pruned <path> (<size>)` means a cache was deleted because no project uses
   it any more; say so with the size.
2. **On a non-zero exit, report and stop.** `2` is a refusal: a URL with a credential in it (tell
   the user to use their git credential helper or ssh instead), no access, an unknown source, or an
   unreadable store. `3` means no node, `5` a runtime failure. Never retry with a modified URL or a
   token.
3. **Mark old citations historical, only on a `replaced <old> with <new>` or `disconnected <old>`
   line.** `<old>` there is the normalized key `github.com/<owner>/<repo>`. In each
   `docs/planning/*.md` (not `*.tests.md`) whose frontmatter has `status: active`, find `sources:`
   entries with `kind: git` whose `ref` starts with `<old>#` (compare lowercase) and set their
   `connection:` to `historical`, adding the key when it is missing. Change nothing else: `ref` and
   `seen` stay, since a historical citation still proves what was reviewed. On `already connected`,
   mark nothing.
4. **Report:**

```
CONTEXT SOURCES: <project root>
- <source> sha <first 12 of sha=> branch <branch=>  (shared with <number of shared-with roots> projects)
<pruned, forgot and stale lines as printed>
Marked historical in: <planning files changed, for the author to commit>
```

`no sources connected` is reported as is. `stale project=<path>` is a project whose folder is
missing; suggest `forget-stale` only after the user confirms the folder is really gone, since an
unmounted drive shows the same way.
