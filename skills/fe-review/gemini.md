## Frontend Review Checklist

**Response style:** Brief. Minimal tokens. Bullets over prose. No filler.
**Commands:** Use `rtk` prefix — `rtk ls .`, `rtk grep`, `rtk git status`, `rtk tsc`, `rtk jest`.
**Context first:** Read relevant files and understand existing code and patterns before acting. Ask if anything is unclear — never assume.

When reviewing frontend code in this project, check for these violations:

**Architecture (Entry/View/Presenter/Model/Resource)**
- View files must not contain useState, useEffect, or API hooks — violations belong in Presenter
- Presenter hooks must return a plain object, never JSX
- Model files must be pure TypeScript with no React imports or side effects
- Entry files must wrap children in ErrorBoundary from react-error-boundary

**Styling**
- No inline styles — use StyleSheet.create() from react-native
- No magic numbers for spacing/color — use Token.spacing.*, Token.color.*, Token.border.* from @traveloka/web-components
- No styled-components, Tailwind, or CSS modules

**TypeScript**
- No `any` types
- Async/remote data must use discriminated unions: NOT_ASKED | LOADING | DATA_READY | ERROR
- Component props must be typed as `type Props = {}` above the function

**Performance**
- No anonymous objects/functions as props on memoized components
- No array index as key on dynamic lists
- Heavy components should use Next.js dynamic() import

**Missing patterns**
- User interactions without useTracker() calls
- Display strings hardcoded in View instead of sourced from Resource + useContentResource()
