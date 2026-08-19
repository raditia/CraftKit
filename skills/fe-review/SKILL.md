---
name: fe-review
description: Review code for correctness, pattern adherence, code quality, and ESLint compliance.
alwaysApply: false
---

**Commands:** `rtk lint`, `rtk tsc`, `rtk git diff`, `rtk grep "pattern" .`
**Model:** everyday — escalate if review surfaces architectural conflicts with non-obvious resolution

---

> **Core behaviors:** Read actual files before commenting — never assume. Push back when you find real issues — not sycophancy. Surface every violation even if inconvenient. See `/using-agent-skills`.

---

**Context:** `docs/context.md` — read: Summary, Key Changes, Architecture Patterns in Use, Conflicts/Ambiguities. Standard load procedure in `/using-agent-skills`.

---

> Styling, React correctness, and state/data-fetching rules enforced by `fe-rules` (always active) — not repeated here.

## What to check

### Architecture (Entry/View/Presenter/Model/Resource)

- [ ] **View** — calls `usePresenter*()` and renders only? Flag `useState`, `useEffect`, or API calls.
- [ ] **Presenter** — returns a plain object? Flag any JSX or `return <...>`.
- [ ] **Model** — types and pure functions only? Flag React imports or side effects.
- [ ] **Entry** — wraps in `<ErrorBoundary>` from `react-error-boundary`?
- [ ] **Resource** — all display strings here, not hardcoded in View?

### TypeScript

- [ ] No `any` types (explicit or implicit)
- [ ] Async data as discriminated unions (`NOT_ASKED | LOADING | DATA_READY | ERROR`)
- [ ] Props typed as `type Props = { ... }` above component
- [ ] No missing return types on exported functions (strict mode)

### Performance

- [ ] `dynamic()` import for heavy components not needed on initial render
- [ ] Stable `key` props on dynamic lists (not array index)
- [ ] No anonymous object/function in JSX props that breaks memo

### Tracking

- [ ] User interactions tracked via `useTracker()` from your project's tracking package
- [ ] Tracking calls in Presenter handlers, not in View
- [ ] Tracking calls include correct event category, action, payload

### Tests

- [ ] `__tests__/` folder exists for each feature module
- [ ] External hooks from shared packages mocked with `jest.mock(...)`
- [ ] Uses project render wrapper (not bare `render`) — see `/fe-test`

### Code quality

- [ ] Single responsibility — each function/component does one job
- [ ] View JSX return > ~80 lines without `UI*` sub-component extraction
- [ ] Presenter hook > ~100 lines without sub-hook splitting
- [ ] No nested ternaries more than one level deep
- [ ] No cryptic abbreviations or unclear names
- [ ] No abstractions (helpers, HOCs) that are only used once

### ESLint

- [ ] `rtk lint path/to/file.tsx` on every file in the diff — zero errors
- [ ] No `// eslint-disable` without a documented reason in the same comment

---

## Output format

For each issue:
```
[SEVERITY] File:line — description
  Why: ...
  Fix: ...
```

`ERROR` = breaks pattern/types | `WARNING` = convention deviation | `SUGGESTION` = improvement opportunity

Push back on real issues — do not soften findings for comfort. At the end, list patterns observed not covered by any skill as **Suggested skill updates**.
