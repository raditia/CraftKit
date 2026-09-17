---
name: grounding
description: Provenance law for claims that drive action. Always active, so a finding or an edit rests on something checked rather than something recalled.
---

A session reads a file at turn 3 and edits it at turn 40. Between those, the file changed, the branch moved, or the read never happened and the detail came from memory of a similar codebase. The output looks identical either way, which is the whole problem: a recalled fact and a verified one are indistinguishable in prose.

So claims that drive action carry where they came from.

## Three labels

| Label | Means | Example |
|---|---|---|
| `[verified: <how>]` | Checked this turn, and the how is reproducible: a command and its output, or `file:line` actually read | `[verified: check.sh:175]` · `[verified: git diff --stat]` |
| `[from context.md @<sha>]` | Taken from a context doc, and the doc's baseline is named so a reader can tell whether it has drifted | `[from context.md @a891629]` |
| `[UNVERIFIED]` | Stated from inference, memory, or a source not consulted this turn | `[UNVERIFIED: only the re-invocation shape confirmed]` |

## The law

**An `[UNVERIFIED]` claim may not back an `[ERROR]`-severity finding or a code edit.** Verify it first, or lower the severity to match the evidence. A confident wrong claim costs more than a hedged right one, because the hedge invites a check and the confidence forecloses it.

## Where labels go

Label the claims that **drive an action**: review findings, the justification for an edit, an answer the user will act on. Narration needs none, and labelling it drowns the signal in ceremony.

Applies to `/fe-review`, `/android-review`, `/ios-review`, `/code-quality`, `/ponytail-review`, `/ponytail-audit`, `/debug`, `/research`, and every cold agent that reports findings.

## Handed content only

A cold agent reviews the content it was given. When a file it needs was not provided, it reports `not provided` and reviews the rest, rather than reading a possibly-different version or recalling one. The parallel orchestrators pass full file contents for exactly this reason, so a gap in the payload is a gap to name, not to fill from memory.

**One agent inverts this, and only one.** `bulk-read` is spawned precisely to read a file the caller withheld, because a file read whole by the caller is re-sent on every turn after while the agent's context is discarded. Its bullets carry `file:line`, so a claim built on them stays reproducible, and they answer questions rather than justify edits: an edit needs text the editor actually read, so when a line must change `bulk-read` names the range and the caller reads that slice, which `gate-read-size.js` never refuses. Every other cold agent still reports `not provided`. The same exception is stated in `partials/grounding-claims.md`, the copy agents actually carry, and `check.sh` holds the two together.

## Staleness is a state, not a guess

Three outcomes, and the third is not the first:

- **clean**: the baseline and the working tree agree.
- **drifted**: named files changed since the baseline, so anything said about them is suspect.
- **cannot-verify**: the baseline is unreachable (squash merge, rebase, amend, gc), or there is no repository. This reports as cannot-verify, never as clean, because a detector that answers "clean" when it cannot see is worse than one that admits it.

## Prefer derivation over recording

Every recorded fact is a future stale fact. When a value can be recomputed cheaply, recompute it instead of writing it down. This repo's own proof: hardcoded model ids went stale and needed a hotfix, while ids derived from entitlements at read time cannot. A context doc is a cache, and a cache with no invalidation story is a stale answer waiting for a confident reader.
