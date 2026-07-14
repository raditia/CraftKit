---
name: android-context
description: Generate or update docs/context.md for an Android branch — MVP flavored summary of changed feature modules, screens, presenters, and Dagger wiring. Optional branch-scoping doc that feeds /android-review and /ship.
alwaysApply: false
---

**Commands:** `git diff`, `git log`, `git status`, `./gradlew :<module>:lintGeneralDebug`
**Model:** cheapest — `claude-haiku-4-5`. Escalate to everyday if the diff spans multiple feature modules with cross-feature `-api`/navigator changes.

---

> **Core behaviors:** Surface conflicts — never silently resolve them. Emit an inline plan before executing. Verify output before claiming done. See `/using-agent-skills`.

---

# Android Feature Context

Optional. Single-screen work does **not** need this — read a sibling screen instead (see `/android-patterns`). Generate this only for multi-screen or cross-feature branches, so `/android-review` and `/ship` read one summary instead of re-scanning modules.

Organized by **MVP role + module split**, not EVPMR.

---

## Step 0 — Inline plan

```
PLAN:
1. Detect base branch
2. Collect: staged → committed-not-pushed → pushed-on-branch
3. Map each changed file to its module (feature/-api/-base/-model/-navigation) + screen + MVP role
4. Surface any layer/DI/navigation violations (do not fix)
5. Write/update docs/context.md
6. Verify output
→ Proceeding unless redirected.
```

---

## Step 1 — Collect changes

```bash
git remote show origin | grep "HEAD branch"     # base, default main
git diff --cached --name-status                  # staged
git log @{u}..HEAD --oneline && git diff @{u}..HEAD
git log main...@{u} --oneline && git diff main...@{u}
```
If `@{u}` errors (no upstream), skip and note it.

---

## Step 2 — Conflict detection (surface only — do not fix)

- Business logic / repository calls in an Activity/Fragment/Widget or ViewModel
- Presenter doing Android view manipulation beyond the base contract, or navigating outside `navigate(...)`
- Network/DB on the main dispatcher (missing `withContext(dispatcher.io())`)
- Hardcoded display text instead of `R.string`
- A direct DFM dependency where an `-api` NavigatorService belongs

```
CONFLICT: file:line
  Found: [what the diff shows]
  Expected: [MVP rule]
  Options: A) ... B) ...
  → Awaiting direction.
```

---

## Step 3 — Write `docs/context.md`

```markdown
# Android Feature Context
<!-- managed by android-context — regenerate with /android-context -->
**Generated:** {{ISO timestamp}}
**Branch:** {{branch}} | **Base:** {{base}} | **Commit:** {{git rev-parse HEAD}}

## Summary
{{2-4 sentences: what is being built, which feature module(s), user-facing purpose}}

## Modules & Screens Touched
| Module | Split (feature/-api/-base/-model/-nav) | Screen (`<Screen>`) | Roles changed |
|--------|----------------------------------------|---------------------|---------------|
| <feature> | feature | <Screen> | Presenter, ViewModel |

## Key Changes
{{bullets with file refs: new screens, new repositories, navigator/`-api` changes, Dagger component changes}}

## MVP Notes
- **State:** {{which ViewModels hold what @Bindable state / StateFlow}}
- **Navigation:** {{NavigatorService methods, Dart nav models added/changed}}
- **DI:** {{new @Component inject entries, providers, cross-feature -api deps}}
- **Data:** {{new/changed repositories/interactors + dispatchers}}
- **Strings:** {{new strings.xml keys, variant-switcher usage}}

## Known Issues
{{Android Lint findings, build errors. Empty if none.}}

## Conflicts / Ambiguities
{{Unresolved conflicts surfaced above. Not silently fixed.}}

## Test Coverage Needed
{{Presenters new/changed lacking JUnit/MockK tests — see /android-test}}
```

Hard limit: **≤ 400 lines**. Summarize; never paste whole files.

---

## Step 4 — Verify

- [ ] `docs/context.md` written at the Android repo root
- [ ] Every changed file mapped to a module + role
- [ ] Conflicts surfaced, not silently resolved
- [ ] No unrelated files dumped in

Report: path written, modules covered, conflict count, line count.
