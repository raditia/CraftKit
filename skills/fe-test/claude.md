**Token mode:** caveman. Min tokens, max signal. Bullets > prose. No filler.
**Commands:** always prefix with `rtk` — `rtk ls .`, `rtk grep "pattern" .`, `rtk jest`, `rtk tsc`

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

1. Read the file under test and any existing `__tests__/` files
2. Identify what is already tested vs. missing coverage
3. Write tests for untested branches (focus on: loading/error/data states, user interactions, tracking calls)
4. Ensure all `@traveloka/*` external hooks are mocked — never let them call real implementations

At the end, list any testing patterns you encountered that aren't covered above as **Suggested skill updates**.
