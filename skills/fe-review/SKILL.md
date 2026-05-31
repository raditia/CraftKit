---
name: fe-review
description: Review code for correctness, pattern adherence, code quality, and ESLint compliance.
alwaysApply: false
---

**Token mode:** caveman. Min tokens, max signal. Bullets > prose. No filler.
**Commands:** always prefix with `rtk` — `rtk lint`, `rtk tsc`, `rtk git diff`, `rtk grep "pattern" .`

---

> **Core behaviors:** Read actual files before commenting — never assume. Push back when you find real issues — not sycophancy. Surface every violation even if inconvenient. See `/using-agent-skills`.

---

## Load project context

1. Find project root — nearest `package.json` going up from CWD
2. If `docs/context.md` missing → auto-run `/fe-context` steps first
3. **Selective include:** read only `Summary`, `Key Changes`, `Architecture Patterns in Use`, `Conflicts/Ambiguities`
4. If context conflicts with what you observe:
   ```
   CONFUSION: docs/context.md says X but code shows Y.
   Options: A) ... B) ... → Which takes precedence?
   ```

---

## What to check

### Architecture (Entry/View/Presenter/Model/Resource)

- [ ] **View** — calls `usePresenter*()` and renders only? Flag `useState`, `useEffect`, or API calls.
- [ ] **Presenter** — returns a plain object? Flag any JSX or `return <...>`.
- [ ] **Model** — types and pure functions only? Flag React imports or side effects.
- [ ] **Entry** — wraps in `<ErrorBoundary>` from `react-error-boundary`?
- [ ] **Resource** — all display strings here, not hardcoded in View?

### Styling

- [ ] No inline styles (`style={{ ... }}`)
- [ ] All styles in `StyleSheet.create()` at bottom of file
- [ ] Only `Token.spacing.*`, `Token.color.*`, `Token.border.*` — no magic numbers
- [ ] No CSS modules, no styled-components, no Tailwind

### TypeScript

- [ ] No `any` types (explicit or implicit)
- [ ] Async data as discriminated unions (`NOT_ASKED | LOADING | DATA_READY | ERROR`)
- [ ] Props typed as `type Props = { ... }` above component
- [ ] No missing return types on exported functions (strict mode)

### State & data fetching

- [ ] Server state via React Query — no hand-rolled fetch in `useEffect`
- [ ] Stable references via `useCallback`/`useMemo` where re-renders matter
- [ ] Redux only for genuinely shared cross-component state

### Performance

- [ ] `dynamic()` import for heavy components not needed on initial render
- [ ] Stable `key` props on dynamic lists (not array index)
- [ ] No anonymous object/function in JSX props that breaks memo

### Tracking

- [ ] User interactions tracked via `useTracker()` from `@traveloka/core`
- [ ] Tracking calls include correct event category, action, payload

### Tests

- [ ] `__tests__/` folder exists for each feature module
- [ ] External hooks mocked with `jest.mock('@traveloka/...')`
- [ ] Uses `renderComponent` from `@traveloka/core/test`, not bare `render`

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
