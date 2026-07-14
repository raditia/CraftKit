---
name: android-scaffold
description: Scaffold a new Android feature screen in a modular monorepo following the MVP + Core-framework contract — View (Activity/Fragment/Widget) + Presenter + ViewModel + NavigationModel + Repository stub, wired into the feature's Dagger component.
alwaysApply: false
---

**Commands:** `ls <feature>/src/main/java/.../<screen>`, `grep -rn "pattern" <feature>/src`, `./gradlew :<feature>:lintGeneralDebug`
**Model:** cheapest — `claude-haiku-4-5`. Escalate to everyday if the screen needs state/effect orchestration not covered by the Core MVP contract

---

> **Core behaviors:** Surface assumptions before generating. Copy a real sibling screen — never invent structure. Don't pre-split into widgets speculatively. See `/using-agent-skills` and the pattern map in `/android-patterns`.

---

**Context:** No `docs/context.md` for a single screen. **Mandatory first step:** read one existing sibling screen package in `<feature>/src/main/java/.../<screen>/` to copy exact base classes, Dagger wiring, and Kotlin/Java split.

---

## Step 1 — Understand context

```
ASSUMPTIONS I'M MAKING:
1. Feature module: [target <feature> DFM]
2. Screen name: [PascalCase, e.g. Detail]
3. Prefix: <Feature><Screen> → e.g. <Prefix>
4. Sibling I'm copying from: [path to an existing screen package]
5. UI tech: [Data Binding / Compose-in-widget] — match the sibling
6. Reachable from another feature? [yes → needs -api NavigatorService / no]
→ Correct me now or I'll proceed with these.
```

Prefer copying the newest sibling that uses the module's current conventions.

---

## Step 2 — Create the screen package

Package: `com.<org>.<app>.<feature>.<screen>` — Android-facing files go in a `view/` sub-package.

### `<Prefix>ViewModel.kt` — display state (`CoreViewModel`, `@Bindable`, `Parcelable`)
```kotlin
class <Prefix>ViewModel : CoreViewModel() {
    @get:Bindable
    var title: String = ""
        set(value) { field = value; notifyPropertyChanged(BR.title) }
    // one-off effects go through the inherited event queue: postEvent(Event(TYPE, extras))
}
```

### `<Prefix>Presenter.kt` — business logic (`CorePresenter<VM>`)
```kotlin
class <Prefix>Presenter @Inject constructor(
    private val repository: <Feature>ApiRepository,
) : CorePresenter<<Prefix>ViewModel>() {

    fun onViewCreated() {
        launch {                                   // coroutine scope from CorePresenter
            val result = repository.requestX(param)
            viewModel.title = result.title         // mutate VM → Data Binding repaints
        }
    }
}
```
**No Android view references** beyond the base contract; no navigation `startActivity` here — call `navigate(intent)` from the base.

### `<Prefix>Activity.kt` (or `Fragment`/`Widget`) — the View
```kotlin
class <Prefix>Activity : CoreActivity<<Prefix>Presenter, <Prefix>ViewModel>() {
    override fun layoutId() = R.layout.activity_<prefix_snake>
    override fun onInject(component: <Feature>Component) = component.inject(this)
    override fun onViewModelCreated() {
        Dart.bind(this)                            // typed intent extras
        binding.viewModel = viewModel
        presenter.onViewCreated()
    }
}
```
Wire listeners → `presenter.onX()`. Display-only formatting (image load, tooltips) may live here. **No business logic.**

### `<Prefix>ActivityNavigationModel.kt` — in `<feature>-navigation`
```kotlin
@DartModel
class <Prefix>ActivityNavigationModel {
    @BindExtra lateinit var itemId: String
}
```

---

## Step 3 — Dagger wiring

Add the new View to the feature `@Component`:
```kotlin
fun inject(activity: <Prefix>Activity)
```
Constructor-injected Presenter/Repository need no manual provider unless they require a binding — add one to the feature module if so. Reuse the existing `<Feature>ComponentBuilder`.

State the wiring you did or skipped.

---

## Step 4 — Navigation

- **Reachable within the feature:** the caller builds the Intent via the generated Henson/Dart builder (`Henson.with(context).gotoXActivity()...build()`).
- **Reachable from another feature:** add `getXIntent(context, params): Intent` to the feature's `<Feature>NavigatorService` in `-api`, implement it in the DFM, and register the impl in the holder. Never let another feature depend on the DFM directly.

---

## Step 5 — Strings

Add to the module's `res/values/strings.xml`; reference `R.string.<key>`. Never hardcode display text in View/Presenter. For market-variant copy, use the string variant switcher.

---

## Step 6 — Quality rules

- Presenter holds logic; ViewModel holds state; View renders. No leakage.
- ViewModel is `Parcelable`-safe for process death.
- Split a screen into widgets only when it genuinely grows complex — not speculatively.
- Match the sibling's Data-Binding vs Compose-in-widget choice; don't introduce a `StateFlow` ViewModel unless the sibling already uses one.

---

## After generating

- [ ] `./gradlew :<feature>:lintGeneralDebug` — zero new violations
- [ ] `./gradlew :<feature>:testGeneralDebugUnitTest` compiles (add a Presenter test — see `/android-test`)
- [ ] Dagger graph compiles (the View is in the `@Component`'s `inject(...)` list)
- List each file created with its path + package
- Note the sibling you copied and any wiring assumptions
- List patterns observed not covered by `/android-patterns` as **Suggested skill updates**
