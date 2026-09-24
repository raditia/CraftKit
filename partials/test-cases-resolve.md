---
name: test-cases-resolve
description: How a skill finds the active feature's test cases and which of them count as requirements. Shared by every test-case consumer; spliced in at sync time, never loaded always-on.
---

## Reading the feature's test cases

Test cases live in `docs/planning/<slug>.tests.md`, beside the intent file and keyed by the same
slug. Use the slug your caller passed, or the one `planning-resolve` gives. Never open another
slug's `.tests.md`: that is how one feature's requirements leak into another's build.

No file, or no rows → there are no test cases for this feature. Proceed exactly as you would
without them, and say so in one line.

### File shape

```markdown
---
feature: <slug>
---

# Test cases: <feature title>

| ID | Title | Steps | Expected | Source | Status | Automation |
|----|-------|-------|----------|--------|--------|------------|
| TC-001 | … | 1. … <br> 2. … | … | figma:<node> · lark:<doc>#<section> · inferred | draft | jest |
```

The file is a table so that no line starts with `status:`, which is what keeps it out of the
intent resolver's glob. It has no `status:` frontmatter for the same reason.

| Field | Values |
|---|---|
| **Status** | `draft` · `approved` · `rejected` · `needs-review`. Set by a human, in the repo |
| **Automation** | `jest` (RN/web) · `junit` (Android) · `quick` (iOS) · `manual` |
| **Source** | The pointer and section the case came from, or `inferred` when none backs it |

### What counts as a requirement

| Status | Treat it as |
|---|---|
| `approved` | A requirement. Build to it, test it, score against it |
| `draft`, `needs-review` | Unverified. List it by ID, never build or test to it |
| `rejected` | Ignore |

- **Read only the cases your task maps to.** A `/plan` task row names its TC IDs; read those rows.
  With no mapping, read the approved rows only.
- **Only `/test-cases` writes this file.** Consumers read it; they never add a row or change a
  status. A case that looks wrong is reported to the author, not edited.
- **Test cases come from their sources, never from the diff or the code.** A case rewritten to
  match what was built confirms the implementation instead of the requirement, and every test
  then passes for the wrong reason.
