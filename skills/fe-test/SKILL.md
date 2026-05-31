---
name: fe-test
description: Write or improve tests covering all changed code paths. Enforces 93% coverage minimum.
alwaysApply: false
---

**Commands:** `rtk jest`, `rtk tsc`, `rtk lint`, `rtk grep "pattern" .`
**Model:** everyday — escalate if coverage cannot reach 93% and root cause is non-obvious

---

> **Core behaviors:** Surface assumptions about what needs testing. Never skip verification — tests must pass and coverage must be ≥ 93% before done. See `/using-agent-skills`.

---

## Load project context

1. Find project root — nearest `package.json` going up from CWD
2. If `docs/context.md` missing → auto-run `/fe-context` steps first
3. **Selective include:** read only `Summary`, `Key Changes`, `Test Coverage Needed`
4. If context conflicts with what you observe:
   ```
   CONFUSION: docs/context.md says X but code shows Y.
   Options: A) ... B) ... → Which?
   ```
5. Never invent test cases not grounded in the actual diff or context — ask instead

---

## Testing conventions

### File location
`__tests__/[FileName].test.tsx` inside the feature folder.

### Render helper (React Native)
Always use `renderComponent` from `@traveloka/core/test` — never bare `render`:
```ts
import { renderComponent } from '@traveloka/core/test';
```

### Provider wrapper (Next.js / web)
For web components needing React Query, router, or theme context — wrap once in a helper:
```ts
import { render, RenderOptions } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';

export function renderWithProviders(ui: React.ReactElement, options?: RenderOptions) {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>{ui}</QueryClientProvider>,
    options,
  );
}
```
Create `queryClient` outside the wrapper closure — creating it inside resets cache on every render and causes flaky tests.

### Mocking `@traveloka/*` hooks
```ts
jest.mock('@traveloka/core', () => ({
  useContentResource: jest.fn(),
  useTracker: jest.fn(() => jest.fn()),
  useRouter: jest.fn(),
}));

beforeEach(() => {
  (useContentResource as jest.Mock).mockReturnValue({
    [FeatureName]: { headerTitle: 'Title' },
  });
});
```
Never let `@traveloka/*` hooks call real implementations in tests.

### Network mocking with MSW
For tests that exercise real fetch/React Query flows (web):
```ts
import { setupServer } from 'msw/node';
import { http, HttpResponse } from 'msw';

const server = setupServer(
  http.get('/api/routes', () => HttpResponse.json({ routes: [] })),
);

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

// Per-test override
server.use(http.get('/api/routes', () => new HttpResponse(null, { status: 500 })));
```
`onUnhandledRequest: 'error'` — any unmocked request fails loudly. Silent passes are worse than red.

---

## Query priority

Prefer queries in this order — top = most accessible, bottom = escape hatch:

| Priority | Query | Use when |
|----------|-------|----------|
| 1 | `getByRole('button', { name: /save/i })` | Interactive elements |
| 2 | `getByLabelText('Email')` | Form inputs with labels |
| 3 | `getByPlaceholderText('Search')` | Inputs without visible labels |
| 4 | `getByText('Submit')` | Non-interactive text |
| 5 | `getByTestId('submit-btn')` | Last resort — when no semantic query fits |

Use `testID` (React Native) / `data-testid` (web) sparingly. Prefer role/label — tests that pass role queries also verify accessibility.

Query variants:
- `getBy*` — throws if not found (use for expected elements)
- `queryBy*` — returns `null` (use to assert absence)
- `findBy*` — async Promise (use for elements appearing after async work)

---

## User interactions

**React Native** — `fireEvent` from `@testing-library/react-native`:
```ts
import { fireEvent } from '@testing-library/react-native';
fireEvent.press(getByTestId('search-button'));
fireEvent.changeText(getByTestId('origin-input'), 'CGK');
```

**Web** — prefer `userEvent` (simulates real browser event sequence):
```ts
import userEvent from '@testing-library/user-event';
const user = userEvent.setup();
await user.type(screen.getByLabelText('Email'), 'test@example.com');
await user.click(screen.getByRole('button', { name: /save/i }));
```
Always `await` userEvent calls. Call `userEvent.setup()` once per test.

---

## What to cover per file type

**View components:**
- All discriminated union states: `NOT_ASKED`, `LOADING`, `DATA_READY`, `ERROR`
- User interactions (press, type, scroll)
- Tracker calls (`toHaveBeenCalledWith`)
- Mock the Presenter hook to control output

**Presenter hooks:**
- `renderHook` from `@testing-library/react-hooks`
- State transitions (initial → after action)
- API call arguments
- Error handling branches

**Model (reducers/selectors):**
- Pure unit tests — no rendering

### Async assertions
```ts
// Element that appears after async work
expect(await screen.findByText('Loaded')).toBeInTheDocument();

// Side effect
await waitFor(() => expect(saveSpy).toHaveBeenCalled());

// Element that disappears
await waitForElementToBeRemoved(() => screen.queryByText('Loading'));
```
Never `setTimeout` + assertion — flaky.

### Assertion style
```ts
expect(getByRole('button', { name: /submit/i })).toBeInTheDocument();
expect(queryByTestId('error-banner')).not.toBeInTheDocument();
expect(mockTrack).toHaveBeenCalledWith('BUS_SEARCH', 'SUBMIT', expect.objectContaining({ origin: 'CGK' }));
```

---

## Accessibility assertions

Run `axe` on every interactive component:
```ts
import { axe, toHaveNoViolations } from 'jest-axe';
expect.extend(toHaveNoViolations);

test('UserCard has no a11y violations', async () => {
  const { container } = renderWithProviders(<UserCard user={mockUser} />);
  expect(await axe(container)).toHaveNoViolations();
});
```
Catches: missing labels, invalid ARIA, missing alt text, heading order violations.

---

## Presenter hook testing
```ts
import { renderHook, act } from '@testing-library/react-hooks';

test('search state transitions', () => {
  const { result } = renderHook(() => usePresenterBusSearch());
  expect(result.current.searchState.type).toBe('NOT_ASKED');

  act(() => result.current.handleSearch({ origin: 'CGK', dest: 'DPS' }));
  expect(result.current.searchState.type).toBe('LOADING');
});
```
- Wrap state-changing calls in `act`
- Test via the hook's public API only — not internal state
- Pass providers via `wrapper` option when hook needs context

---

## TDD workflow

```
RED     → write a failing test for the next requirement
GREEN   → write minimal code to pass
REFACTOR → improve code, tests stay green
REPEAT  → next requirement
```

For new components:
1. Define prop types and hook signature
2. Write the simplest test case
3. Verify it fails for the right reason
4. Implement just enough to pass
5. Add the next case

---

## Workflow

### 1. Diff first
```bash
rtk git log --oneline main...HEAD
rtk git diff main...HEAD --name-only
rtk git diff main...HEAD
```
Detect base branch: `git remote show origin | grep 'HEAD branch'`

### 2. Map cases
For every changed file: list every new/modified branch, state transition, handler, and edge case. Note what's covered vs. missing.

### 3. Write tests
Cover every code path from the diff:
- All discriminated union states
- Every `if/else`, ternary, optional chaining fallback
- All user interactions and tracking calls
- Error boundaries and error states

### 4. Run — all must pass
```bash
rtk jest path/to/__tests__/FileName.test.tsx
```
Fix failures — never skip or comment out.

### 5. Coverage — must be ≥ 93%
```bash
rtk jest --coverage path/to/feature/
```
Lines, Branches, Functions, Statements all ≥ 93%. Add tests until threshold is met.

### 6. ESLint
```bash
rtk lint path/to/__tests__/FileName.test.tsx
```
Fix all errors. No `// eslint-disable` without a documented reason.

### 7. Done
Report: tests added, pass/fail count, final coverage numbers per metric.
List testing patterns encountered not covered above as **Suggested skill updates**.

---

## Anti-patterns

- `container.querySelector('...')` — bypasses accessible queries, hides real user failures
- `jest.mock('react', ...)` — never mock React; refactor the component instead
- Asserting on render count — implementation detail
- Snapshot tests of DOM output — break on every style change, rubber-stamped in review
- Ignoring `act()` warnings — they signal real bugs
- Mutable state shared across tests — flakes when order changes
