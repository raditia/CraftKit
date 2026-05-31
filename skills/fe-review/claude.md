**Token mode:** caveman. Min tokens, max signal. Bullets > prose. No filler.
**Commands:** always prefix with `rtk` — `rtk ls .`, `rtk grep "pattern" .`, `rtk git status`, `rtk tsc`, `rtk jest`

---

**Context first:** Read the relevant files, understand the existing code and patterns, confirm what's being asked. Ask if anything is unclear — never assume.

---

## Load project context

Before doing anything else:
1. Find the project root — walk up from CWD to the nearest directory containing `package.json`
2. Check if `docs/context.md` exists there
3. **If found:** read it — use it as your understanding of what's being worked on. Skip re-scanning the project.
4. **If not found:** stop and tell the user: "No context found. Run `/fe-context` first to generate `docs/context.md`."

---

Review the specified file(s) or the current diff for correctness and adherence to this project's frontend patterns. Read the actual files before commenting — do not assume.

---

## What to check

### Architecture (Entry/View/Presenter/Model/Resource)

- [ ] **View** — does it call `usePresenter*()` and render only? Flag any `useState`, `useEffect`, or API calls in View files.
- [ ] **Presenter** — does it return a plain object? Flag any JSX or `return <...>` in Presenter hooks.
- [ ] **Model** — only types and pure functions? Flag any React imports or side effects.
- [ ] **Entry** — wraps in `<ErrorBoundary>` from `react-error-boundary`?
- [ ] **Resource** — are all display strings defined here rather than hardcoded in View?

### Styling

- [ ] No inline styles (`style={{ ... }}`)
- [ ] All styles defined in `StyleSheet.create()` at the bottom of the file
- [ ] Only `Token.spacing.*`, `Token.color.*`, `Token.border.*` used for design values — no magic numbers
- [ ] No CSS modules, no styled-components, no Tailwind

### TypeScript

- [ ] No `any` types (explicit or implicit)
- [ ] Async/remote data shaped as discriminated unions (`NOT_ASKED | LOADING | DATA_READY | ERROR`)
- [ ] All component props typed as `type Props = { ... }` above the component
- [ ] No missing return type annotations on exported functions (strict mode)

### State & data fetching

- [ ] Server state managed via React Query — no hand-rolled fetch in useEffect
- [ ] No unnecessary re-renders: stable references via `useCallback`/`useMemo` where appropriate
- [ ] Redux used only for genuinely shared cross-component state (not local UI state)

### Performance

- [ ] `dynamic()` import used for heavy components not needed on initial render
- [ ] Lists use stable `key` props (not array index unless list is static)
- [ ] No anonymous object/function creation inside JSX props that would break memo

### Tracking

- [ ] User interactions tracked via `useTracker()` from `@traveloka/core`
- [ ] Tracking calls include the correct event category, action, and payload

### Tests

- [ ] Each feature module has a `__tests__/` folder
- [ ] External hooks mocked with `jest.mock('@traveloka/...')`
- [ ] Uses `renderComponent` from `@traveloka/core/test`, not bare `render`

---

## Output format

For each issue found:
```
[SEVERITY] File:line — description
  Why it matters: ...
  Fix: ...
```

Severity: `ERROR` (breaks pattern/types), `WARNING` (deviation from convention), `SUGGESTION` (improvement opportunity).

At the end, list any patterns you observed that aren't covered by this skill as **Suggested skill updates**.
