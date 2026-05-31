---
name: review
description: Full code review workflow — orchestrates fe-context, code-review (5-axis), and fe-review (EVPMR). Use when reviewing any frontend change before merge.
alwaysApply: false
---

**Commands:** `rtk git diff`, `rtk tsc`, `rtk lint`
**Model:** everyday — escalate for security-sensitive changes or major architecture tradeoffs

> Triggered by: "help me review the changes", "review this", "code review", "review before merge", "LGTM check"

---

## How to run this workflow

Runs in two passes: general quality first, then EVPMR-specific. Report all findings together at the end.

---

## Step 1 — Context

1. Detect base branch: `rtk git remote show origin | grep 'HEAD branch'`
2. Run: `rtk git diff <base>...HEAD --name-only` then `rtk git diff <base>...HEAD`
3. Read `docs/context.md` if present (selective: Summary + Key Changes only)
4. If missing, run the fe-context workflow first

---

## Step 2 — General review (5-axis)

Review every changed file on these axes:

**Correctness**
- Logic is correct for all inputs, including edge cases
- No off-by-one, no missing null checks at system boundaries
- Async errors handled — no unhandled Promise rejections
- Side effects are intentional and reversible

**Readability**
- Names reveal intent — no abbreviations, no single-letter variables beyond loop indices
- Functions do one thing — if you can't name it simply, it does too much
- No comments explaining WHAT — only WHY (non-obvious constraints, workarounds)

**Architecture**
- No coupling between layers that shouldn't know about each other
- New abstractions earn their complexity — three similar lines beats a premature abstraction
- Dependencies flow in the right direction

**Security**
- No secrets, tokens, or PII in source or logs
- User input validated at system boundaries
- No SQL/command injection vectors
- Auth checks present on every protected route and Server Action

**Performance**
- No sequential awaits where `Promise.all` would do
- No `useEffect` + fetch for application data (use React Query)
- No inline style objects in React Native components
- No barrel imports for heavy packages

---

## Step 3 — EVPMR review

Check every changed file against these constraints:

**Architecture**
- [ ] View files: no `useState`, `useEffect`, or direct API calls
- [ ] Presenter files: no JSX returned
- [ ] Model files: no React imports, no side effects
- [ ] Entry files: `<ErrorBoundary>` wraps all content
- [ ] Resource files: only display strings — no logic

**Styling**
- [ ] No inline styles: `style={{ ... }}` is forbidden
- [ ] `StyleSheet.create()` at bottom of every RN component file
- [ ] Only `Token.spacing.*`, `Token.color.*`, `Token.border.*` — no magic numbers

**TypeScript**
- [ ] No `any` — use `unknown` + narrowing if type is genuinely unknown
- [ ] All exported functions have explicit return types
- [ ] `type Props = { ... }` above each component

**State**
- [ ] Single-Presenter state in `useState` inside that Presenter
- [ ] Multi-Presenter shared state lifted to Entry / Context — not Redux unless genuinely cross-feature
- [ ] Async data typed as discriminated unions (`NOT_ASKED | LOADING | DATA_READY | ERROR`)

**Tracking**
- [ ] `useTracker()` from `@traveloka/core` — no direct tracker calls
- [ ] All tracking calls in Presenter handlers, not in View

**Tests**
- [ ] New code paths have tests
- [ ] Coverage still ≥ 93% — run `rtk jest --coverage path/to/feature/` if unsure

---

## Step 4 — Report

Format every finding as:

```
[SEVERITY] File:line — description
Why it matters: ...
Fix: ...
```

Severity levels:
- `[ERROR]` — blocks merge; correctness, security, or hard EVPMR violation
- `[WARNING]` — should fix; readability, soft pattern violation, or test gap
- `[SUGGESTION]` — optional improvement

End with a summary:
```
REVIEW SUMMARY
Errors:      N  (must fix before merge)
Warnings:    N
Suggestions: N
```

If no findings: say so explicitly — "No issues found" is a valid outcome.
