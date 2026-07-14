---
name: ios-context
description: Generate or update docs/context.md for an iOS branch — MVVM-C flavored summary of changed modules, screens, coordinators, and fetchers. Optional branch-scoping doc that feeds /ios-review and /ship.
alwaysApply: false
---

**Commands:** `git diff`, `git log`, `git status`, `swiftlint lint --path <file>`
**Model:** cheapest — `claude-haiku-4-5`. Escalate to everyday if the diff spans > 8 files across multiple modules with cross-module coordinator changes.

---

> **Core behaviors:** Surface conflicts — never silently resolve them. Emit an inline plan before executing. Verify output before claiming done. See `/using-agent-skills`.

---

# iOS Feature Context

Optional. Single-screen work does **not** need this — read a sibling feature instead (see `/ios-patterns`). Generate this only for multi-screen or cross-module branches, so `/ios-review` and `/ship` read one summary instead of re-scanning `Modules/`.

Unlike the EVPMR frontend, iOS context is organized by **MVVM-C role**, not by Entry/View/Presenter/Model/Resource.

---

## Step 0 — Inline plan

```
PLAN:
1. Detect base branch
2. Collect: staged → committed-not-pushed → pushed-on-branch
3. Map each changed file to its module + screen + MVVM-C role
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
git log @{u}..HEAD --oneline && git diff @{u}..HEAD   # committed, not pushed
git log main...@{u} --oneline && git diff main...@{u} # pushed on branch
```
If `@{u}` errors (no upstream), skip and note it.

---

## Step 2 — Conflict detection (do not fix — surface only)

Scan the diff for MVVM-C violations:
- Business logic / networking / `push`/`present` inside a `…ViewController` or `…View`
- A `…ViewModel` importing a UIKit view type or navigating directly
- Raw network-service / DB calls inside a ViewModel (should be behind a `…FetcherProtocol`)
- Hardcoded display text instead of `NSLocalizedString`
- Strong (non-`weak`) `action`/`delegate` on a ViewModel

```
CONFLICT: file:line
  Found: [what the diff shows]
  Expected: [MVVM-C rule]
  Options: A) ... B) ...
  → Awaiting direction.
```

---

## Step 3 — Write `docs/context.md`

```markdown
# iOS Feature Context
<!-- managed by ios-context — regenerate with /ios-context -->
**Generated:** {{ISO timestamp}}
**Branch:** {{branch}} | **Base:** {{base}} | **Commit:** {{git rev-parse HEAD}}

## Summary
{{2-4 sentences: what is being built, which module(s), user-facing purpose}}

## Modules & Screens Touched
| Module | Screen (`<Feature>`) | Roles changed | Note |
|--------|----------------------|---------------|------|
| <Module> | <Feature> | ViewModel, Fetcher | ... |

## Key Changes
{{bullets with file refs: new screens, new Fetcher protocols, coordinator wiring, contract changes}}

## MVVM-C Notes
- **State:** {{which ViewModels hold what state}}
- **Navigation:** {{coordinator delegate methods added/changed}}
- **DI:** {{new Dependency struct fields / @Injected containers}}
- **Data:** {{new/changed Fetchers and their protocols}}
- **Strings:** {{new Localizable.strings keys}}

## Known Issues
{{SwiftLint findings, build errors. Empty if none.}}

## Conflicts / Ambiguities
{{Unresolved conflicts surfaced above. Not silently fixed.}}

## Test Coverage Needed
{{ViewModels new/changed lacking Quick specs — see /ios-test}}
```

Hard limit: **≤ 400 lines**. Summarize; never paste whole files.

---

## Step 4 — Verify

- [ ] `docs/context.md` written at the iOS repo root
- [ ] Every changed file mapped to a module + role
- [ ] Conflicts surfaced, not silently resolved
- [ ] No unrelated files dumped in

Report: path written, modules covered, conflict count, line count.
