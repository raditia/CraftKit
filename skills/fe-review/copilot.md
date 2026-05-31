RESPONSE STYLE: Brief. Minimal tokens. Bullets over prose. No filler sentences. Direct only.
COMMANDS: Always use rtk prefix — rtk git status, rtk tsc, rtk jest, rtk ls, rtk grep.
CONTEXT FIRST: Before making any changes, check for docs/context.md in the project root (nearest package.json). If found, read it — do not re-scan the project. If not found, automatically run the fe-context steps to generate docs/context.md, then proceed. Then read the relevant files to understand existing code and patterns. Ask if anything is unclear — never assume.

When reviewing or suggesting fixes for frontend code in this project, always check for these issues:

ARCHITECTURE: View files must not contain useState/useEffect/API calls — only the Presenter hook. Presenter hooks must return a plain object, not JSX. Model files must be pure TypeScript (no React imports). Entry files must wrap in ErrorBoundary.

STYLING: No inline styles. All styles in StyleSheet.create() using Token.spacing.*, Token.color.*, Token.border.* from @traveloka/web-components. No magic numbers for design values.

TYPESCRIPT: No `any` types. Async data must use discriminated unions (NOT_ASKED/LOADING/DATA_READY/ERROR). Props must be typed as `type Props = {}` above the component.

PERFORMANCE: Avoid anonymous functions/objects in JSX props on memoized components. Use stable keys (not array index) on dynamic lists. Use dynamic() for heavy components.

TRACKING: All user interactions must call useTracker() from @traveloka/core.

CONTENT: Display strings must come from Resource files and useContentResource() — not hardcoded.

CODE QUALITY: Flag — function/component doing more than one job; View JSX return > ~80 lines without UI* sub-components; Presenter hook > ~100 lines without sub-hooks; nested ternaries more than one level deep; cryptic abbreviations; abstractions used in only one place.

ESLINT: Run `rtk lint path/to/file.tsx` on every file in the diff. Flag all ESLint errors. Flag any eslint-disable without a documented reason.
