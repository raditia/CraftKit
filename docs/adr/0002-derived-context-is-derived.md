# ADR-0002: Derived context is derived at read time, never stored

- **Status:** Accepted
- **Date:** 2026-09-17
- **Deciders:** Gusti Raditia Madya

## Context

`docs/context.md` mixes two kinds of content with opposite maintenance needs. Of the nine
sections `/fe-context` writes, four are facts git already holds: `Changed Files`
(staged / committed / pushed), `Key Changes`, `Architecture Patterns in Use`, and the
`Branch | Base | Commit` header. The rest is human intent, covered by ADR-0001.

Recording a derived fact is what creates staleness, and the freshness rule around it does not
hold:

- The cache key is branch plus commit equality, so the cache hits only when zero commits have
  landed since the last write. On an active feature branch that is a near-zero hit rate: it
  regenerates on essentially every read while being trusted in between.
- Staged-but-uncommitted work does not move `HEAD`. So editing and staging files leaves the
  check reporting `both match → context is fresh` while the doc's own
  `Staged (uncommitted)` section is wrong. The one state the doc exists to track is the state
  its key cannot see.
- The always-active `grounding` rule already states the general form of this: a context doc is a
  cache, and a cache with no invalidation story is a stale answer waiting for a confident
  reader. It also prefers recomputation over recording wherever a value is cheap to recompute.

Two facts bound the blast radius. No cold agent reads the file; all fourteen receive excerpts
inline from the orchestrator's `CONTEXT:` block. And twelve native skills already declare
`No docs/context.md required` and read a real sibling instead, so the derive-don't-store
pattern is established here rather than novel. The real reader count for the derived half is
about eight skills, not the thirty-eight files that merely mention the path.

## Options considered

| Option | Pros | Cons |
|--------|------|------|
| A (chosen) stop writing the derived sections; derive them into the turn per run | Staleness becomes structurally impossible, not merely detected; the silent staged-work hole disappears with the thing it lied about; nothing to merge, nothing to conflict | The main session pays a derivation per run instead of reading a file; cost is unmeasured |
| B keep writing it, fix only the keying | Smallest change; keeps a single place to look | Keeps a cache whose hit rate is near zero and whose key cannot see staged work, so the lie stays reachable |
| C keep the file but gitignore it as a local scratch cache | Removes merge conflicts | Keeps staleness and the staged-work hole; adds a file whose contents differ per machine, so two engineers debugging the same branch read different context |
| D tighten the freshness check to include the working tree | Closes the staged-work hole | Any tree change invalidates, so the hit rate goes from near-zero to zero and the cache is pure overhead |

## Decision

`/fe-context` stops writing the derived sections. The same content is derived at read time and
emitted into the turn that needs it.

Option A is chosen because it removes the failure mode rather than detecting it. B, C and D all
preserve a stored copy of a git-derived fact, which means a reader can still be handed a
confident wrong answer; D's own logic (invalidate on any tree change) is an admission that the
cache never pays for itself.

Option D deserves its rejection stated plainly: closing the staged-work hole correctly drives
the hit rate to exactly zero, at which point the file is overhead with a merge-conflict surface.
That argument is the clearest case for A.

Agents receive intent plus the diff they already get, and no derived summary. A `Key Changes`
paraphrase of a diff the agent already holds is the same content paid for twice; intent is the
part a diff cannot carry and the part they currently receive least of.

## Consequences

**Easier.** Staleness in the derived half cannot occur, so no freshness check, no regeneration
step, and no drift question. Merge conflicts in generated content go away. Agent spawns get
cheaper and carry more signal per token.

**Harder.** There is no file to open to see what a branch changed; you ask, and it is derived.
Eight skills' `**Context:**` lines, the standard context loading procedure, and Phase 0 of three
parallel commands all change together.

**Costs and what this locks in.**

- **The per-run derivation cost is unmeasured.** The case for A rests on the cache's hit rate
  being near zero on an active branch, which is reasoning from the freshness rule, not a
  benchmark. If derivation turns out to be expensive, the honest fix is to narrow what gets
  derived, not to restore the stored copy.
- Ships as a second release, after ADR-0001. That sequencing is deliberate: the derived doc
  survives release 1, so its absence is felt before it is deleted.
- Needs a `check.sh` invariant that no skill reads a section the generator no longer writes,
  otherwise a reader silently receives nothing where it used to receive content.
- Locks in that `docs/` holds intent and decisions only. Any future urge to cache a git-derived
  fact there should be read against this ADR first.
