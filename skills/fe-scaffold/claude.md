**Token mode:** caveman. Min tokens, max signal. Bullets > prose. No filler.
**Commands:** always prefix with `rtk` — `rtk ls .`, `rtk grep "pattern" .`, `rtk git status`, `rtk tsc`, `rtk jest`

---

Scaffold a new frontend feature module. Before generating any code, read the codebase around the target location to confirm naming conventions, token usage, and existing patterns — then apply them exactly.

---

## Step 1 — Understand context

Ask for or infer:
- Feature name (e.g. `BusMobilePassengerForm`)
- Product prefix (bus → `gtrbus`, train → `gtrtrn`, rental → `gtrppr`, shuttle → `gtrpps`, etc.)
- Platform: `mobile` or `desktop`
- Target package (e.g. `gtrbus-mobile/mobile-passenger-form/`)

Read 1-2 existing feature folders in the same package to confirm exact naming and import style before writing anything.

---

## Step 2 — Create the 5-file module

All files live in one folder named `[kebab-case-feature]/`. File naming: `[Role][ProductPrefix][Platform][FeatureName].[ext]`.

### `Entry[Name].tsx`
- Wraps in `<ErrorBoundary>` from `react-error-boundary`
- Provides any required React Contexts
- Renders `<View[Name] />` with no props (all data flows through hooks inside View)

### `View[Name].tsx`
- Pure presentational — **no business logic, no direct API calls, no useState for server data**
- Calls `usePresenter[Name]()` at the top; destructures everything needed from it
- Returns JSX using `<View>`, `<Text>`, `<TouchableOpacity>`, etc. from `react-native`
- All styles via `StyleSheet.create()` at the bottom of the file using `Token.*` values

### `Presenter[Name].ts`
- Single exported hook `usePresenter[Name]()`
- All `useState`, `useEffect`, `useCallback`, `useMemo`, React Query calls live here
- Returns a plain object — never JSX
- Side effects (tracking, navigation) triggered via handlers returned in the object

### `Model[Name].ts`
- TypeScript types only — no runtime logic except pure reducer/selector functions
- Use discriminated unions for async data states:
  ```ts
  type AsyncData<T> =
    | { type: 'NOT_ASKED' }
    | { type: 'LOADING' }
    | { type: 'DATA_READY'; payload: T }
    | { type: 'ERROR'; error: string }
  ```
- Export reducer functions and selector functions (pure, no side effects)

### `Resource[Name].ts`
- Exports a `resource[Name]` const with `contentResource` keys (empty string values as placeholders)
- Keys mirror the i18n labels needed by the View
- Example:
  ```ts
  export const resourceBusMobilePassengerForm = {
    contentResource: {
      PassengerForm: {
        headerTitle: '',
        submitLabel: '',
      },
    },
  };
  ```

---

## Step 3 — Styling rules

- **Never** use inline styles (`style={{ margin: 8 }}`)
- **Always** use `StyleSheet.create()` — placed at the bottom of the file
- **Always** use design tokens from `@traveloka/web-components`:
  - `Token.spacing.xs / s / m / l / xl`
  - `Token.color.uiBluePrimary / uiLightPrimary / uiDarkNeutral / ...`
  - `Token.border.radius.normal`
- Compose styles as arrays: `style={[styles.base, isActive && styles.active]}`

---

## Step 4 — TypeScript rules

- `strict: true` is enforced — no `any`, no implicit returns
- Prefer `type` for unions/discriminated unions, `interface` for props and API shapes
- Type component props as a local `type Props = { ... }` above the component

---

## Step 5 — Tracking

If the feature has user interactions, add tracker calls using `useTracker()` from `@traveloka/core`:
```ts
const track = useTracker();
// in handler:
track('FEATURE_NAME', 'ACTION', { ...payload });
```

---

## After generating

- List each file created with its path
- Note any assumptions made about naming or token choices
- If you noticed patterns in the codebase not covered above, list them as **Suggested skill updates** at the end
