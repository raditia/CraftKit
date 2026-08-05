---
name: ponytail-review
description: Over-engineering audit for a diff or file. Finds what to delete — reinvented stdlib, speculative abstractions, dead flexibility. Outputs one finding per line with net line reduction estimate.
alwaysApply: false
---

**Commands:** `rtk git diff`, `rtk grep "pattern" .`
**Model:** cheapest tier (see the plan-aware Model routing table in `using-agent-skills`). No escalation — task is pattern matching on diff, not architecture judgment.

> Correctness bugs, security issues, performance: use `/code-quality` instead. This skill targets complexity only.

---

## Trigger

User says: "review for over-engineering", "what can we delete", "is this over-engineered", "simplify review", or invokes `/ponytail-review`.

---

## Process

1. Read the diff or file(s) specified.
2. Apply the decision ladder + **ponytail rubric** from `karpathy-guidelines` rule 2 — the six tags (`delete:` `stdlib:` `native:` `yagni:` `shrink:` `narrate:`) and the protected list live there, always active. Flag anything that fails an earlier rung.
3. Output one finding per line.
4. End with net line estimate.

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

Protected code is listed in the ponytail rubric (`karpathy-guidelines` rule 2) — never flag it.

Findings are applied as **deletion, not rewrite**: act on the named `file:line` only. A finding that appears to need a restructure gets said out loud and left alone.
