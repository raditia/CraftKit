When reviewing or suggesting fixes for frontend code in this project, always check for these issues:

ARCHITECTURE: View files must not contain useState/useEffect/API calls — only the Presenter hook. Presenter hooks must return a plain object, not JSX. Model files must be pure TypeScript (no React imports). Entry files must wrap in ErrorBoundary.

STYLING: No inline styles. All styles in StyleSheet.create() using Token.spacing.*, Token.color.*, Token.border.* from @traveloka/web-components. No magic numbers for design values.

TYPESCRIPT: No `any` types. Async data must use discriminated unions (NOT_ASKED/LOADING/DATA_READY/ERROR). Props must be typed as `type Props = {}` above the component.

PERFORMANCE: Avoid anonymous functions/objects in JSX props on memoized components. Use stable keys (not array index) on dynamic lists. Use dynamic() for heavy components.

TRACKING: All user interactions must call useTracker() from @traveloka/core.

CONTENT: Display strings must come from Resource files and useContentResource() — not hardcoded.
