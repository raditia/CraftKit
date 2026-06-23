---
name: fe-test
description: Write or improve tests covering all changed code paths. Enforces 93% coverage minimum.
alwaysApply: false
---

**Commands:** `rtk tsc`, `rtk lint`, `rtk grep "pattern" .`
**Tests:** `rtk test --testPathPattern=<path> --no-coverage` (run from workspace root)
**Model:** everyday — escalate to `claude-opus-4-8` if coverage cannot reach 93% and root cause is non-obvious

> Triggered by: "write tests", "add tests", "test this", "coverage is low", "improve coverage", "I need tests for X", "test coverage is failing", "missing tests"

---

> **Core behaviors:** Surface assumptions about what needs testing. Never skip verification — tests must pass and coverage must be ≥ 93% before done. See `/using-agent-skills`.

---

**Context:** `docs/context.md` — read: Summary, Test Coverage Needed. Standard load procedure in `/using-agent-skills`.

---

## Testing conventions

### File location
`__tests__/[FileName].test.tsx` inside the feature folder.

### Render helper
Use project-level render wrapper — never bare `render`. Check for existing helper before creating one.

### Mocking shared package hooks
Mock all hooks from shared packages. Fluent tracker chaining (`track(...).send(...)`) requires `send` on the inner mock return — mismatch causes `TypeError`:
```ts
useTracker: jest.fn(() => jest.fn(() => ({ send: jest.fn() }))),
```

### Network mocking
Use MSW for fetch/React Query flows. Set `onUnhandledRequest: 'error'` — silent passes mask missing mocks.

---

## Query priority

| Priority | Query | Use when |
|----------|-------|----------|
| 1 | `getByRole('button', { name: /save/i })` | Interactive elements |
| 2 | `getByLabelText('Email')` | Form inputs with labels |
| 3 | `getByPlaceholderText('Search')` | Inputs without visible labels |
| 4 | `getByText('Submit')` | Non-interactive text |
| 5 | `getByTestId('submit-btn')` | Last resort |

- `getBy*` — throws if not found
- `queryBy*` — returns `null` (assert absence)
- `findBy*` — async Promise (elements appearing after async work)

---

## What to cover per file type

**View components:**
- All discriminated union states: `NOT_ASKED`, `LOADING`, `DATA_READY`, `ERROR`
- User interactions (press, type, scroll)
- Tracker calls (`toHaveBeenCalledWith`)
- Mock the Presenter hook to control output

**Presenter hooks** (`renderHook` from `@testing-library/react-hooks`):
- State transitions (initial → after action) — wrap in `act`
- API call arguments, error handling branches
- Test via public API only — not internal state

**Model:** pure unit tests — no rendering.

### Async assertions
```ts
expect(await screen.findByText('Loaded')).toBeInTheDocument();
await waitFor(() => expect(saveSpy).toHaveBeenCalled());
await waitForElementToBeRemoved(() => screen.queryByText('Loading'));
```
Never `setTimeout` + assertion — flaky.

---

## Workflow

### 1. Diff first
```bash
rtk git diff main...HEAD --name-only
rtk git diff main...HEAD
```

### 2. Map cases (max 3 bullets per changed file — not exhaustive)
For each **changed file only**: list the new/modified branches and states that need coverage. Stop at 3; additional cases emerge from coverage report. Do not map or touch files not in the diff.

### 3. Write all tests
Cover every code path from the diff — **changed files only**. Write all test files before running.

### 4. Run — all must pass
```bash
rtk test --testPathPattern="path/to/__tests__/FileName" --no-coverage
```
Fix failures — never skip or comment out.

### 5. Coverage — must be ≥ 93% on changed files only
```bash
rtk test --testPathPattern="path/to/feature" --coverage --collectCoverageFrom="<changed-files-glob>"
```
Scope coverage to **only the files modified in the diff** — not the whole feature folder. Lines, Branches, Functions, Statements all ≥ 93% on those files. Add tests for uncovered lines from the report, then re-run once. Do NOT write tests for files not in the diff.

### 6. ESLint
```bash
rtk lint path/to/__tests__/FileName.test.tsx
```
Fix all errors. No `// eslint-disable` without documented reason.

If `rtk lint <file>` fails with `JSON parse failed: EOF` (wrapper choked), fall back to `pnpm exec oxlint <file>`.

### 7. Done
Report: tests added, pass/fail count, final coverage numbers per metric.
List testing patterns not covered above as **Suggested skill updates**.
