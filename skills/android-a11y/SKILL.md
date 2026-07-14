---
name: android-a11y
description: Accessibility patterns for Android (Views + Data Binding and Jetpack Compose) within the MVP + Core-framework architecture. Covers TalkBack labels, roles/state, touch targets, focus order, live regions, and text scaling. Use when building any interactive screen or control.
alwaysApply: false
---

**Commands:** `grep -rn "contentDescription\|semantics" <feature>/src`, `./gradlew :<module>:lintGeneralDebug`
**Model:** cheapest — `claude-haiku-4-5`. Escalate to everyday for complex focus flows spanning multiple screens.

---

> **Core behaviors:** Accessibility is applied in the View, but the *label strings and derived state* come from the Presenter/ViewModel (via `R.string`) — never hardcode labels in the layout. See `/using-agent-skills` and `/android-patterns`.

---

**Context:** No `docs/context.md` required. Read the changed layout/View/Composable and, if unclear, a sibling that already handles TalkBack.

---

## MVP mapping

| Layer | Responsibility |
|-------|---------------|
| **Presenter** | Computes accessible text/state from `R.string` + domain state; writes to the ViewModel. |
| **ViewModel** | Exposes the a11y label/state as `@Bindable` (or in the Compose state). |
| **View** | Binds `contentDescription`/semantics from the VM; sets static roles; groups decorative views. |

Never build a label string in the layout XML or Composable — it belongs upstream (so it uses `R.string` and reflects state).

---

## Android Views

```xml
<ImageButton
    android:id="@+id/deleteButton"
    android:contentDescription="@{viewModel.deleteLabel}"   <!-- from Presenter via R.string -->
    android:minWidth="48dp" android:minHeight="48dp" />      <!-- touch target ≥ 48dp -->
```

```kotlin
// State/role that TalkBack must announce — set via AccessibilityDelegate or view APIs
ViewCompat.setAccessibilityDelegate(button, object : AccessibilityDelegateCompat() {
    override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfoCompat) {
        super.onInitializeAccessibilityNodeInfo(host, info)
        info.roleDescription = context.getString(R.string.role_button)
        info.isEnabled = viewModel.isEnabled            // announce disabled, not just dim
    }
})
```

- **Decorative image:** `android:importantForAccessibility="no"` (or `contentDescription="@null"`).
- **Group related text** into one focusable node: `android:focusable="true"` + a combined `contentDescription` on the container, children `importantForAccessibility="no"`.
- **Live region** for content that updates in place: `android:accessibilityLiveRegion="polite"` (or `assertive` for urgent).
- **Focus on transition:** `view.sendAccessibilityEvent(AccessibilityEvent.TYPE_VIEW_FOCUSED)` after the new screen/section appears.
- **Text scaling:** use `sp` for text sizes; don't disable font scaling. Ensure layouts reflow.

## Jetpack Compose

```kotlin
IconButton(
    onClick = onDelete,
    modifier = Modifier.semantics {
        contentDescription = deleteLabel      // from state, sourced from stringResource
        role = Role.Button
    },
)

// Merge a group into one node
Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "$name, $tier" }) { ... }

// Decorative
Icon(painterResource(R.drawable.ic_star), contentDescription = null)

// Live announcement after async work (from the state layer, not every recomposition)
LaunchedEffect(loadedKey) { view.announceForAccessibility(loadedMessage) }

// State
Modifier.semantics { stateDescription = if (selected) "Selected" else "Not selected" }
```

Minimum touch target in Compose: `Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp)` (or `minimumInteractiveComponentSize()`).

---

## Anti-patterns

```xml
<!-- BAD: icon button with no contentDescription — TalkBack says "button" -->
<ImageButton android:src="@drawable/ic_trash" />

<!-- BAD: label hardcoded in layout instead of R.string via VM -->
<ImageButton android:contentDescription="Delete item" />

<!-- BAD: touch target smaller than 48dp -->
<ImageButton android:layout_width="24dp" android:layout_height="24dp" />
```
```kotlin
// BAD: announcing on every recomposition (no key)
view.announceForAccessibility(message)   // called in composition body

// BAD: fixed dp for text — ignores user font scale
fontSize = 14.dp   // use sp
```

---

## Checklist

- [ ] Every interactive control has a `contentDescription`/`semantics.contentDescription` (string from Presenter via `R.string`) + correct role
- [ ] Disabled/selected/expanded state exposed to TalkBack (node info / `stateDescription`), not shown by style alone
- [ ] Touch targets ≥ 48dp
- [ ] Decorative images set `importantForAccessibility="no"` / `contentDescription = null`; related text grouped into one node
- [ ] In-place updates use a live region; screen transitions move accessibility focus
- [ ] Announcements fired after async work with a key — not on every recomposition/repaint
- [ ] Text uses `sp`; font scaling not disabled; layout reflows
- [ ] No accessibility label strings hardcoded in layout XML / Composable

List patterns observed not covered above as **Suggested skill updates**.
