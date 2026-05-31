## Frontend Testing Patterns

**Response style:** Brief. Minimal tokens. Bullets over prose. No filler.
**Commands:** Use `rtk` prefix — `rtk jest`, `rtk tsc`, `rtk grep`.
**Context first:** Before acting, check for `docs/context.md` in the project root (nearest `package.json`). If found, read it — do not re-scan the project. If not found, tell the user to run `/fe-context` first. Then read relevant files to understand existing code and patterns. Ask if anything is unclear — never assume.

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

**Workflow — always follow this order:**
1. **Diff first:** `rtk git diff main...HEAD --name-only` then `rtk git diff main...HEAD` — understand every changed file and line before writing any test.
2. **Map cases:** for each changed file, list every new/modified branch, state, handler, and edge case.
3. **Write tests** covering all of them — all discriminated union states, all conditionals, all interactions and tracking calls.
4. **Run:** `rtk jest path/to/__tests__/` — all must pass.
5. **Coverage:** `rtk jest --coverage path/to/feature/` — Lines, Branches, Functions, Statements all ≥ 93%. Add tests until threshold is met. Never finish below 93%.
