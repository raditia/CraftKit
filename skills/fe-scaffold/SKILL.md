---
name: fe-scaffold
description: Scaffold a new frontend feature module following the Entry/View/Presenter/Model/Resource pattern.
alwaysApply: false
---

**Commands:** `rtk ls .`, `rtk grep "pattern" .`, `rtk git status`, `rtk tsc`, `rtk jest`
**Model:** cheapest — `claude-haiku-4-5` (Claude). Escalate to everyday if feature requires novel architecture not covered by EVPMR

---

> **Core behaviors:** Surface assumptions before generating. Enforce simplicity — split when complex, not speculatively. Verify with lint + tsc before claiming done. See `/using-agent-skills`.

---

**Context:** `docs/context.md` — read: Summary, Architecture Patterns in Use, Changed Files. Standard load procedure in `/using-agent-skills`. Never invent requirements not in context — ask instead.

---

## Step 1 — Understand context

State assumptions before generating:
```
ASSUMPTIONS I'M MAKING:
1. Feature name: [name]
2. Feature folder: [kebab-case-feature-name]
3. Platform: [mobile / desktop]
4. Target package: [path]
→ Correct me now or I'll proceed with these.
```

Read 1-2 existing feature folders in the same package to confirm exact naming and import style before writing anything.

---

## Step 2 — Create the 5-file module

All files in one folder: `[kebab-case-feature]/`
Naming: `[Role][ProductPrefix][Platform][FeatureName].[ext]`

### `Entry[Name].tsx`
- Wraps in `<ErrorBoundary>` from `react-error-boundary`
- Provides required React Contexts
- Renders `<View[Name] />` with no props

### `View[Name].tsx`
- Pure presentational — no `useState`, no `useEffect`, no direct API calls
- Calls `usePresenter[Name]()` at top, destructures everything from it
- Returns JSX using `react-native` primitives (`View`, `Text`, `TouchableOpacity`)
- All styles via `StyleSheet.create()` at bottom

### `Presenter[Name].ts`
- Single exported hook `usePresenter[Name]()`
- All `useState`, `useEffect`, `useCallback`, `useMemo`, React Query calls live here
- Returns a plain object — never JSX
- Tracking and navigation via handlers in the returned object

### `Model[Name].ts`
- TypeScript types only + pure reducer/selector functions
- Discriminated unions for async data:
  ```ts
  type AsyncData<T> =
    | { type: 'NOT_ASKED' }
    | { type: 'LOADING' }
    | { type: 'DATA_READY'; payload: T }
    | { type: 'ERROR'; error: string }
  ```

### `Resource[Name].ts`
- Content resource keys with empty string defaults
  ```ts
  export const resource[Name] = {
    contentResource: {
      [FeatureName]: { headerTitle: '', submitLabel: '' },
    },
  };
  ```

---

## Step 3 — Styling rules

- **Never** inline styles (`style={{ margin: 8 }}`)
- **Always** `StyleSheet.create()` at bottom of file
- **Always** design tokens from your project's token system (adapt paths to your setup):
  - Spacing: e.g. `Token.spacing.xs / s / m / l / xl`
  - Color: e.g. `Token.color.primary / secondary / neutral`
  - Border: e.g. `Token.border.radius.normal`
- Compose as arrays: `style={[styles.base, isActive && styles.active]}`

---

## Step 4 — TypeScript rules

- `strict: true` — no `any`, no implicit returns
- `type Props = { ... }` above each component
- `interface` for API shapes/props, `type` for unions

---

## Step 5 — Code quality

- **Single responsibility:** one job per function/component. If you need "and" — split it.
- **View length:** JSX return > ~80 lines → extract as `UI[Name][Section].tsx` in same folder
- **Presenter length:** hook > ~100 lines → split into `usePresenter[Name]Data`, `usePresenter[Name]Handlers`
- **No over-engineering:** only split when genuinely complex. No abstractions for single-use code.
- **Readable names:** full words. `isSubmitting` not `isSub`. `handleSearchPress` not `onPress1`.
- **No nested ternaries:** more than one level → extract to variable or `UI*` sub-component

---

## Step 6 — Tracking

```ts
const track = useTracker(); // from your project's tracking package
track('FEATURE_NAME', 'ACTION', { ...payload });
```

---

## After generating

- [ ] `rtk lint path/to/file.tsx` on every file created or modified — zero errors
- [ ] `rtk tsc --noEmit` — no TypeScript errors
- [ ] No `// eslint-disable` without a documented reason
- List each file created with path
- Note any naming/token assumptions made
- List any patterns observed not covered by a skill as **Suggested skill updates**
