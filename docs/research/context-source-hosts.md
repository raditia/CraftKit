# Context source: what each host lets the helper do

**Date:** 2026-10-05 · **Task:** T4 spike in `docs/planning/context-source.md` · **Gate for:** T5 onward

## Question

Can a prose planning step, on each host craftkit ships to, drive
`scripts/context-source.sh` (refresh, search, cite, pause on conflict)? Does the host allow the
three things the helper needs: running the script, network for `git fetch`, and writes under
`~/.craftkit`?

## Method

A local bare repo stood in for `github.com/<fixture-org>/<fixture-docs>` through git's
`url.<base>.insteadOf`, holding one planted decision ("Bookings close 2 hours before
departure", `decisions/0007-booking-cutoff.md:5`). A throwaway project was connected to it, and a
stub of the planned partial (refresh, search, read each hit, emit the CONFLICT block, run three
probes) was given headlessly to each host with the ask "riders can book a shuttle seat up to 30
minutes before departure". Each host ran with its user default permissions. The spike entry was
disconnected afterwards and its cache pruned.

## Results

| Host | Script runs | Network | `~/.craftkit` write | Cited CONFLICT | Evidence |
|------|-------------|---------|---------------------|----------------|----------|
| Claude Code (`claude -p`, Bash and Read allowed) | ok | ok (`api.github.com` 200) | ok | yes, `@f0d84daa928f:decisions/0007-booking-cutoff.md:5`, paused for A/B/C | spike run 1 |
| Codex (`codex exec`, default sandbox) | ok | **fail** (curl exit 6, HTTP 000) | **fail** (`EPERM`) | yes after the fix below, same citation, from the cached SHA reported `cannot-verify` | spike runs 1 and 2 |
| Cursor | not run | not run | not run | not run | `cannot-verify (cursor-agent CLI not installed)` |
| Gemini CLI | not run | not run | not run | not run | `cannot-verify (gemini CLI not installed)` |

## Bugs the spike and review found

The first Codex run stalled until interrupted (exit 130). `withLock` retried forever when
`mkdir` failed for a reason other than an existing lock, and the sandbox's `EPERM` is such a
reason. Fixed: any non-`EEXIST` failure returns at once, and `refresh` reports the cached SHA as
`cannot-verify (cache not writable (<code>))`. A `check.sh` fixture with a read-only cache holds
it (must finish in under 10 seconds). Search lines now carry `sha=` and `file=`, so a reader can
cite and open a hit without depending on refresh output.

Review after the spike found the same class elsewhere, all fixed with `check.sh` fixtures and
each fixture shown to fail against the broken code: a read-only home with no cache now exits 4
cleanly instead of crashing; a corrupt store is refused and left untouched instead of being read
as empty and overwritten; the store and caches take locks around every write; symlinks in a docs
repo are never followed; skipped files are counted per reason and never as searched; unexpected
errors exit 5, distinct from usage (1).

## Decided fallback

- **Read-only sandbox (Codex default):** planning proceeds from the cached SHA, labelled
  `cannot-verify`, and says so. Search, reading and the conflict prompt all work.
- **No cache yet in a read-only sandbox:** the first `connect`, and any refresh that needs the
  network, cannot happen there. `refresh` exits 4 (`no-copy`), and the partial tells the user to
  run `bash ~/.craftkit/bin/context-source.sh refresh` (or `connect`) outside the sandbox, or to
  approve the host's escalation prompt, then retry. It never proceeds as if the source were empty.
- **Cursor and Gemini:** unverified until their CLIs are available to probe. A host that cannot
  run the shell call at all would look exactly like an unconnected project, so the partial must
  say `context source not consulted: <why>` whenever the call did not run or exited 1, 3 or 5,
  rather than staying silent. That wording is T7's job; until T12 runs there, these hosts are
  unverified, not degraded.

## Consequences for the plan

- T5 onward can proceed: the call path works on the one host with full access and degrades
  honestly on the restrictive one.
- T7 must carry the `no-copy` instruction above verbatim and cite from `file=`/`sha=`.
- T12's Codex leg runs in the default sandbox, so its pass bar is measured on the degraded path;
  its runs need a pre-populated cache.
