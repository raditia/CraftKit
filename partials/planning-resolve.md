---
name: planning-resolve
description: How to find the active feature's intent file under docs/planning/. Shared by every skill that reads or writes intent; spliced in at sync time, never loaded always-on.
---

## Resolving the active planning file

Intent lives in `docs/planning/<slug>.md`, one file per feature (ADR-0001). The mapping from
branch to feature is **derived, never recorded**, so there is no index to go stale:

```bash
rtk grep -l "^status: active" docs/planning/*.md 2>/dev/null | grep -v '\.tests\.md$'
```

`<slug>.tests.md` is the feature's test-case file, not a second feature, so it is excluded.

**Resolve once.** A skill handed a slug uses it and never resolves again, so no sub-step can land
on a different feature than its caller.

| Result | What it means | What to do |
|---|---|---|
| Exactly one | The normal case under a single-checkout workflow | Use it |
| Zero | No intent recorded for this work | Proceed without it, and say so. Never invent a spec, and never create the file outside `/spec` |
| Two or more | Usually a stray file that followed a branch switch, since untracked files survive `git checkout` | Resolve by diff, below |

**Two or more: match, then ask.** Compare each candidate's `## Spec` against the current diff
(`rtk git diff <base>...HEAD --name-only`). Exactly one candidate whose named files intersect the
diff wins. When two intersect, or none do, name the candidates and ask the author which applies.
Matching is a fact and therefore your job; choosing between two real candidates is a decision and
therefore theirs.

**Status is human-owned.** `active` / `shipped` / `abandoned` is the one fact git cannot derive,
so no check maintains it. A file still marked `active` months after its branch merged is stale
intent, and the author is the only one who can say which.

### File shape

```markdown
---
slug: <kebab-slug, matches the filename>
status: active
created: {{ISO date}}
sources:            # optional; pointers plus a seen marker, never content (ADR-0002)
  - kind: figma     # or lark
    ref: <file key/node id, or doc token>
    seen: <marker last reviewed; written only by /spec and /test-cases>
---

# <feature title>

## Spec
_(owned by /spec)_

## Task Plan
_(owned by /plan)_

## Decisions
_(pointers appended by /adr; paths are ../adr/NNNN-title.md)_
```

Test cases live beside it in `docs/planning/<slug>.tests.md` (see `test-cases-resolve`).

Commit this file early on the feature branch. Left uncommitted it follows you onto every other
branch, which is the two-candidate case above and the thing this layout exists to avoid.
