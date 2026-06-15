---
name: ponytail-audit
description: Whole-repository over-engineering scan. Ranks what to delete, simplify, or replace with stdlib/native. Read-only — generates report, applies no changes.
alwaysApply: false
---

**Commands:** `rtk grep "pattern" .`, `find . -name "*.ts" -not -path "*/node_modules/*"`
**Model:** everyday

> Diff-scoped review: use `/ponytail-review` instead. This skill scans the full repo.

---

## Trigger

User says: "audit the whole repo for bloat", "find over-engineering everywhere", "what should we delete across the codebase", or invokes `/ponytail-audit`.

---

## Scan targets

Hunt for:
- Unnecessary dependencies (`package.json` — anything with a native/stdlib equivalent)
- Single-implementation interfaces or abstract classes
- Delegating wrappers that add no value
- One-off exports used in exactly one place
- Dead configuration (flags, env vars, feature toggles never read)
- Hand-rolled duplicates of standard library functions

Exclude: `node_modules/`, `.git/`, build output dirs.

---

## Finding tags

Same as `/ponytail-review`:

| Tag | Meaning |
|-----|---------|
| `delete:` | Unused code / dead flexibility |
| `stdlib:` | Hand-rolled stdlib duplicate |
| `native:` | Dep replicating platform capability |
| `yagni:` | Single-impl abstraction or single-caller layer |
| `shrink:` | Logic expressible in fewer lines |

---

## Output format

Ranked by impact (most lines saved first):

```
<tag> <item>. <replacement>. [path]
```

End with:
```
summary: ~<N> lines removable, <M> deps removable
```

---

## Boundaries

Report only — no edits. Correctness, security, performance belong in `/code-quality`. Never flag `ponytail:` marked shortcuts.
