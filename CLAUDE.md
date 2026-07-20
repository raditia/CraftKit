# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

CraftKit (`@raditia/craftkit`) is the **source of truth** for AI coding skills, rules, commands, and agents that get synced into six AI tools: Claude Code, Cursor, GitHub Copilot, Gemini CLI, Codex CLI, and Crush. It contains no application code and no test suite — the "product" is the content in `rules/`, `skills/`, `commands/`, `agents/` plus the bash machinery that distributes it.

You will be running here under the very rules this repo defines (they are installed into `~/.claude/CLAUDE.md`). Editing source files here changes future behavior for every synced tool.

## Commands

```bash
bash install.sh        # git-clone install: wires post-merge hook + runs first sync (ensure_tools)
bash sync.sh           # distribute rules/skills/commands/agents into all 6 tools (idempotent)
AGENTIC_SETUP=1 bash sync.sh   # also run ensure_tools (installs/updates rtk, wires hooks) — what install/postinstall use
```

There is no build, lint, or test step. Verification = run `sync.sh` and confirm `Sync complete.` with no errors, and that the `[adapter]` sections report `(up to date)` or the expected `+ installing` lines.

Release: bump `version` in `package.json` + `# craftkit \`vX.Y.Z\`` header in README + add a changelog row. Pushing to `main` triggers `.github/workflows/release.yml` to publish the npm package and create the GitHub release.

## Architecture: how distribution works

The whole system is a **fan-out from four content directories into per-tool destinations**, driven by `sync.sh` + one adapter per tool.

### Content directories (what you edit)

| Dir | Loaded by AI | Invoked | Format |
|-----|--------------|---------|--------|
| `rules/*.md` | Every session, always-on | Never | frontmatter + body |
| `skills/<name>/SKILL.md` | On demand | `/<name>` or natural language | `alwaysApply` flag in frontmatter decides rule vs command |
| `commands/*.md` | On demand | `/<name>` or natural language | orchestrator workflows that spawn agents |
| `agents/*.md` | Spawned by commands | `subagent_type:` in a command | cold sub-agent: frontmatter (name, description, tools, model) + system prompt |

A `skills/<name>/SKILL.md` with `alwaysApply: true` is treated as a **rule** by the Claude adapter (goes into the managed CLAUDE.md block), not a slash command. That's why some "skills" behave like always-on rules.

### sync.sh — the engine

`sync.sh` sources all six `adapters/*.sh`, then for each adapter runs four sync passes: `sync_rules_adapter`, `sync_adapter` (skills), `sync_commands_adapter`, and `sync_agents_adapter` (only if the adapter defines `install_<adapter>_agent`). Each pass:

1. Reads prior state from `~/.craftkit-state/<adapter>[-rules|-agents|-commands]` (one name per line).
2. **Removes** anything in state but no longer in the repo (handles deletions/renames).
3. **Installs/updates** current items, diffing source against dest to skip unchanged files.
4. Rewrites the state file.

This state-file diff is why deleting a source file auto-uninstalls it everywhere on next sync — the removal loop catches the orphan. If you rename a file, the old name is removed and the new one installed.

After all adapters, `finalize_<adapter>` runs if defined (Claude uses it to rebuild a missing managed block and wire the routing hook), then `sync_copilot_projects` re-runs per-project Copilot agent setup for any registered project.

### Adapters — the contract

Each `adapters/<tool>.sh` implements a fixed set of function names that `sync.sh` calls by string interpolation (`"install_${adapter}_skill"`). To add a tool, implement: `get_<a>_dest`, `install_<a>_skill`, `uninstall_<a>_skill`, and the `_rule` / `_command` / `_agent` variants, plus an optional `finalize_<a>`. Add the tool name to the `ADAPTERS` array.

**Managed-block pattern (Claude, Gemini, Codex, Crush):** rules are concatenated into a delimited block (`<!-- BEGIN AGENTIC-SKILLS ... END -->`) inside a shared file like `~/.claude/CLAUDE.md`, edited in place with a Python regex sub. Everything outside the markers is the user's own content and must be preserved. `claude.sh:_rebuild_claude_md` / `_remove_claude_md_section` are the reference implementation.

**Claude specifics (`adapters/claude.sh`):**
- Rules → managed block in `~/.claude/CLAUDE.md`. Commands → `~/.claude/commands/<name>.md`. Agents → `~/.claude/agents/<name>.md`.
- A skill that flips between rule and command (via `alwaysApply`) is migrated: installing as a rule removes the stale command file and vice-versa.
- `install_claude_craftkit_hook` copies `hooks/craftkit-routing.js` to `~/.claude/hooks/` and registers it as a `UserPromptSubmit` hook in `~/.claude/settings.json` (idempotent — checks for `craftkit-routing` substring before appending).

### Routing hook

`hooks/craftkit-routing.js` is a `UserPromptSubmit` hook that injects the skill-first routing gate as `additionalContext` on **every** prompt. It is what forces the "classify intent → announce `/skill` or `No skill matched` → invoke" behavior you see each turn. The hook text duplicates the routing table from `rules/using-agent-skills.md` — if you change routing rules, update both.

## EVPMR — the domain the skills enforce

The frontend skills/agents all operate on a 5-file-per-feature architecture. `rules/fe-rules.md` enforces it always-on; this is content the skills act on, not how this repo itself is structured.

```
EntryFeature.tsx    ErrorBoundary + providers (boundary only)
ViewFeature.tsx     pure render — calls usePresenter*, NEVER useState/useEffect/API
PresenterFeature.ts all hooks/state/React Query — returns plain object, NEVER JSX
ModelFeature.ts     types + pure functions — NEVER imports React
ResourceFeature.ts  all display strings
```

## Critical authoring rules

These live in `rules/using-agent-skills.md` (the "Skill authoring rules" section) and apply to **every** add/update/remove in this repo:

1. **Conflict check first.** Scan `rules/`, `skills/`, `commands/`, `agents/` for duplicate concepts, duplicate slash commands, or contradicting rules before writing. Surface conflicts — never silently merge.
2. **Token audit.** Every line must earn its place. Content already in an always-active rule must not be repeated in a skill — reference it instead.
3. **README sync is mandatory.** Adding/removing/renaming any rule, skill, command, or agent requires updating the matching table in `README.md` in the same change. Renaming an agent also means updating every `subagent_type:` reference in `commands/`.
4. **Agents are cold copies.** Agent system prompts don't inherit `rules/`. If an agent duplicates rule content (e.g. EVPMR constraints), updating the rule means manually updating the agent file too.
5. **Skill naming = implicit namespace.** The skill's directory basename *is* its slash command (`skills/think/` → `/think`), so the name carries the grouping — there are no subfolders (see Conventions). Platform-scoped skills are prefixed with their platform (`fe-*`, `android-*`, `ios-*`); a **cross-cutting / general skill takes no prefix** (`code-quality`, `debug`, `ideate`, `think`, `ponytail-*`). Pick the name by this rule: platform work → prefix it; general reasoning/quality skill → bare name.

## Conventions that bite

- **Never edit installed files** in `~/.claude/`, `~/.cursor/`, VS Code settings, etc. — `sync.sh` owns them and overwrites on next pull. Always edit source here.
- **`skills/` is flat — one level, no subfolders.** The engine globs `skills/*/` exactly one deep and uses `basename` as the skill name; nesting (`skills/group/name/`) breaks both. Grouping is carried by the name prefix (authoring rule #5), not directories. `sync.sh` also runs a **routing drift guard** at startup: every `skills/*/` must be named in `hooks/craftkit-routing.js` or the sync aborts — so wire a new skill's routing entry before syncing.
- **bash 3.2 compatible** (macOS default). Both `install.sh` and `sync.sh` hard-check the version. Avoid bash 4+ features (associative arrays, `${var,,}`, etc.). The empty-array-safe idiom `"${arr[@]+"${arr[@]}"}"` is used throughout for this reason.
- **`ensure_tools` is interactive** (patches shell profile via `rtk init`). It only runs when `AGENTIC_SETUP=1`, never from the plain post-merge hook path — don't move it out of that guard.
- Commands are prefixed with `rtk` in this environment (token-filtering proxy): `rtk git status`, `rtk tsc`, etc.
