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
  accessible={true}               // makes element a single focusable unit
  accessibilityLabel="Submit"     // what screen reader announces (from Resource)
  accessibilityHint="Saves your changes and returns to the list"
  accessibilityRole="button"      // announces element type to screen reader
  accessibilityState={{ disabled: isLoading, selected: isActive }}
  onPress={onPress}
/>
```

### accessibilityRole values

| RN Role | Use for |
|---------|---------|
| `button` | `Pressable`, `TouchableOpacity` acting as buttons |
| `link` | Navigation elements |
| `text` | Plain text elements |
| `header` | Section headings |
| `image` | `Image` components |
| `checkbox` / `radio` | Toggle inputs |
| `combobox` | Dropdown/picker |
| `tab` | Tab bar items |
| `none` | Decorative elements to hide from screen reader |

### accessibilityState

```tsx
// Communicates interactive state without visual reliance
accessibilityState={{
  disabled: !isValid,
  selected: isSelected,
  checked: isChecked,       // for checkboxes
  expanded: isOpen,         // for accordions/dropdowns
  busy: isLoading,          // for loading indicators
}}
```

### Grouping elements

```tsx
// BAD: screen reader reads each child separately
<View>
  <Text>John Doe</Text>
  <Text>Premium member</Text>
</View>

// GOOD: grouped into a single focusable unit with one announcement
<View accessible={true} accessibilityLabel="John Doe, Premium member">
  <Text>John Doe</Text>
  <Text>Premium member</Text>
</View>
```

### Hiding decorative elements

```tsx
// Decorative icon alongside a labelled button — hide from screen reader
<Pressable accessibilityLabel={Resource.deleteLabel} accessibilityRole="button" onPress={onDelete}>
  <Icon name="trash" importantForAccessibility="no-hide-descendants" />
  <Text>{Resource.deleteLabel}</Text>
</Pressable>
```

---

## TextInput accessibility

```tsx
// BAD: no label, no error link
<TextInput placeholder="Email" value={email} onChangeText={setEmail} />

// GOOD: label announced, error state and hint communicated
<TextInput
  accessibilityLabel={Resource.emailLabel}
  accessibilityHint={Resource.emailHint}
  accessibilityState={{ disabled: isSubmitting }}
  // when error present, Presenter combines label + error into accessibilityLabel:
  // e.g. "Email, Invalid email address"
  value={email}
  onChangeText={onEmailChange}
  autoComplete="email"
  keyboardType="email-address"
  textContentType="emailAddress"
/>
```

Combine error into `accessibilityLabel` from Presenter — RN has no `aria-describedby`:

```ts
// PresenterFeatureName.ts
const emailAccessibilityLabel = emailError
  ? `${Resource.emailLabel}, ${emailError}`
  : Resource.emailLabel;
```

---

## Focus management

Use when UI transitions require explicit focus control (modals, screen changes, alert dialogs).

```ts
// PresenterFeatureName.ts
import { AccessibilityInfo, findNodeHandle } from 'react-native';

// Call from Presenter after modal opens
const focusOnOpen = (ref: React.RefObject<View>) => {
  const node = findNodeHandle(ref.current);
  if (node) AccessibilityInfo.setAccessibilityFocus(node);
};
```

```tsx
// ViewFeatureName.tsx — pass ref from Presenter
<View ref={modalRef} accessible={true} accessibilityViewIsModal={true}>
  ...
</View>
```

`accessibilityViewIsModal={true}` prevents screen readers from reading content outside the modal.

---

## Dynamic content announcements

For content that updates without a navigation event (success banners, inline errors, loading state):

```ts
// PresenterFeatureName.ts
import { AccessibilityInfo } from 'react-native';

// After async action completes
const announceResult = (message: string) => {
  AccessibilityInfo.announceForAccessibility(message);
};
```

Use sparingly — only for state changes the user cannot see (background completion, async errors). Do not announce every render.

---

## Reduced motion

```ts
// PresenterFeatureName.ts
import { AccessibilityInfo } from 'react-native';
import { useEffect, useState } from 'react';

// In Presenter hook — returns to View as plain value
const [reduceMotion, setReduceMotion] = useState(false);
useEffect(() => {
  AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion);
  const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
  return () => sub.remove();
}, []);
```

```tsx
// ViewFeatureName.tsx
<Animated.View style={{ opacity: reduceMotion ? 1 : animatedOpacity }}>
  {children}
</Animated.View>
```

---

## Next.js / web (when building web screens)

Use native HTML semantics first. ARIA only when native is insufficient.

```tsx
// Forms — always connect label to input
<label htmlFor="email">{Resource.emailLabel}</label>
<input
  id="email"
  type="email"
  aria-describedby={emailError ? 'email-error' : undefined}
  aria-invalid={!!emailError}
/>
{emailError && <span id="email-error" role="alert">{emailError}</span>}
```

```tsx
// Interactive elements — use semantic elements
<button type="button" onClick={onPress}>{Resource.label}</button>  // not <div onClick>
<a href="/path">{Resource.navLabel}</a>                            // not <div onClick> for nav
```

```tsx
// Dynamic content
<div role="status" aria-live="polite" aria-atomic="true">{statusMessage}</div>
<div role="alert" aria-live="assertive">{errorMessage}</div>  // urgent errors only
```

Heading hierarchy must be sequential (h1 → h2 → h3). Never skip levels.

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
