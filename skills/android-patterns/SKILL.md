---
name: android-patterns
description: MVP + Core-framework architecture reference for a modular Android monorepo. Per-screen Activity/Fragment/Widget (View) + Presenter + ViewModel contract, Repository/Interactor data layer, Dagger DI, NavigatorService navigation, Gradle Dynamic-Feature-Module split. Use when designing or understanding an Android feature.
alwaysApply: false
---

**Commands:** `grep -rn "pattern" <feature>/src`, `./gradlew :<module>:lintGeneralDebug`
**Model:** everyday — escalate for a screen with novel state/effect orchestration not covered below

> Triggered by: "how does this screen work", "Android architecture", "explain this module", "where does state live", "how do I structure an Android feature"

---

> **Core behaviors:** Patterns serve the architecture — the Core-framework MVP contract wins. Read a real sibling screen before claiming the pattern; the codebase is the source of truth, this file is the map. See `/using-agent-skills`.

---

**Context:** No `docs/context.md` for single-screen work — read one real sibling screen package under `<feature>/src/main/java/.../<screen>/` to confirm exact naming and base classes before acting.

---

## The pattern: MVP + Core framework

**M**odel-**V**iew-**P**resenter over a shared `Core*` base-class framework, using **Android Views + Data Binding**, with **Jetpack Compose adopted incrementally per-widget** (a `ComposeView` embedded inside a Data-Binding layout, receiving already-computed display data — not a parallel MVVM stack). Newer screens may use an `androidx.lifecycle.ViewModel` + `StateFlow`; that's a migration path, not yet the dominant pattern. **Read the sibling before choosing.**

### Per-screen file set

For screen `<Screen>` in feature `<Feature>` (`<Prefix>` = `<Feature><Screen>`):

| File | Role | Hard rule |
|------|------|-----------|
| `<Prefix>Activity.kt` / `Fragment.kt` / `Widget.kt` | The **View** — inflates layout, wires listeners → Presenter, does display-only formatting (image load, tooltips) | **No business logic** |
| `<Prefix>Presenter.kt` | Business logic. `extends CorePresenter<VM>`. Talks to repositories/use-cases, writes state into the ViewModel, decides navigation targets | **No Android view refs beyond the base contract** |
| `<Prefix>ViewModel.kt` (or `.java`) | Display-state holder. `extends CoreViewModel`, `@Bindable` fields, `Parcelable` for process-death survival | **No business logic** |
| `<Prefix>ActivityNavigationModel.kt` | (in `-navigation`) intent-extra params, annotation-bound (`@DartModel`/`@BindExtra`) | Typed extras, no manual `Bundle` keys |

Base classes live in a shared `core`/`platform` module:
- `CoreActivity<P, VM>` / `CoreFragment` / `CoreFrameLayout<P, VM>` — lifecycle glue: creates the Presenter, binds the layout via `DataBindingUtil`, wires the `ViewModel` into `binding.viewModel`, drains the event queue back to the View.
- `CorePresenter<VM>` — holds `viewModel`, exposes `navigate(Intent)`, centralizes auth-retry and network-error → UI-event mapping.
- `CoreViewModel` — a Data-Binding `BaseObservable`; `@Bindable` getters/setters call `notifyPropertyChanged(BR.x)`.

### Screen composition

A screen = an Activity/Fragment hosting several independent MVP **widgets**. Each widget is its own Presenter + ViewModel + View triple (independently unit-testable), stitched by the parent screen's Presenter calling `widget.setData(...)`.

---

## State & data flow

| Question | Answer |
|----------|--------|
| Where does state live? | In the **ViewModel** as `@Bindable` fields (field-by-field mutable, classic MVP — not a single immutable `data class State`) |
| How does the View update? | Data Binding observes `@Bindable` getters; Presenter mutates the VM, VM calls `notifyPropertyChanged` |
| One-off effects (toast, snackbar, navigate, close, loading)? | Appended to the VM's bounded **event queue** as `Event(type, extras)`; the View drains it on the `events` property change and dispatches by `type` |
| Reactive streams in the view layer? | Rare. Classic MVP uses imperative Presenter→VM writes. Newer `StateFlow` ViewModels exist as a migration path — follow the sibling. |

---

## Dependency injection — Dagger 2

- **Constructor injection** (`@Inject constructor`) for Presenters/Repositories/UseCases; **member injection** (`fun inject(target)`) for Activities/Fragments/Widgets (framework classes can't take constructor params).
- **One feature `@Component`** per feature module, listing an `inject(...)` overload for every injectable in that feature. It declares `dependencies = [<OtherFeature>ApiComponent, ...]` on each sibling feature's `-api` component it needs, plus `modules = [...]` for feature-local providers.
- A `<Feature>ComponentBuilder` builds/reuses the component; a small `ComponentHolder : DefaultLifecycleObserver` nulls it out `onStop`, so the graph lives only while a screen of the feature is on-screen.
- App-level singletons (network client, session/auth, feature-flags, analytics) come from an app-level DI manager, consumed as a component dependency.

---

## Data layer — Repository / Interactor

```kotlin
// Modern: thin coroutine wrapper over the API provider, dispatcher-controlled
class <Feature>ApiRepository @Inject constructor(
    private val apiProvider: <Feature>ApiProvider,
    private val dispatcher: DispatcherProvider,
) {
    suspend fun requestX(param: XParam): XResponse =
        withContext(dispatcher.io()) { apiProvider.requestX(param).await() }
}
```
- **Repository** — network pass-through with dispatcher control; called from the Presenter.
- **Interactor** (older, coexisting) — a per-screen use-case that takes a `View` interface and calls back into it directly (`view.populate(...)`). Newer code favors Repository + suspend called from the Presenter. Follow the sibling.
- Network errors flow up through the `CorePresenter` error-mapping utility → VM `Event`/`Message` for the View to render.

---

## Navigation

1. **Cross-feature — NavigatorService + fallback.** `-api`/`-navigation` defines `interface <Feature>NavigatorService { fun getXIntent(context, params): Intent }`. The real impl lives in the DFM and is swapped into a holder (`<X>NavigatorServiceImplHolder.service = realImpl`) once the module loads; before that, `-base` ships a `FallbackNavigatorServiceImpl` returning an Intent to a generic "download this module" screen and resuming once downloaded. **Other features depend only on `-api`, never the DFM directly.**
2. **Intra-feature intent extras — Dart/Henson.** Navigation param classes annotated `@DartModel`/`@BindExtra` auto-generate a typed Intent builder + extras binder (`Dart.bind(this)` in `onCreate`).
3. **In-screen fragment nav** — AndroidX Navigation `safeargs` (`<X>FragmentDirections`).

No single app-wide Router/Coordinator — navigation is Intent + generated extras, gated behind per-feature service interfaces for cross-feature calls.

---

## Module split (Gradle)

A feature is split into up to 5 modules:

| Module | Plugin | Contains |
|--------|--------|----------|
| `<feature>-model` | `android-library` | pure data/DTO/param classes, enums. No Android resources. |
| `<feature>-api` | `android-library` | public contracts consumed by *other* features: navigator interfaces, public providers, cross-boundary DTOs. |
| `<feature>-navigation` | `android-library` | `@DartModel` intent-extra param classes. |
| `<feature>-base` | `android-library` | shared base classes, reusable widgets, `FallbackNavigatorServiceImpl`, its DI wiring. |
| `<feature>` | **`android-dynamic-feature`** | the actual screens/logic: Activities, Fragments, Widgets, Presenters, ViewModels, Dagger component, repositories. Ships as an on-demand split APK. |

Only the top-level `<feature>` is a Dynamic Feature Module. Anything another feature needs is pushed down into `-api/-base/-model/-navigation` (ordinary libraries bundled into the base app). Root `dependencies.gradle` centralizes the `libs.*` version catalog; `general-setting.gradle` is applied by every module.

---

## Strings / resources

- `strings.xml` per module, referenced as `R.string.x` (alias a base module's `R` as `BaseR` when reusing cross-cutting copy).
- A market/locale **variant switcher** (`stringSwitcher.getVariantStringValue(defaultRes, countryVariantRes)`) picks country-specific copy beyond standard `values-<locale>/` qualifiers.
- Never hardcode display text in a View/Presenter — always a resource.

---

## Build system

- Gradle (Kotlin DSL `settings.gradle.kts` + Groovy per-module `build.gradle`), shared `libs.*` catalog.
- One flavor dimension (e.g. `general`), build types `debug`/`staging`/`release`/`benchmark`.
- DFMs excluded from local debug builds by default (`build-enable.gradle`, gitignored, copied from a `.default` template) to keep sync/build fast; CI builds all.
- Build a module: `./gradlew :<feature>:assembleGeneralDebug`. Test: `./gradlew :<feature>:testGeneralDebugUnitTest`. Lint: `./gradlew :<feature>:lintGeneralDebug`.

---

## After using this skill

List any pattern you observed in the code that this map doesn't cover as **Suggested skill updates** — the codebase evolves faster than this doc.
