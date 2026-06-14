---
name: fe-a11y
description: Accessibility patterns for React Native and Next.js within the EVPMR architecture. Covers accessible labels, roles, focus management, dynamic announcements, and reduced motion. Use when building any interactive component or form.
alwaysApply: false
---

**Context:** `docs/context.md` → Summary + Key Changes only
**Commands:** `rtk tsc`, `rtk lint`
**Model:** everyday — escalate for complex focus flows spanning multiple routes

---

# Frontend Accessibility (fe-a11y)

## When to activate

- Building or reviewing interactive components (forms, modals, dropdowns, tabs)
- Adding `Pressable`, `TouchableOpacity`, or `TextInput` without accessibility props
- Receiving a11y feedback from code review tools
- Implementing focus management on screen transitions
- Building components that announce state changes to screen readers

---

## EVPMR mapping

Accessibility is a cross-cutting concern — each layer has a specific responsibility:

| Layer | Responsibility |
|-------|---------------|
| **Presenter** | Computes accessible state: `accessibilityLabel`, `accessibilityState`, `isReduceMotionEnabled` result, focus ref |
| **View** | Applies a11y props from Presenter to elements — never derives them inline |
| **Model** | Types for a11y-related state (e.g. `{ disabled: boolean; selected: boolean }`) |
| **Entry** | Wraps with `<ErrorBoundary>` — no a11y responsibility |
| **Resource** | Owns all `accessibilityLabel` strings — never hardcode in View |

```ts
// PresenterFeatureName.ts — return a11y props as plain object
const accessibilityProps = {
  label: Resource.submitButton,          // string from Resource
  hint: Resource.submitButtonHint,
  role: 'button' as AccessibilityRole,
  state: { disabled: isLoading },
};
return { accessibilityProps, ... };
```

```tsx
// ViewFeatureName.tsx — apply from Presenter, no inline derivation
<Pressable
  accessibilityLabel={accessibilityProps.label}
  accessibilityHint={accessibilityProps.hint}
  accessibilityRole={accessibilityProps.role}
  accessibilityState={accessibilityProps.state}
  onPress={onSubmit}
/>
```

---

## React Native accessibility API

### Core props

```tsx
<Pressable
  accessible={true}
  accessibilityLabel={Resource.submitLabel}   // from Resource — never hardcode
  accessibilityHint={Resource.submitHint}
  accessibilityRole="button"
  accessibilityState={{ disabled: isLoading, selected: isActive }}
  onPress={onPress}
/>
```

`accessibilityRole` values: `button`, `link`, `text`, `header`, `image`, `checkbox`, `radio`, `combobox`, `tab`, `none` (decorative).

`accessibilityState` fields: `disabled`, `selected`, `checked`, `expanded`, `busy`.

### Grouping + decorative elements

```tsx
// Group related text into one focusable unit
<View accessible={true} accessibilityLabel="Jane Doe, Premium member">
  <Text>Jane Doe</Text><Text>Premium member</Text>
</View>

// Hide decorative icon from screen reader
<Icon name="trash" importantForAccessibility="no-hide-descendants" />
```

### TextInput

Combine error into `accessibilityLabel` from Presenter — RN has no `aria-describedby`:

```ts
// PresenterFeatureName.ts
const emailA11yLabel = emailError
  ? `${Resource.emailLabel}, ${emailError}`
  : Resource.emailLabel;
```

### Focus management (modals / screen transitions)

```ts
// PresenterFeatureName.ts — call after modal opens
import { AccessibilityInfo, findNodeHandle } from 'react-native';
const node = findNodeHandle(ref.current);
if (node) AccessibilityInfo.setAccessibilityFocus(node);
```

```tsx
// ViewFeatureName.tsx
<View ref={modalRef} accessible={true} accessibilityViewIsModal={true}>...</View>
```

### Dynamic announcements

```ts
// PresenterFeatureName.ts — after async action, NOT on every render
AccessibilityInfo.announceForAccessibility(Resource.successMessage);
```

### Reduced motion

```ts
// PresenterFeatureName.ts
const [reduceMotion, setReduceMotion] = useState(false);
useEffect(() => {
  AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion);
  const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
  return () => sub.remove();
}, []);
// Pass reduceMotion to View as plain value
```

---

## Next.js / web

Use native HTML semantics first. ARIA only when native is insufficient.

```tsx
// Forms — label must be explicit, not placeholder
<label htmlFor="email">{Resource.emailLabel}</label>
<input id="email" type="email"
  aria-describedby={emailError ? 'email-error' : undefined}
  aria-invalid={!!emailError} />
{emailError && <span id="email-error" role="alert">{emailError}</span>}

// Dynamic content
<div role="status" aria-live="polite">{statusMessage}</div>  // non-urgent
<div role="alert" aria-live="assertive">{errorMessage}</div> // urgent only
```

Heading hierarchy must be sequential (h1 → h2 → h3). Never skip levels. Use `<button>` not `<div onClick>`.

---

## Anti-patterns

```tsx
// BAD: Pressable with no label — screen reader says "button" with no context
<Pressable onPress={onDelete}><Icon name="trash" /></Pressable>

// BAD: accessibilityLabel hardcoded in View (belongs in Resource)
<Pressable accessibilityLabel="Delete item" />

// BAD: accessible={false} on an interactive element — keyboard/switch users can't reach it
<Pressable accessible={false} onPress={onPress} />

// BAD: state not communicated — user can't tell button is disabled
<Pressable style={isDisabled ? styles.dim : styles.normal} onPress={isDisabled ? undefined : onPress} />
// GOOD: accessibilityState={{ disabled: isDisabled }} + onPress={isDisabled ? undefined : onPress}

// BAD: announcing on every render
useEffect(() => { AccessibilityInfo.announceForAccessibility(message); });  // no deps

// WEB BAD: div with onClick and no role/keyboard support
<div onClick={handleClick}>Submit</div>
// WEB BAD: placeholder as label substitute
<input placeholder="Enter email" />  // label must exist separately
```

---

## Checklist

- [ ] Every `Pressable` / `TouchableOpacity` has `accessibilityLabel` (from Resource) and `accessibilityRole`
- [ ] `accessibilityState` communicates `disabled`, `selected`, `expanded`, `busy` where applicable
- [ ] `TextInput` errors prepended to `accessibilityLabel` in Presenter
- [ ] Decorative icons use `importantForAccessibility="no-hide-descendants"`
- [ ] Modal/dialog uses `accessibilityViewIsModal={true}` and focuses on open
- [ ] State changes announced via `AccessibilityInfo.announceForAccessibility` (not on every render)
- [ ] Animations respect `AccessibilityInfo.isReduceMotionEnabled()` — result computed in Presenter
- [ ] All `accessibilityLabel` strings live in Resource file — none hardcoded in View
- [ ] (Web) Every `<input>` has a `<label>` with matching `htmlFor`/`id`
- [ ] (Web) Error messages linked via `aria-describedby` with `role="alert"`
