---
name: code-review
description: Five-axis code review — correctness, readability, architecture, security, performance. Use before any merge. Complements fe-review for frontend pattern specifics.
alwaysApply: false
---

**Commands:** `rtk lint`, `rtk tsc`, `rtk git diff`, `rtk grep "pattern" .`

---

> **Core behaviors:** Read actual files before commenting — never assume. Push back on real issues — not sycophancy. Surface every violation even if inconvenient. See `/using-agent-skills`.

---

## Load project context

1. Find project root — nearest `package.json` going up from CWD
2. If `docs/context.md` missing → auto-run `/fe-context` steps first
3. **Selective include:** read only `Summary`, `Key Changes`, `Architecture Patterns in Use`, `Conflicts/Ambiguities`
4. If context conflicts with observed code:
   ```
   CONFUSION: docs/context.md says X but code shows Y.
   Options: A) ... B) ... → Which takes precedence?
   ```

---

## Approval standard

> "Approve a change when it definitely improves overall code health, even if it isn't perfect."

Perfect is the enemy of shipped. Review for real issues — not personal preference.

---

## Five-axis review

### 1. Correctness
- Matches spec/task requirements?
- Edge cases handled (null, empty, boundary values)?
- Error paths handled — not just the happy path?
- Tests actually testing the right things, not just passing?
- Off-by-one errors, race conditions, state inconsistencies?

### 2. Readability & Simplicity
- Names descriptive and consistent with project conventions?
- Control flow straightforward? No nested ternaries (> 1 level deep)?
- Related code grouped logically?
- Abstractions earning their complexity?
- Dead code present? (no-op variables, backwards-compat shims, removed comments)
- If significant simplification opportunities exist → run `/code-simplify`

### 3. Architecture (EVPMR)
- **View** — only calls `usePresenter*()` and renders? Flag `useState`, `useEffect`, API calls
- **Presenter** — returns plain object? Flag any JSX or `return <...>`
- **Model** — types and pure functions only? Flag React imports or side effects
- **Entry** — wraps in `<ErrorBoundary>` from `react-error-boundary`?
- **Resource** — all display strings here, not hardcoded in View?
- New pattern introduced — is it justified?
- No circular dependencies?
- Run `/fe-review` for the complete frontend pattern checklist

### 4. Security
- User input validated and sanitized?
- No secrets in code, logs, or version control?
- Auth/authorization checked where needed?
- No `dangerouslySetInnerHTML` without sanitization?
- External data (API responses, URL params) treated as untrusted?
- No string concatenation in queries or shell commands?
- Dependencies from trusted sources with no known vulnerabilities?

### 5. Performance
- N+1 query patterns?
- Unbounded loops or unconstrained data fetching?
- Missing `useCallback`/`useMemo` for stable references where re-renders matter?
- Anonymous objects/functions in JSX props that break memo?
- `dynamic()` import missing for heavy components not needed on initial render?
- Stable `key` props on lists — not array index?
- Large objects created in hot paths?

---

## Change sizing

```
~100 lines   → Good. Reviewable in one sitting.
~300 lines   → Acceptable for a single logical change.
~1000 lines  → Too large — ask to split.
```

**One change = one self-contained modification addressing one thing.** Separate refactoring from feature work — always.

### Splitting strategies

| Strategy | When |
|----------|------|
| Stack | Sequential dependencies — submit small, base next on it |
| By file group | Cross-cutting concerns needing different reviewers |
| Horizontal | Shared code/stubs first, then consumers |
| Vertical | Smaller full-stack slices of a feature |

---

## Severity labels

Label every comment so authors know what's required vs. optional:

| Prefix | Required? | Meaning |
|--------|-----------|---------|
| *(none)* | Yes | Must address before merge |
| **Critical:** | Yes | Blocks merge — security, data loss, broken functionality |
| **Nit:** | No | Minor style preference — author may ignore |
| **Optional:** / **Consider:** | No | Worth considering but not required |
| **FYI** | No | Informational only — no action needed |

---

## Output format

For each issue:
```
[SEVERITY] File:line — description
  Why: ...
  Fix: ...
```

`ERROR` = blocks merge | `WARNING` = convention deviation | `SUGGESTION` = improvement opportunity

---

## Dead code hygiene

After any refactoring, scan for orphaned code:

```
DEAD CODE IDENTIFIED:
- formatLegacyDate() in utils/date.ts — replaced by formatDate()
- OldTaskCard in components/ — replaced by TaskCard
- LEGACY_API_URL in config.ts — no remaining references
→ Safe to remove?
```

Don't silently delete. Identify, list, ask.

---

## Dependency discipline

Before adding any dependency:
1. Does the existing stack solve this? (Often yes.)
2. Bundle impact? (`rtk grep '"dependencies"' package.json`)
3. Actively maintained? (Last commit, open issues)
4. Known vulnerabilities? (`npm audit`)
5. License compatible?

> Every dependency is a liability. Prefer existing utilities over new ones.

---

## Review checklist

- [ ] **Context:** understand what this change does and why
- [ ] **Correctness:** spec matched, edge cases covered, error paths handled, tests adequate
- [ ] **Readability:** clear names, no nested ternaries > 1 level, no unnecessary complexity
- [ ] **Architecture:** run `/fe-review` for full EVPMR checklist
- [ ] **Security:** no secrets, input validated at boundaries, external data untrusted, auth checked
- [ ] **Performance:** no N+1, stable refs (useCallback/useMemo), no anon JSX props, stable list keys
- [ ] **Verification:** `rtk tsc --noEmit` | `rtk lint` | `rtk jest` — all pass
- [ ] **Verdict:** Approve / Request changes

---

## Honesty

- Don't rubber-stamp. "LGTM" without evidence helps no one.
- Don't soften real issues. Honest assessment beats diplomatic vagueness.
- Quantify problems with evidence — specific beats general.
- Push back on approaches with clear problems.
- Sycophancy is a review failure mode.
- Accept override gracefully when author has full context and disagrees.

---

## Anti-patterns

| Rationalization | Reality |
|---|---|
| "It works, that's good enough" | Working + unreadable creates compounding debt |
| "AI-generated code is probably fine" | AI code needs more scrutiny, not less — confident and plausible even when wrong |
| "Tests pass, so it's good" | Tests don't catch architecture, security, or readability problems |
| "I'll clean it up later" | Later never comes. The review is the quality gate — use it. |
| "PRs merged without review" | Every change gets reviewed. No exceptions. |

---

## After review

- [ ] All Critical/Important issues resolved or explicitly deferred with documented justification
- [ ] `rtk tsc --noEmit` passes
- [ ] `rtk lint` passes on all changed files
- [ ] Build succeeds

List patterns observed not covered by a skill as **Suggested skill updates**.
