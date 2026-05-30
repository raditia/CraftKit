RESPONSE STYLE: Brief. Minimal tokens. Bullets over prose. No filler sentences. Direct only.
COMMANDS: Always use rtk prefix — rtk jest, rtk tsc, rtk ls, rtk grep.
CONTEXT FIRST: Before making any changes, read the relevant files to understand existing code and patterns. Ask if anything is unclear — never assume.

When writing tests for this project:

FILE LOCATION: __tests__/[ComponentName].test.tsx inside the feature folder.

RENDER HELPER: Always use renderComponent from @traveloka/core/test, never bare render from @testing-library/react.

MOCKING: Mock all @traveloka/* hooks with jest.mock() at the top of the test file. Set return values in beforeEach(). Never let external hooks call real implementations.

Example mock pattern:
jest.mock('@traveloka/core', () => ({ useContentResource: jest.fn(), useTracker: jest.fn(() => jest.fn()) }));

COVERAGE per file type:
- View components: test loading/error/data states, user interactions via fireEvent, tracker calls. Mock the Presenter hook.
- Presenter hooks: use renderHook, test state transitions and API arguments.
- Model reducers/selectors: pure unit tests, no rendering.

QUERYING: Use getByTestId/queryByTestId. Add testID props to interactive and key elements in Views.

ASSERTIONS: Use @testing-library/jest-dom matchers (toBeInTheDocument, not.toBeInTheDocument). Check tracker calls with toHaveBeenCalledWith.
