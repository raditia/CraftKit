---
name: code-quality
description: Two-mode skill — review code for correctness/arch/security/performance, or simplify complex-but-working code. Rules applied from rules/ automatically.
alwaysApply: false
---

**Commands:** `rtk lint`, `rtk tsc`, `rtk git diff`, `rtk jest`, `rtk grep "pattern" .`
**Model:** everyday — escalate for security-sensitive changes, architecture decisions with significant tradeoffs, or refactors > 500 lines

**Context:** `docs/context.md` — read: Summary, Key Changes, Architecture Patterns in Use. Standard load procedure in `using-agent-skills`.

> For day-to-day reviews use the `/review` command — it runs this + fe-review automatically.

---

## Mode detection

Determine which mode applies from the request:

| Request | Mode |
|---------|------|
| "review this", "check the code", "is this correct?", "LGTM?" | **Review** |
| "this is too complex", "simplify this", "hard to read", "refactor for clarity" | **Simplify** |
| Both concerns present | Run Review first, then Simplify on flagged areas |

---

## Review mode

> "Approve a change when it definitely improves overall code health, even if it isn't perfect."

### Five axes

**1. Correctness**
- Matches spec/task requirements?
- Edge cases handled (null, empty, boundary values)?
- Error paths handled — not just the happy path?
- Off-by-one errors, race conditions, state inconsistencies?

**2. Readability**
- Names descriptive and consistent with project conventions?
- Control flow straightforward? No nested ternaries (> 1 level deep)?
- Abstractions earning their complexity?
- Dead code present? (no-op variables, backwards-compat shims)

**3. Architecture (EVPMR)**
- **View** — only calls `usePresenter*()` and renders? Flag `useState`, `useEffect`, API calls
- **Presenter** — returns plain object? Flag any JSX
- **Model** — types and pure functions only? Flag React imports or side effects
- **Entry** — wraps in `<ErrorBoundary>`?
- **Resource** — all display strings here, not hardcoded in View?
- No circular dependencies?

**4. Security**
- User input validated and sanitized?
- No secrets in code, logs, or version control?
- Auth/authorization checked where needed?
- No `dangerouslySetInnerHTML` without sanitization?
- No string concatenation in queries or shell commands?

**5. Performance**
- N+1 query patterns?
- Sequential awaits where `Promise.all` would do?
- Missing stable refs (`useCallback`/`useMemo`) for re-renders that matter?
- No dynamic imports missing for heavy components?
- Stable `key` props on lists?

### Change sizing

```
~100 lines  → Good. Reviewable in one sitting.
~300 lines  → Acceptable for a single logical change.
~1000 lines → Too large — ask to split.
```

One change = one self-contained modification. Separate refactoring from feature work.

### Dependency discipline

Before adding any dependency: Does the existing stack solve this? Bundle impact? Actively maintained? Known vulnerabilities (`npm audit`)? License compatible?

> Every dependency is a liability.

### Output

```
[ERROR]      File:line — description (blocks merge)
[WARNING]    File:line — description (should fix)
[SUGGESTION] File:line — description (optional)
  Why: ...
  Fix: ...
```

End with:
```
REVIEW SUMMARY
Errors:      N
Warnings:    N
Suggestions: N
Verdict: APPROVE / REQUEST CHANGES
```

### Honesty
- Don't rubber-stamp. "LGTM" without evidence helps no one.
- Quantify problems with evidence — specific beats general.
- Accept override gracefully when author has full context and disagrees.

---

## Simplify mode

> "Not fewer lines — code easier to read, understand, modify, and debug."

### When to use
- Feature works and tests pass, but implementation feels heavier than needed
- Code review flagged readability or complexity issues
- Deeply nested logic, long functions, or unclear names

### When NOT to use
- Code is already clean
- You don't fully understand it yet — read first
- Module is about to be rewritten entirely

### Process

**Step 1 — Understand before touching (Chesterton's Fence)**
```
BEFORE SIMPLIFYING:
- What is this code's responsibility?
- What calls it? What does it call?
- What are the edge cases and error paths?
- Why might it have been written this way?
  rtk git log -p -- path/to/file
```

**Step 2 — Identify opportunities**

| Pattern | Fix |
|---------|-----|
| Deep nesting (3+ levels) | Guard clauses or helper functions |
| Long functions (50+ lines) | Split into focused functions |
| Nested ternaries (> 1 level) | if/else chains or lookup objects |
| Generic names (`data`, `result`, `item`) | Rename to content: `userProfile`, `validationErrors` |
| Duplicated logic (5+ lines in multiple places) | Extract to shared function |
| Dead code | Remove after confirming |
| View JSX > ~80 lines | Extract `UI[Name][Section].tsx` sub-component |
| Presenter hook > ~100 lines | Split to `usePresenter[Name]Data` + `usePresenter[Name]Handlers` |
| Hardcoded strings in View | Move to `Resource[Name].ts` |
| Magic numbers in StyleSheet | Replace with `Token.spacing.*` / `Token.color.*` |

**Step 3 — Apply incrementally**

One simplification at a time:
```bash
rtk test --testPathPattern="path/to/__tests__" --no-coverage
rtk tsc --noEmit
```
If tests fail → revert and reconsider. Never batch multiple simplifications untested.

**Rule of 500:** If refactor touches > 500 lines → escalate.

**Never mix simplification with feature work.**

**Step 4 — Verify**
- Genuinely easier to understand?
- No behavior change?
- Diff is clean — no unrelated changes?

### Red flags
- Tests require modification to pass → behavior was changed
- "Simplified" version is longer or harder to follow
- Removing error handling because "it makes the code cleaner"

---

## Verification (both modes)

- [ ] `rtk test --testPathPattern=<changed-path> --no-coverage` — all pass (simplify: without modification)
- [ ] `rtk tsc --noEmit` — zero errors
- [ ] `rtk lint` — zero errors
- [ ] No unrelated changes mixed in
