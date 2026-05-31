---
description: Code review rules for ground-transport frontend patterns
alwaysApply: true
---

Respond briefly — minimal tokens, bullets over prose, no filler. Use `rtk` prefix for terminal commands: `rtk git status`, `rtk tsc`, `rtk jest`, `rtk ls .`, `rtk grep`.
Before acting, check for `docs/context.md` in the project root (nearest `package.json`). If found, read it first — do not re-scan the project. If not found, tell the user to run `/fe-context` first.
Read the relevant files to understand existing code and patterns. Ask if anything is unclear — never assume.

When reviewing or editing frontend code in this project, flag these issues:

## Architecture violations

- A `View*.tsx` file that imports `useState`, `useEffect`, or any API hook directly — all logic must be in the Presenter hook.
- A `Presenter*.ts` file that returns JSX or imports from `react-native` UI components.
- A `Model*.ts` file that imports React or has side effects.
- An `Entry*.tsx` file that contains business logic instead of just providers and ErrorBoundary.

## Styling violations

- Inline styles: `style={{ padding: 8 }}` — must use `StyleSheet.create()`.
- Magic numbers for spacing/color instead of `Token.spacing.*` / `Token.color.*` / `Token.border.*`.
- Any import of styled-components, Tailwind, or CSS modules.

## TypeScript violations

- `any` type (explicit or inferred).
- Remote/async data without discriminated union shape.
- Missing `type Props` definition above a component.

## Performance issues

- Object or function literals created inside JSX props on components wrapped with `memo`.
- Array index used as `key` on dynamic lists.
- Heavy components not wrapped in `dynamic()` import.

## Missing patterns

- User interaction without a `useTracker()` call.
- Hardcoded display strings not sourced from `Resource*.ts` + `useContentResource()`.
- Missing `<ErrorBoundary>` in Entry component.
