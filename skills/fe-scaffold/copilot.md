RESPONSE STYLE: Brief. Minimal tokens. Bullets over prose. No filler sentences. Direct only.
COMMANDS: Always use rtk prefix — rtk git status, rtk tsc, rtk jest, rtk ls, rtk grep.
CONTEXT FIRST: Before making any changes, check for docs/context.md in the project root (nearest package.json). If found, read it — do not re-scan the project. If not found, automatically run the fe-context steps to generate docs/context.md, then proceed. Then read the relevant files to understand existing code and patterns. Ask if anything is unclear — never assume.

When generating new frontend feature code for this project:

ARCHITECTURE — Always use the Entry/View/Presenter/Model/Resource pattern:
- Entry[Name].tsx: ErrorBoundary wrapper + context providers. Nothing else.
- View[Name].tsx: Pure presentational. Calls usePresenter[Name]() hook, no other state or effects.
- Presenter[Name].ts: All useState, useEffect, useCallback, React Query hooks, event handlers. Returns a plain object.
- Model[Name].ts: TypeScript types and pure reducer/selector functions. No React imports.
- Resource[Name].ts: Content resource keys as empty string defaults for i18n.

STYLING — Always use React Native StyleSheet:
- import { StyleSheet, View, Text } from 'react-native'
- Define const styles = StyleSheet.create({}) at the bottom of the file.
- Use Token.spacing.*, Token.color.*, Token.border.* from @traveloka/web-components.
- Never use inline styles. Never use CSS modules or styled-components.

TYPESCRIPT — strict mode is enforced:
- No `any` types.
- Use discriminated unions for async states: { type: 'NOT_ASKED' | 'LOADING' | 'DATA_READY' | 'ERROR' }.
- Type component props as `type Props = { ... }` above the component.

TRACKING — add useTracker() from @traveloka/core for user interaction events.
