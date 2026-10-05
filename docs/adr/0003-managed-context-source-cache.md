# ADR-0003: Context sources are read from a craftkit-managed cache outside every project

- **Status:** Accepted
- **Date:** 2026-10-05
- **Deciders:** Gusti Raditia Madya

## Context

A project can connect one or more team documentation repos on GitHub (PRDs, specs, SQL,
meeting notes, decisions) so `/interview`, `/spec` and `/plan` can check an ask against what
the team already recorded (`docs/planning/context-source.md`). The planning skills need to
search those repos, which means their text has to be readable somewhere at planning time.

Two existing contracts bound where that text may live:

- ADR-0002 locks in that `docs/` holds intent and decisions only, so nothing derived from
  elsewhere is cached inside a project.
- `partials/external-sources.md:47` says "Write nothing you fetched to disk", written for Figma
  and Lark, where the content is reachable on demand through an MCP read and a stored copy only
  creates staleness.

A docs repo is different from a Figma node: relevance search needs the whole tree, not one
pointer, and git already gives a reliable revision marker (the SHA) that Lark and Figma lack.
The author also ruled out committing anything into the code repo and naming any company or
repo in craftkit itself.

## Options considered

| Option | Pros | Cons |
|--------|------|------|
| A (chosen) craftkit-managed shallow clone per source under `~/.craftkit/context-cache/`, refreshed at planning time, pruned when no project references it | Fast local search on every host; works offline from the last fetch with an honest `cannot-verify`; the user maintains nothing; SHA gives exact provenance | Doc text sits on the user's disk outside any project; craftkit owns a fetch, lock and prune path that can fail |
| B user-managed clone that the project points at | Craftkit stores nothing and runs no fetch | The user must clone, pull and clean up per source; the spec's rewrite chose to remove exactly this step |
| C live fetch through the GitHub API per run | Nothing on disk | Network on every planning run; search over an API is weak (list then fetch per file); rate limits; no offline path |
| D copy matched docs into the project's planning files | Context travels with the spec | Breaks ADR-0002's boundary; leaks team doc text into code repos and their history |

## Decision

Option A. The cache lives only under `~/.craftkit/context-cache/`, never inside a project, so
ADR-0002's boundary holds: planning files keep pointers (`<repo>@<sha>:<path>:<line>`) and the
decisions the author approved, never doc text. This is not an exception to ADR-0002; it is the
first stored copy that sits outside the boundary ADR-0002 draws.

The absolute sentence in `partials/external-sources.md:47` is scoped, not relaxed: Figma and
Lark content still never touches disk; `kind: git` content exists only inside the managed cache.
A, unlike B, removes the maintenance step the author asked to remove; unlike C, it searches
locally and survives an outage; unlike D, it keeps doc text out of code repos.

## Consequences

**Easier.** Search is a local read on every host. Provenance is exact: a SHA, a path, a line.
An outage degrades to the last fetched SHA reported as `cannot-verify`, never to a guess.

**Harder.** Craftkit now owns a fetch, a lock against two projects refreshing one cache, URL
normalization so one repo maps to one cache, and pruning. The store
(`~/.craftkit/context-sources.json`) must never hold credentials, so URLs carrying userinfo are
refused rather than stored. Only `github.com` is accepted; a GitHub Enterprise host is refused
until a team needs it.

**Costs and what this locks in.**

- Team docs sit on the developer's disk in a place they did not choose, so the cache is created
  owner-only (directories 0700, the store 0600). Disconnect prunes a cache no project references
  and prints its path and size. A project whose root is missing still counts as a reference, so an
  unmounted drive never loses its cache to another project's disconnect; `status` lists such
  entries and `forget-stale` removes them. A run killed between saving the store and pruning can
  leave an unreferenced cache behind until the next prune of that source.
- Access rides the developer's existing git credentials. A repo they cannot fetch is
  `cannot-verify`, and craftkit never asks for, stores, or forwards a token.
- Any future urge to store fetched Figma or Lark content should be read against this ADR: the
  allowance is for a git source with a SHA, kept outside every project, and nothing wider.
