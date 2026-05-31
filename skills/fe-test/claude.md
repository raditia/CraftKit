**Token mode:** caveman. Min tokens, max signal. Bullets > prose. No filler.
**Commands:** always prefix with `rtk` — `rtk ls .`, `rtk grep "pattern" .`, `rtk jest`, `rtk tsc`

---

**Context first:** Read the relevant files, understand the existing code and patterns, confirm what's being asked. Ask if anything is unclear — never assume.

---

## Load project context

Before doing anything else:
1. Find the project root — walk up from CWD to the nearest directory containing `package.json`
2. Check if `docs/context.md` exists there
3. **If not found:** automatically run the fe-context steps to generate it, then continue
4. **Selective include:** read only the sections relevant to testing — `Summary`, `Key Changes`, `Test Coverage Needed`. Do not load the entire file.
5. **Confusion management:** if context conflicts with what you observe in the code, surface it — never silently pick one interpretation:
   ```
   CONFUSION: docs/context.md says X but the code shows Y.
   Options: A) ... B) ... → Which should I follow?
   ```
6. Never invent test cases not grounded in the actual diff or context — ask instead

---

Write or improve tests for the specified component or hook. Read the target file and any existing tests in its `__tests__/` folder before generating anything.

---

## Testing conventions in this project

### File location
Tests live in `__tests__/` inside the feature folder, named `[FileName].test.tsx`.

### Render helper
Always use `renderComponent` from `@traveloka/core/test` — **never** bare `render` from `@testing-library/react`:
```ts
import { renderComponent } from '@traveloka/core/test';
```

### Mocking external hooks
Mock all `@traveloka/*` hooks at the module level before tests:
```ts
jest.mock('@traveloka/core', () => ({
  useContentResource: jest.fn(),
  useTracker: jest.fn(() => jest.fn()),
  useRouter: jest.fn(),
}));
```

Set mock return values in `beforeEach()`:
```ts
beforeEach(() => {
  (useContentResource as jest.Mock).mockReturnValue({
    BusSearch: { searchFormHeader: 'Search Bus' },
  });
});
```

### What to test

**View components:**
- Renders the correct UI given different Presenter outputs
- Handles loading, error, and data states (mock the Presenter hook)
- Fires the correct handler on user interaction (`fireEvent.press()` / `fireEvent.click()`)
- Key elements have `testID` / `data-testid` attributes for querying

**Presenter hooks:**
- Use `renderHook` from `@testing-library/react-hooks`
- Test state transitions (initial state → after action)
- Test that API calls are made with correct arguments
- Test error handling branches

**Model (reducer/selector):**
- Pure unit tests — no rendering needed
- Test each reducer action and each selector output

### Assertion style
```ts
expect(getByTestId('submit-button')).toBeInTheDocument();
expect(queryByTestId('error-banner')).not.toBeInTheDocument();
expect(mockTrack).toHaveBeenCalledWith('BUS_SEARCH', 'SUBMIT', expect.objectContaining({ origin: 'CGK' }));
```

### Test structure
```ts
describe('ViewBusMobileSearchForm', () => {
  beforeEach(() => { /* set up mocks */ });

  it('renders search header from content resource', () => { ... });
  it('shows loading indicator when status is LOADING', () => { ... });
  it('calls onSubmit handler when form is submitted', () => { ... });
  it('tracks search event on submit', () => { ... });
});
```

---

## Steps to follow

### 1. Understand what changed
Find the base branch and diff against it:
```bash
rtk git log --oneline main...HEAD        # commits on this branch
rtk git diff main...HEAD --name-only     # files changed
rtk git diff main...HEAD                 # full diff
```
If base branch is not `main`, detect it: `git remote show origin | grep 'HEAD branch'`.

### 2. Map changed code to test cases
For every changed file in the diff:
- Read the file and its `__tests__/` folder
- List every changed function, branch, state transition, and edge case introduced by the diff
- Note which cases are already covered and which are missing

### 3. Write tests for all uncovered cases
Cover every code path introduced or modified by the diff:
- All discriminated union states (`NOT_ASKED`, `LOADING`, `DATA_READY`, `ERROR`)
- Every conditional branch (`if/else`, ternary, optional chaining fallback)
- All user interactions and their side effects (handlers, tracking calls)
- Error boundaries and error states

### 4. Run tests and fix failures
```bash
rtk jest path/to/__tests__/FileName.test.tsx
```
All tests must pass before proceeding. Fix failures — do not skip or comment out.

### 5. Verify coverage ≥ 93%
```bash
rtk jest --coverage path/to/feature/
```
Check `Lines`, `Branches`, `Functions`, `Statements` — all must be ≥ 93%.
If below threshold, identify uncovered lines from the report and add missing test cases. Repeat until passing.

### 6. ESLint
Run `rtk lint path/to/__tests__/FileName.test.tsx` on every test file written or modified. Fix all errors before finishing. No `// eslint-disable` without a documented reason.

### 7. Done
Report: tests added, pass/fail count, final coverage numbers.
List any testing patterns you encountered not covered above as **Suggested skill updates**.
