---
name: android-review
description: Review an Android feature diff against the MVP + Core-framework contract — layer violations, Dagger DI, NavigatorService navigation, string resources, coroutine/main-thread correctness, Android Lint compliance.
alwaysApply: false
---

**Commands:** `git diff <base>...HEAD`, `./gradlew :<module>:lintGeneralDebug`, `grep -rn "pattern" <feature>/src`
**Model:** everyday — escalate to `claude-opus-4-8` if the review surfaces an architectural conflict with non-obvious resolution

---

> **Core behaviors:** Read the actual changed files before commenting — never assume from filename. Push back on real issues, no sycophancy. Surface every violation. See `/using-agent-skills` and the pattern map in `/android-patterns`.

---

**Context:** No `docs/context.md` (single-screen). Read the changed files plus, when a violation is unclear, the matching sibling screen to confirm the established convention.

---

## What to check

### Layer boundaries (MVP + Core framework)

- [ ] **View (Activity/Fragment/Widget)** — inflates layout, wires listeners, display-only formatting? **Flag** business logic, data fetching, or decision logic in the View.
- [ ] **Presenter** — owns business logic, extends `CorePresenter<VM>`, writes into the ViewModel? **Flag** direct Android view manipulation beyond the base contract, or `startActivity`/`Intent` navigation done outside the base `navigate(...)`.
- [ ] **ViewModel** — display-state holder (`CoreViewModel`, `@Bindable`), `Parcelable`? **Flag** business logic, repository calls, or network access in the VM.
- [ ] **Effects** — one-off UI effects (toast/snackbar/navigate/close/loading) go through the VM event queue, not called directly from the Presenter into the View.

### Dependency injection (Dagger)

- [ ] Presenters/Repositories/UseCases use `@Inject constructor`; Activities/Fragments/Widgets use member injection (`component.inject(this)`).
- [ ] New injectable View added to the feature `@Component`'s `inject(...)` list.
- [ ] Cross-feature deps declared via the other feature's `-api` component, not a direct DFM dependency.
- [ ] Component lifecycle respected (built via `<Feature>ComponentBuilder`, released `onStop`).

### Navigation

- [ ] Cross-feature navigation goes through the `<Feature>NavigatorService` interface (in `-api`) + holder — **flag** a direct dependency on another feature's DFM.
- [ ] Intent extras use the generated `@DartModel`/`@BindExtra` binder, not manual `Bundle` string keys.

### Strings / resources

- [ ] No hardcoded display text in View/Presenter — all via `R.string`.
- [ ] Market-variant copy uses the string variant switcher, not ad-hoc country `if`s.

### Coroutine / correctness

- [ ] Repository suspend functions wrap IO in `withContext(dispatcher.io())` — **flag** network/DB on the main dispatcher.
- [ ] Presenter launches in its lifecycle-bound scope (from `CorePresenter`) — **flag** `GlobalScope` or leaked scopes.
- [ ] VM mutations that drive Data Binding happen on the main thread.
- [ ] No `!!` on nullable API/DB results that can be null.

### Android Lint

- [ ] `./gradlew :<module>:lintGeneralDebug` — zero new violations (custom rules on).
- [ ] No `@Suppress`/`tools:ignore` without a documented reason.

### Tests

- [ ] Presenter changes have matching JUnit + MockK tests in `src/test/...` mirroring the source path — see `/android-test`.

---

## Output format

For each issue:
```
[SEVERITY] File:line — description
  Why: ...
  Fix: ...
```

`[ERROR]` = breaks the MVP contract / DI graph / coroutine correctness | `[WARNING]` = convention deviation, test gap | `[SUGGESTION]` = improvement worth considering.

Push back on real issues — do not soften findings. At the end, list patterns observed not covered by `/android-patterns` as **Suggested skill updates**.
