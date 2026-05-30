## Frontend Testing Patterns

**File location:** `__tests__/[ComponentName].test.tsx` inside the feature folder.

**Render helper:** Always use `renderComponent` from `@traveloka/core/test`. Never use bare `render` from @testing-library/react.

**Mocking external hooks:**
```ts
jest.mock('@traveloka/core', () => ({
  useContentResource: jest.fn(),
  useTracker: jest.fn(() => jest.fn()),
  useRouter: jest.fn(),
}));

beforeEach(() => {
  (useContentResource as jest.Mock).mockReturnValue({ /* keys */ });
});
```
Never let @traveloka/* hooks run real implementations in tests.

**What to test by file type:**
- View components: loading/error/data states, user interactions (fireEvent), tracker calls. Mock the Presenter hook to control output.
- Presenter hooks: use renderHook from @testing-library/react-hooks, test state transitions and API call arguments.
- Model reducers/selectors: pure unit tests — no rendering needed.

**Querying:** Use getByTestId/queryByTestId. Ensure key UI elements have testID props.

**Assertions:** Use jest-dom matchers (toBeInTheDocument). Verify tracker calls with toHaveBeenCalledWith including event category, action, and payload shape.
