---
name: ios-a11y
description: Accessibility patterns for UIKit-based iOS screens within the MVVM-C architecture. Covers VoiceOver labels/traits/hints, focus & announcements, Dynamic Type, and reduce motion. Use when building any interactive screen or control.
alwaysApply: false
---

**Commands:** `grep -rn "accessibility" Modules/<Module>`, `swiftlint lint --path <file>`
**Model:** cheapest — `claude-haiku-4-5`. Escalate to everyday for complex focus flows spanning multiple screens.

---

> **Core behaviors:** Accessibility is applied in the View/VC, but the *strings and derived state* come from the ViewModel (via `NSLocalizedString`) — never hardcode labels in the view. See `/using-agent-skills` and `/ios-patterns`.

---

**Context:** No `docs/context.md` required. Read the changed `…View.swift` / `…ViewController.swift` and, if unclear, a sibling that already handles VoiceOver.

---

## MVVM-C mapping

| Layer | Responsibility |
|-------|---------------|
| **ViewModel** | Computes accessible text/state (label, value, hint) from `NSLocalizedString` + domain state; pushes via `action?.setX(...)`. Fires announcements after async work. |
| **ViewController** | Applies accessibility props onto the view when repainting. Manages focus on screen appear. |
| **View** | Sets static `accessibilityTraits`, groups decorative subviews. No dynamic label derivation. |

Never build a label string inside the View — it belongs to the VM (so it uses `NSLocalizedString` and reflects state).

---

## Core UIKit accessibility API

```swift
button.isAccessibilityElement = true
button.accessibilityLabel = viewModelPushedLabel        // from VM, via NSLocalizedString
button.accessibilityHint  = viewModelPushedHint
button.accessibilityTraits = .button                    // .header, .link, .selected, .notEnabled, .adjustable
button.accessibilityValue = "\(currentCount)"           // for steppers/sliders/adjustable
```

Traits combine: `[.button, .selected]`. Use `.notEnabled` (not just a dimmed style) so VoiceOver announces disabled state.

### Grouping & decorative elements

```swift
// Combine a stack into one focusable element with one label
containerStack.isAccessibilityElement = true
containerStack.accessibilityLabel = "\(name), \(memberTier)"   // strings from VM

// Hide decorative icon
decorativeIcon.isAccessibilityElement = false
```

### Focus management (screen transitions / modals)

```swift
// In VC, after the screen/modal appears — move VoiceOver focus
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
}
```
Use `.screenChanged` for full-screen transitions, `.layoutChanged` for in-place content updates.

### Dynamic announcements

```swift
// VC implements the Action callback; VM decides WHEN to announce (after async success/failure)
func announceResult(_ message: String) {
    UIAccessibility.post(notification: .announcement, argument: message)
}
```
The VM calls `action?.announceResult(NSLocalizedString("<module>.<screen>.a11y.loaded", comment: ""))` — announce on state change, not on every repaint.

### Dynamic Type

```swift
label.font = UIFont.preferredFont(forTextStyle: .body)
label.adjustsFontForContentSizeCategory = true
```
Prefer text styles over fixed point sizes so text scales. If the design system provides scalable fonts, use those.

### Reduce motion

```swift
// VM (or a shared helper) reads the setting; VC skips/simplifies the animation
if UIAccessibility.isReduceMotionEnabled {
    view.alpha = 1  // set final state directly, no animation
} else {
    UIView.animate(withDuration: 0.3) { view.alpha = 1 }
}
```

---

## Anti-patterns

```swift
// BAD: icon-only button with no label — VoiceOver says "button"
let b = UIButton(); b.setImage(trashIcon, for: .normal)   // no accessibilityLabel

// BAD: label hardcoded in the View instead of NSLocalizedString from VM
button.accessibilityLabel = "Delete item"

// BAD: disabled shown only via dim style — VoiceOver still says "button", enabled
button.alpha = 0.4    // missing .notEnabled trait

// BAD: announcing on every repaint
func setTitleText(_ t: String) { UIAccessibility.post(notification: .announcement, argument: t) }

// BAD: fixed font size — ignores Dynamic Type
label.font = UIFont.systemFont(ofSize: 14)
```

---

## Checklist

- [ ] Every interactive control has an `accessibilityLabel` (string from VM via `NSLocalizedString`) + correct `accessibilityTraits`
- [ ] Disabled controls set `.notEnabled` (not just a dim style)
- [ ] Selected/expanded state reflected in traits (`.selected`) or `accessibilityValue`
- [ ] Decorative subviews set `isAccessibilityElement = false`; related text grouped into one element
- [ ] Screen transition posts `.screenChanged`; in-place update posts `.layoutChanged`
- [ ] State-change announcements fired by the VM after async work — not on every repaint
- [ ] Text uses `preferredFont(forTextStyle:)` + `adjustsFontForContentSizeCategory = true`
- [ ] Animations gated on `UIAccessibility.isReduceMotionEnabled`
- [ ] No accessibility label strings hardcoded in the View/VC

List patterns observed not covered above as **Suggested skill updates**.
