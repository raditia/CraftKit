---
name: ponytail-review
description: Over-engineering audit for a diff or file. Finds what to delete — reinvented stdlib, speculative abstractions, dead flexibility. Outputs one finding per line with net line reduction estimate.
alwaysApply: false
---

**Commands:** `rtk git diff`, `rtk grep "pattern" .`
**Model:** cheapest — `claude-haiku-4-5` (Claude), `gemini-2.5-flash` (Gemini), `gpt-4o-mini` (Copilot/Cursor). No escalation — task is pattern matching on diff, not architecture judgment.

> Correctness bugs, security issues, performance: use `/code-quality` instead. This skill targets complexity only.

---

## Trigger

User says: "review for over-engineering", "what can we delete", "is this over-engineered", "simplify review", or invokes `/ponytail-review`.

---

## Process

1. Read the diff or file(s) specified.
2. Apply the decision ladder from `karpathy-guidelines` rule 2 — flag anything that fails an earlier rung.
3. Output one finding per line.
4. End with net line estimate.

---

## Finding tags

| Tag | Meaning |
|-----|---------|
| `delete:` | Dead code or unused flexibility — no replacement needed |
| `stdlib:` | Hand-rolled logic the standard library already provides |
| `native:` | Dependency doing what the platform natively offers |
| `yagni:` | Abstraction with single implementation or single-caller layer |
| `shrink:` | Same logic achievable in fewer lines |

---

## Output format

```
<file>:L<line>: <tag> <what>. <replacement or "remove">.
```

End with:
```
net: -<N> lines possible
```

If nothing to cut: `Lean already. Ship.`

---

## Boundaries

Never flag:
- Input validation at trust boundaries
- Error handling that prevents data loss
- Security or accessibility code
- `ponytail:` marked shortcuts (already acknowledged)
- Smoke tests / basic assertions
