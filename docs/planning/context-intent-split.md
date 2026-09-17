---
slug: context-intent-split
status: active
created: 2026-09-17
---

# Split feature intent from derived context

## Spec
**Updated:** 2026-09-17T00:00:00Z · **By:** /spec

- **Objective:** stop one feature's spec destroying another's, and stop the context doc asserting
  git facts it cannot keep current. Two releases, decided in ADR-0001 and ADR-0002.
- **Users & job:** anyone running craftkit workflows across more than one feature from a single
  checkout, which is every session that is not a one-off fix.
- **Success:**
  - Intent for N features coexists with no shared slot and no merge conflict in generated content.
  - Every skill that reads or writes intent resolves the active feature by one shared rule.
  - `/fe-context` neither reads nor writes intent, and cannot recreate the shared slot.
  - (Release 2) the derived half is not stored, so it cannot be stale.
- **In scope:** the `planning-resolve` partial, the six skills that touch intent, three commands,
  two partials, the loading procedure, `check.sh` invariants, and migrating the live block.
- **Out of scope:**
  - Enforcing that intent files get committed early. It is a discipline this design depends on
    and deliberately does not police.
  - Detecting rotted `status: active`. No git fact distinguishes paused from abandoned.
  - Release 2's derived-half removal, which is the next release, not this one.
- **Constraints:** bash 3.2; the em-dash prose gate; one resolver, never a second copy of the
  glob rule.
- **Key decisions:** ADR-0001 (intent keyed per feature), ADR-0002 (derived context is derived).
  Both record the options weighed and the rejected alternatives.
- **Acceptance:**
  - [x] `check.sh` check 32 passes, and fails on each of its three branches before passing.
  - [x] No source file under `skills/ commands/ partials/ rules/ agents/` references the shared
        PLANNING block.
  - [x] The live block is migrated to `docs/planning/eval-correctness.md`, not deleted.
  - [ ] `sync.sh` prints `Sync complete.` and a second consecutive run reports `(up to date)`.
  - [ ] README documents the new partial; version agrees across the three files.
  - [ ] Release 2: `/fe-context` stops writing the derived sections.

## Task Plan
**Updated:** 2026-09-17T00:00:00Z · **By:** /plan

| ID | Task | Acceptance | Depends on | Executes via |
|----|------|-----------|-----------|--------------|
| T1 | `partials/planning-resolve.md`: glob on status, two-candidate rule, file shape | Injected by all five intent skills | none | direct authoring |
| T2 | `/spec` owns `docs/planning/<slug>.md`, author-named slug, frontmatter status | No PLANNING reference remains | T1 | direct authoring |
| T3 | `/plan`, `/adr`, `/docs`, `/eval` read and write that file | ADR pointers resolve as `../adr/` | T2 | direct authoring |
| T4 | `/fe-context` stops preserving the block; migrates a legacy one instead | Template carries no marker | T1 | direct authoring |
| T5 | Three commands and two partials stop naming the block | `grep -rn "PLANNING block"` is empty | T2 | direct authoring |
| T6 | Loading procedure resolves intent separately from derived context | Step 4 present in the always-on rule | T1 | direct authoring |
| T7 | `check.sh` check 32, three branches | Each branch fails before it passes | T2, T3, T4, T5 | `bash check.sh` |
| T8 | Migrate the live block to `eval-correctness.md`, dogfood this file | Both files resolve correctly | T7 | direct authoring |
| T9 | README sync, CHANGELOG, v1.39.0 | Version agreement check passes | T8 | repo README sync matrix |
| T10 | Release 2: derived half stops being written (ADR-0002) | Separate release | T9 | deferred |

Critical path: T1 → T2 → T3 → T7 → T8 → T9. T10 is the next release.

## Decisions
- [ADR-0001](../adr/0001-intent-keyed-per-feature.md) · intent lives in one file per feature under `docs/planning/`, keyed by an author-given slug, mapping derived by globbing on status · Accepted 2026-09-17
- [ADR-0002](../adr/0002-derived-context-is-derived.md) · the git-derived half is derived at read time and never stored · Accepted 2026-09-17
