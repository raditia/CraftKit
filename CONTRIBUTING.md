# Contributing to craftkit

There is no build and no test suite — the product is the markdown in `rules/`, `skills/`,
`commands/`, and `agents/`, plus the bash that distributes it. So `check.sh` is the gate.

## The gate

```bash
bash check.sh   # content integrity — exit 0 required before every commit
bash sync.sh    # distribute; a second consecutive run must report no work
```

Both must pass. `sync.sh` printing `Sync complete.` only proves files copied — the real
signal is that a **second consecutive run reports no work at all** (`(up to date)`
everywhere). Any `+` or `-` line on a repeat run is a diff-skip bug, not noise.

## What check.sh catches

It checks the mechanical invariants a reader can't hold in their head:

- dangling `subagent_type` references
- skill/command install-destination collisions
- nested skills that never sync (`skills/` must stay exactly one level deep)
- frontmatter `name` that disagrees with the file path
- unresolvable `craftkitInject` sources
- a routing hook advertising a renamed command, or no longer resolving a platform from `cwd`
- an orchestrator covering RN/web but not native
- an always-active rule contradicting the native skills on `docs/context.md`
- undocumented agents or skills
- an adapter listed in `sync.sh` with no sourced file behind it, or an adapter file not listed
- a `parallel-*` orchestrator with no sequential twin mapped in both the rule and the hook
- a routing hook pinned to a node version fnm can prune
- `package.json` declaring a license with no `LICENSE` file
- version drift across `package.json` + README header + newest `CHANGELOG.md` section

**Every check exists because that exact bug shipped and went unnoticed.** When you fix a
new class of bug, add a check — and confirm it fails before you make it pass. A check you
never saw fail is a check you haven't tested.

## Authoring rules

The full checklist for adding or changing a rule, skill, command, or agent lives in
[CLAUDE.md](CLAUDE.md) under **"Critical authoring rules"** — conflict check first, token
audit, mandatory README sync, the cold-copy problem and when to reach for `craftkitInject`,
and the naming convention that makes a skill's directory name its slash command.

It is deliberately kept there rather than duplicated here: that file is loaded into every
session working in this repo, so it is the copy that actually gets followed.

## Releasing

1. Bump `version` in `package.json`.
2. Update the `# craftkit \`vX.Y.Z\`` header in `README.md`.
3. Add a `## vX.Y.Z — YYYY-MM-DD` section at the top of `CHANGELOG.md`.

Pushing to `main` triggers `.github/workflows/release.yml`, which reads the version from
the **README header** and the release notes from the matching `CHANGELOG.md` section. A
missing section fails the release rather than shipping placeholder notes. `check.sh` guards
the three-way version agreement.

Publishing to npm is manual — the workflow has no publish step and no `NPM_TOKEN`, which is
why the npm package trails the repo version.

## Conventions that bite

- **Never edit installed files** in `~/.claude/`, `~/.cursor/`, `~/GEMINI.md`, or `~/.codex/`.
  `sync.sh` owns them and overwrites on the next pull. Always edit source here.
- **bash 3.2 compatible** — macOS ships 3.2 and both `install.sh` and `sync.sh` hard-check it.
  No associative arrays, no `${var,,}`. The empty-array-safe `"${arr[@]+"${arr[@]}"}"` idiom
  is used throughout for this reason.
- **Wire a new skill's routing entry before syncing.** `sync.sh` aborts if any `skills/*/`
  is missing from `hooks/craftkit-routing.js`.
- Shell commands in this environment are prefixed with `rtk` (a token-filtering proxy):
  `rtk git status`, `rtk tsc`.
