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
4. If context conflicts with what you observe in the code:
   ```
   CONFUSION: docs/context.md says X but code shows Y.
   Options: A) ... B) ... → Which?
   ```
5. Never invent test cases not grounded in the actual diff or context — ask instead

---

## Testing conventions

### File location
`__tests__/[FileName].test.tsx` inside the feature folder.

### Render helper
Always use `renderComponent` from `@traveloka/core/test` — never bare `render`:
```ts
import { renderComponent } from '@traveloka/core/test';
```

### Mocking external hooks
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

### What to cover per file type

**View components:**
- All discriminated union states (`NOT_ASKED`, `LOADING`, `DATA_READY`, `ERROR`)
- User interactions (`fireEvent.press()` / `fireEvent.click()`)
- Tracker calls (`toHaveBeenCalledWith`)
- Mock the Presenter hook to control output

**Presenter hooks:**
- `renderHook` from `@testing-library/react-hooks`
- State transitions (initial → after action)
- API call arguments
- Error handling branches

**Model (reducers/selectors):**
- Pure unit tests — no rendering

### Query elements
`getByTestId` / `queryByTestId` — add `testID` to key elements in View components.

### Assertion style
```ts
expect(getByTestId('submit-button')).toBeInTheDocument();
expect(queryByTestId('error-banner')).not.toBeInTheDocument();
expect(mockTrack).toHaveBeenCalledWith('BUS_SEARCH', 'SUBMIT', expect.objectContaining({ origin: 'CGK' }));
```

---

## Workflow

### 1. Diff first
```bash
rtk git log --oneline main...HEAD
rtk git diff main...HEAD --name-only
rtk git diff main...HEAD
```
Detect base branch if not `main`: `git remote show origin | grep 'HEAD branch'`

### 2. Map cases
For every changed file: list every new/modified branch, state transition, handler, and edge case. Note what's already covered vs. missing.

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
Lines, Branches, Functions, Statements all ≥ 93%. Add tests until threshold is met. Never finish below 93%.

### 6. ESLint
```bash
rtk lint path/to/__tests__/FileName.test.tsx
```
Fix all errors. No `// eslint-disable` without a documented reason.

### 7. Done
Report: tests added, pass/fail count, final coverage numbers per metric.
List testing patterns encountered not covered above as **Suggested skill updates**.
