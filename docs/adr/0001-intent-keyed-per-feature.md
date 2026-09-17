# ADR-0001: Feature intent is keyed per feature, not per context file

- **Status:** Accepted
- **Date:** 2026-09-17
- **Deciders:** Gusti Raditia Madya

## Context

`docs/context.md` holds a single delimited PLANNING block carrying the spec, task plan and
decisions for "the current feature". Seven skills write into that block (`/spec`, `/plan`,
`/adr`, `/grill`, `/interview`, `/docs`, `/eval`) and the file is git-tracked.

The block has exactly one slot, and the doc has exactly one `**Branch:**` field, so it can
describe one feature at a time. Real work runs several features across several branches from a
single checkout. Three consequences follow, and all three were observed rather than predicted:

- Writing a spec for feature B destroys feature A's spec, because there is nowhere else for it
  to go. This happened live in the session that produced this ADR: a `/spec` run overwrote the
  shipped v1.36.0 planning block.
- `/fe-context` regenerates the derived sections on a branch or commit mismatch but preserves
  the PLANNING block verbatim, so the file can hold feature A's intent beside branch B's
  changed-file list. That state is not stale, it is incoherent, and it reads as authoritative.
- The file is tracked, so every parallel merge collides inside machine-generated content that
  no human should be resolving by hand.

The forces: intent must survive N concurrent features; it must not be destroyed by a sibling
feature; and merging two features must not require resolving a conflict in a generated file.

## Options considered

| Option | Pros | Cons |
|--------|------|------|
| A (chosen) one file per feature, `docs/planning/<slug>.md`, named by the author at `/spec` time | Distinct filenames cannot collide on merge; a sibling feature cannot overwrite; survives branch rename; branch→feature mapping stays derived by globbing for `Status: active` | Loses the single place to look; needs a resolution rule when two active files are present; author must supply a name |
| B keep one file, PLANNING becomes a list of per-feature sub-blocks | One place to look; no new directory | Every writer must parse and target a sub-block, which is the same single-file merge conflict with extra indirection; the destructive-overwrite bug returns the moment one writer targets the wrong sub-block |
| C fixed `docs/planning/current.md` | Simplest possible rule; no naming step | Reintroduces the exact defect: two branches, same filename, different content, conflict on every parallel merge |
| D per-branch file, slug derived from branch name | No naming step | Breaks on branch rename, has no answer on `main`, and a stacked PR pair wants one feature across two branches |

## Decision

Intent lives in `docs/planning/<slug>.md`, one file per feature, with the slug supplied by the
author when `/spec` runs and recorded in the file's frontmatter alongside a human-owned
`Status:` field (`active` / `shipped` / `abandoned`).

Option A is the only one where the collision is impossible rather than merely unlikely: two
features cannot share a filename, so no merge resolves generated content and no writer can
overwrite a sibling's intent. B and C both keep a single shared slot and therefore keep the
defect; D makes the key a value git controls, which breaks on the two operations (rename,
stacking) that are routine.

The branch→feature mapping is deliberately **not** recorded. It is derived by globbing
`docs/planning/*.md` for `Status: active`, which under a single-checkout workflow normally
yields exactly one file. When it yields more, the active file is matched against the current
diff, and the author is asked only when the diff intersects two candidates or none: matching is
a fact, choosing between real candidates is a decision.

`Status:` is human-owned on purpose. Intent goes stale when a person changes their mind, not
when code moves, so an automated freshness check has no signal to offer. The drift detector was
considered here and rejected: this repo squash-merges, so a recorded baseline commit becomes
unreachable at merge and the detector would answer `cannot-verify` as its common case.

## Consequences

**Easier.** N features coexist without destroying each other. Parallel merges stop colliding in
generated content. A shipped feature's intent stays readable instead of being overwritten by the
next one.

**Harder.** There is no longer one file to open. A reader must resolve which feature is active
before reading intent, and that resolution can be ambiguous.

**Costs and what this locks in.**

- Untracked files survive `git checkout`, so an uncommitted planning file follows the author
  onto other branches. The diff-matching rule mitigates this; it does not eliminate it.
  Committing the planning file early is a discipline this design depends on and does not enforce.
- `Status: active` can rot. Nothing detects a feature abandoned weeks ago and still marked
  active.
- Seven writers must be migrated. Until all seven are, intent has two possible homes and a
  missed writer splits it across both silently, which is worse than the single-slot bug because
  it is quiet. **This release is therefore not complete without a `check.sh` invariant that no
  skill writes the PLANNING block and that the marker is gone from the `/fe-context` template.**
- The author now names features. That name becomes the durable key, so a badly chosen slug is
  mildly sticky.
