# anti-slop (miqdadbadjuber/anti-slop): what it ships, how it installs, what it touches

Research date: **2026-09-17**. Primary sources only: the repository's own files, read from a shallow clone pinned at `743735248fbaefd76bb56619615687dfa8b3bc1e` (2026-09-16), plus the GitHub REST API for repository metadata. No blog post, write-up, or third-party summary was consulted. Every claim below cites either a `path:line` inside that clone or the API URL it came from.

**Verbatim-quoting caveat.** Upstream separates a rule id from its title with an em dash character (`R-02`, then that character, then `Copywriting`). This repo's `check.sh` check 19 greps `docs/` for that byte and exempts only `CHANGELOG` and `CRAFTKIT-INJECTED-RULES` lines, so reproducing it here would fail the gate. Rule titles below render the separator as a plain space. That is the single normalization applied to any quoted text in this note; everything else is byte-exact.

## Answer

- **It is a prose rule-set, not machinery.** Six skills in the open Agent Skills layout (`<name>/SKILL.md`), one 50 KB core, four plugin manifests, and a small interactive npm installer. **Zero hooks of any kind**, and nothing that edits `~/.claude/settings.json` (grep across every tracked text file returns no match for `settings.json`, `"hooks"`, or any hook event name).
- **One thing does auto-run, and only on the Claude Code plugin route:** `.claude-plugin/plugin.json:13-19` registers an MCP server that launches `node .claude-plugin/contrast-mcp-launcher.mjs`, which spawns `python3` on a WCAG contrast server. The npm and skills-directory routes register nothing.
- **MIT, attribution required**, standard clause: the copyright notice must be included in all copies or substantial portions (`LICENSE:12-13`).
- **Six-agent target, not Claude-only.** Claude Code, Codex, Antigravity, OpenCode, Cursor, Gemini CLI, and Hermes, each with its own skills directory (`cli/lib/install.mjs:12-23`).
- **Overlap with craftkit is narrow but real and concentrated in one place:** `antislop-code` is a comment-hygiene rule-set that covers nearly the same ground as the `narrate:` tag in `karpathy-guidelines`, and the core's R-02 forbids em dashes in text, which is this repo's own check 19. Everything else it ships (UI, color, copywriting, contrast, responsive layout) is territory craftkit does not enter.

---

## 1. What it contains

46 tracked files. Full listing, classified, with byte size as reported by `git ls-files` plus `wc -c` on the pinned clone:

| Path | Bytes | Class |
|---|---|---|
| `antislop.md` | 50012 | **prompt / rule** (the core filter, 38 rules) |
| `skills/antislop/SKILL.md` | 50184 | **skill** (generated from `antislop.md`) |
| `skills/antislop-ui/SKILL.md` | 26844 | **skill** |
| `skills/antislop-copywriting/SKILL.md` | 25175 | **skill** |
| `skills/antislop-layoutmobile/SKILL.md` | 16378 | **skill** |
| `skills/antislop-human/SKILL.md` | 11051 | **skill** |
| `skills/antislop-code/SKILL.md` | 8944 | **skill** |
| `skills/antislop-human/contrast-check.py` | 5589 | **script** (Python CLI, WCAG contrast) |
| `skills/antislop-human/contrast-mcp.py` | 3627 | **script** (Python MCP stdio server) |
| `rules/antislop.md` | 804 | **rule** (always-on pointer, plain) |
| `rules/antislop.mdc` | 948 | **rule** (Cursor `.mdc`, `alwaysApply: true`) |
| `plugin.json` | 25 | **config** (name only) |
| `.claude-plugin/plugin.json` | 644 | **config** (Claude plugin + MCP server) |
| `.claude-plugin/marketplace.json` | 403 | **config** (Claude marketplace) |
| `.claude-plugin/contrast-mcp-launcher.mjs` | 1190 | **script** (Node, picks a Python and spawns it) |
| `.cursor-plugin/plugin.json` | 611 | **config** |
| `.cursor-plugin/marketplace.json` | 403 | **config** |
| `.codex-plugin/plugin.json` | 1091 | **config** |
| `.agents/plugins/marketplace.json` | 307 | **config** (Antigravity) |
| `cli/index.mjs` | 5426 | **script** (interactive installer entrypoint) |
| `cli/lib/install.mjs` | 7908 | **script** (copy + pointer-write logic) |
| `cli/lib/banner.mjs` | 1946 | **script** (ASCII banner) |
| `cli/package.json` | 901 | **config** (npm package `antislop-ai`) |
| `cli/package-lock.json` | 3064 | **config** |
| `cli/scripts/smoke-test.mjs` | 2837 | **script** (test harness) |
| `cli/scripts/smoke-worker.mjs` | 9607 | **script** (test assertions) |
| `cli/scripts/sync-skills.mjs` | 1384 | **script** (regenerates core SKILL.md) |
| `scripts/check-repo.mjs` | 10083 | **script** (repo guardrails, CI) |
| `.github/workflows/ci.yml` | 1377 | **config** (CI) |
| `README.md` | 13690 | **docs** |
| `GUIDE.md` | 21604 | **docs** |
| `ROADMAP.md` | 15067 | **docs** |
| `SECURITY.md` | 3476 | **docs** |
| `LICENSE` | 1072 | **docs** |
| `.gitignore`, `cli/.gitignore` | 183, 22 | **config** |
| `assets/*.png`, `assets/compare/**/*.webp` | 10 files | **docs** (README imagery) |

**No cold agents. No commands. No hooks.** There is no `agents/`, no `commands/`, and no `hooks/` directory in the tree, and the grep in section 3 confirms no hook is registered anywhere.

## 2. Install mechanism

Six routes, all documented in `README.md:71-157`. Quoted exactly:

**Route 1, the installer (README calls it recommended), `README.md:79-81`:**

```bash
npx antislop-ai
```

**Route 2, the skills directory, `README.md:89-91`:**

```bash
npx skills add miqdadbadjuber/anti-slop
```

**Route 3, the Claude Code plugin, `README.md:99-102`:**

```text
/plugin marketplace add https://github.com/miqdadbadjuber/anti-slop
/plugin install antislop@anti-slop
```

**Route 4, Antigravity, `README.md:108-110`:**

```bash
agy plugin install https://github.com/miqdadbadjuber/anti-slop
```

**Route 5, Codex, `README.md:116-119`:**

```bash
codex plugin marketplace add miqdadbadjuber/anti-slop
codex plugin add antislop@anti-slop
```

**Route 6, Cursor, `README.md:125-127`:**

```bash
agent plugin marketplace add https://github.com/miqdadbadjuber/anti-slop
```

followed by a manual step: "Then open **Customize** in Cursor, find **antislop**, and select **Install**, choosing project or user scope." (`README.md:129`)

**Manual single file, `README.md:155-157`:**

```bash
curl -o antislop.md https://raw.githubusercontent.com/miqdadbadjuber/anti-slop/main/antislop.md
```

So: **all of the above**. It is simultaneously an npm installer, a Claude Code plugin + marketplace, a Cursor plugin + marketplace, a Codex plugin + marketplace, an Antigravity plugin, a skills.sh listing, and a paste-in-chat Markdown file. It is not a git clone plus sync model like craftkit; the installer is published to npm as `antislop-ai` (`cli/package.json:2`) and copies bundled folders.

## 3. Does it write outside the repo?

**Yes, but only skill folders and one Markdown pointer. It never touches `~/.claude/settings.json` and registers no hooks.**

Negative evidence first. Grepping every tracked non-binary file for hook and settings surfaces returns nothing:

```
grep -nIE 'settings\.json|"hooks"|hooks/|UserPromptSubmit|SessionStart|PreToolUse|PostToolUse|SubagentStart|postinstall|preinstall'
  -> (no matches)
```

The only mention of `~/.claude` in the whole repo is descriptive, in the docs, about Claude Code's own plugin cache: "Claude Code keeps its own copy of the plugin under `~/.claude/plugins/cache/`" (`GUIDE.md:262`). That is the tool's behavior, not a write the repo performs.

What it does write:

| What | Where | File and line |
|---|---|---|
| Skill folders, recursive copy | `<cwd>/.claude/skills/`, `.codex/skills/`, `.agents/skills/`, `.opencode/skills/`, `.cursor/skills/`, `.gemini/skills/`, `.hermes/skills/` | `cli/lib/install.mjs:12-23` (the `AGENTS` table), copied by `installSkills` at `cli/lib/install.mjs:81-97` via `copyDir` at `:68-79` |
| The same, under `$HOME`, on a global install | `os.homedir()` joined with the same relative dir, except OpenCode to `~/.config/opencode/skills` and Antigravity to `~/.gemini/config/skills` | `resolveBase` at `cli/lib/install.mjs:33-35`, `skillPath` at `:38-41`, `globalDir` overrides at `:15,18` |
| A managed pointer block in the agent's entry file (`CLAUDE.md`, `AGENTS.md`, or `GEMINI.md`) | **always `process.cwd()`**, never `$HOME` | `updatePointers` at `cli/lib/install.mjs:194-208`, specifically `path.join(process.cwd(), name)` at `:203`; written by `writeBlock` at `:160-192` |

Two details worth noting on the pointer write, because they are the destructive-risk surface:

- It is **delimited and idempotent**, using `<!-- antislop:start -->` / `<!-- antislop:end -->` (`cli/lib/install.mjs:99-100`), the same managed-block pattern craftkit uses. `writeBlock` replaces a paired block in place and otherwise appends (`:168-177`).
- It is **only called on a project install**: `const pointers = location === 'project' ? updatePointers(...) : []` (`cli/index.mjs:120`). A global install writes skill folders under `$HOME` but no pointer, which matches the README's claim that "a global install relies on the skills loading themselves by description" (`README.md:77`).

`copyDir` opens with `fs.rmSync(dest, { recursive: true, force: true })` (`cli/lib/install.mjs:69`), so an overwrite replaces a skill folder wholesale rather than merging. The installer gates that behind an explicit prompt (`cli/index.mjs:99-109`) and skips existing folders unless the user chose overwrite (`cli/lib/install.mjs:91`).

## 4. License

**MIT License**, `LICENSE:1`, "Copyright (c) 2026 Miqdad Badjuber" (`LICENSE:3`). Confirmed independently by the API: `license.spdx_id` is `"MIT"` (https://api.github.com/repos/miqdadbadjuber/anti-slop).

**Attribution is required for derivative and adapted content.** The operative sentence, verbatim (`LICENSE:12-13`):

> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

Modification and redistribution are expressly granted ("to use, copy, modify, merge, publish, distribute, sublicense, and/or sell", `LICENSE:8`), so adapting content into craftkit is permitted provided the notice travels with it. This is the same obligation craftkit already discharges for other MIT sources via its "Adapted from `<owner>/<repo>` (MIT)" convention in skill descriptions.

## 5. Target tool

**Not Claude-only.** Seven agents are targeted, each with its own skills path and entry file, from the installer's `AGENTS` table (`cli/lib/install.mjs:12-23`):

| Agent | Skills dir (project) | Entry file for the pointer |
|---|---|---|
| Claude Code | `.claude/skills` | `CLAUDE.md` |
| Antigravity | `.agents/skills` (global `.gemini/config/skills`) | `AGENTS.md` |
| Codex | `.codex/skills` | `AGENTS.md` |
| OpenCode | `.opencode/skills` (global `.config/opencode/skills`) | `AGENTS.md` |
| Cursor | `.cursor/skills` | `AGENTS.md` |
| Gemini CLI | `.gemini/skills` | `GEMINI.md` |
| Hermes | `.hermes/skills` | `AGENTS.md` |

The README adds that the Gemini CLI row is legacy: "Antigravity replaced it, but the installer still writes there for existing setups" (`README.md:145`), and that Hermes needs `hermes skills trust` once per project (`README.md:149`, warned at `cli/index.mjs:140-142`).

Dedicated plugin manifests exist for four of them: `.claude-plugin/`, `.cursor-plugin/`, `.codex-plugin/`, `.agents/plugins/`. Only the Cursor manifest ships `rules` alongside `skills` (`.cursor-plugin/plugin.json:15-16`); only the Claude manifest ships an MCP server (`.claude-plugin/plugin.json:13-19`).

## 6. Content shape

Frontmatter is minimal and uniform. All six skills use exactly three fields: `name`, `description`, `allowed-tools`. No `model`, no `platform`, no injection mechanism. Verbatim, the core (`skills/antislop/SKILL.md:1-5`):

```yaml
---
name: antislop
description: "Anti Slop: Rules for AI Coding Agents. The core filter. Load always to stop generic AI slop."
allowed-tools: Read Write Edit Glob Grep
---
```

`antislop-human` is the only one that widens tool access, because it shells out to the contrast checker (`skills/antislop-human/SKILL.md:1-5`):

```yaml
---
name: antislop-human
description: "Human and accessibility skill for antislop. Contrast, keyboard, focus, and states for real people. Includes the contrast checker."
allowed-tools: Bash(python *) Bash(python3 *) Read Write Edit Glob Grep
---
```

And `antislop-code`, the one most relevant to craftkit (`skills/antislop-code/SKILL.md:1-5`):

```yaml
---
name: antislop-code
description: "Code comment hygiene for AI coding agents: remove generic AI-slop comments, keep the valuable ones, never touch the code."
allowed-tools: Read Write Edit Glob Grep
---
```

**Descriptions are load triggers**, phrased as such: four of the six end with an explicit instruction to the router, either "Load with the core." (`antislop-ui`, `antislop-copywriting`, `antislop-layoutmobile`) or "Load always" (`antislop`). Three front-load a "Use when" clause, for example "Use when writing or editing prose: headlines, tone, CTAs, and anti-AI-writing patterns." (`skills/antislop-copywriting/SKILL.md:3`).

**Bodies are long.** Lines and bytes per skill: core 685 lines / 50184 B, copywriting 372 / 25175, ui 311 / 26844, layoutmobile 170 / 16378, human 147 / 11051, code 128 / 8944. The core alone is roughly 50 KB, which the installer's own comment flags as a cost: "an `@` import pulls all 46 KB of it into every session, including ones that touch no UI" (`cli/lib/install.mjs:111-112`), which is why the pointer names skills rather than importing the core.

The core's body structure (`antislop.md`, headings at `:1-680`): a First-Run Install Wizard (`:11`), Two Usage Modes (`:60`), What This Is and What It Isn't (`:75`), Core Principle (`:95`), a five-item Craftsmanship Standard `C-1` to `C-5` (`:110-130`), Part 1 AI Slop Patterns in seven categories (`:136-221`), Part 2 the 38 mandatory rules in three tiers (`:230-543`), and Part 3 a Liveliness Toolkit with three dials (`:544-548`).

Each rule is a `####` heading plus a bullet list of `FORBIDDEN` / `REQUIRED` clauses. Verbatim, the em-dash rule (`antislop.md:238-244`, separator normalized per the caveat above):

```markdown
#### R-02  Copywriting

- **FORBIDDEN**: em dash character (the U+2014 byte, elided here per the caveat) in any text
- Use comma (`,`), period (`.`), colon (`:`), or parentheses `()` instead
- Text must feel natural and human
- **Carve-out**: documentation of this rule is exempt: ...
```

The per-skill entries use a fixed three-part shape, stated in `skills/antislop-code/SKILL.md:13`: "Every entry has the same shape: **Tell** (the pattern), **Why** (why it reads as slop), **Fix** (what to do instead), with the governing core rule cited as R-XX." Example (`skills/antislop-code/SKILL.md:24-27`):

```markdown
### Restating the Obvious

- **Tell:** a comment that repeats what the next line or declaration already shows, like `// Initialize the variable` above `let count = 0`, ...
- **Why:** it doubles the reading load without adding anything. The code already says it; the comment just repeats it.
- **Fix:** remove and leave the line of code alone.
```

Skills reference the core by rule number and do not restate it, per `README.md:218`: "It references the core rules by number and never duplicates them". That is the same token discipline as craftkit's authoring rule 2.

## 7. Overlap signal: everything it ships, by name

**Skills (6):** `antislop`, `antislop-ui`, `antislop-copywriting`, `antislop-human`, `antislop-layoutmobile`, `antislop-code`. Versions per `README.md:163-168`: core v3.0.0, ui v2.2.0, copywriting v2.3.0, human v2.4.0, layoutmobile v2.5.0, code v3.1.0. Package version is 3.2.9 (`.claude-plugin/plugin.json:4`).

**Rules (2):** `rules/antislop.md`, `rules/antislop.mdc`. Both are the same ~12-line always-on pointer; the `.mdc` adds Cursor frontmatter `globs: **/*` and `alwaysApply: true` (`rules/antislop.mdc:1-5`).

**Commands: none. Cold agents: none. Hooks: none.**

**MCP server (1):** `antislop-contrast`, exposing one tool `check_contrast` (`skills/antislop-human/contrast-mcp.py:14-15`).

**The 38 core rule ids and titles** (`antislop.md`, in file order within each tier; separator normalized):

- *Group 1, Hard Gate, absolute* (`:234`): R-02 Copywriting, R-03 Mobile Responsiveness, R-17 Data & Numbers, R-18 Testimonials, R-23 Clarification & Visual Assets, R-24 Navigation, R-25 Color Contrast, R-26 Interactive Elements, R-27 UI States, R-28 FAQ, R-32 Keyboard Accessibility, R-33 No File/CSS Patching via Scripts, R-34 Every Theme You Ship Must Work, R-35 Verify Before You Deliver, R-36 No Fabricated Claims, R-37 Design Direction Required, R-38 Real Content or Honest Placeholder.
- *Group 2, Purpose-Gate, technique allowed with a written reason* (`:388`): R-01 Color & Gradients, R-04 Icons, R-06 Typography, R-07 Background, R-08 Button Arrows, R-09 Badges, R-10 Glassmorphism, R-12 Shadow, R-13 Glow, R-14 Feature Cards, R-19 Animations, R-22 Illustrations.
- *Group 3, Quality Locks, consistency* (`:462`): R-05 Layout & Page Structure, R-11 Border Radius, R-15 CTA (Call to Action), R-16 Copywriting & Buzzwords, R-20 Visual Identity, R-21 Dark Mode, R-29 Color Palette, R-30 Do Not Clone Popular Products, R-31 Every Decision Must Have a Reason (Write It Down).

**Where this collides with craftkit**, for the caller's diff:

| anti-slop | craftkit counterpart | Relationship |
|---|---|---|
| `antislop-code` (comment hygiene: decorative separators, restating the obvious, workflow narration, empty labels, vague placeholders, signature echo, decorative emoji) | the `narrate:` tag and the comment-discipline block in `karpathy-guidelines` rule 2 | **Near-duplicate scope.** anti-slop is far more granular (seven named patterns with Tell/Why/Fix); craftkit's is a compressed always-on list. Both ban section banners, step numbers, restatement, and JSDoc that echoes the signature. |
| R-02 (em dash forbidden in any text) | `check.sh` check 19 | **Same rule, different enforcement.** craftkit gates it mechanically in CI; anti-slop states it as a prose rule with a documentation carve-out. |
| R-31 (every decision must have a written reason) | `ponytail:` markers, `/adr` | Adjacent, not duplicate. |
| R-35 (verify before you deliver), the Delivery Gate PASS/FAIL report | core behavior 6, the `Stop` verification hook | Same intent, craftkit enforces via hook. |
| `antislop-human` (contrast, keyboard, focus, states) | `fe-a11y`, `android-a11y`, `ios-a11y` | Overlapping concern, but anti-slop is platform-agnostic and ships a real WCAG calculator, which craftkit's a11y skills do not. |
| `antislop-ui`, `antislop-copywriting`, `antislop-layoutmobile` | nothing | **No craftkit counterpart.** Visual design, prose quality, and responsive layout are outside craftkit's scope. |
| `humanizer` skill (installed in this environment, from the Wikipedia AI-writing guide) | `antislop-copywriting` | **Strong overlap**, both target AI-writing tells in prose, including em dash overuse. |

## 8. Executable code

Five Node scripts, two Python scripts. None is a hook. None runs on `npm install` (`cli/package.json:32-36` defines only `test`, `sync-skills`, and `prepublishOnly`; there is no `postinstall` or `preinstall`, confirmed by the grep in section 3).

| File | What it does | Runs automatically? |
|---|---|---|
| `cli/index.mjs` | Interactive installer: prompts for skills, project-or-global, and which agents, then copies folders and writes the pointer. | Only when the user runs `npx antislop-ai`. Refuses to run headless: exits 1 if `!process.stdin.isTTY` (`cli/index.mjs:44-47`). |
| `cli/lib/install.mjs` | The copy and pointer-write logic behind the above. Pure filesystem, no network, no child processes. | Imported by the installer only. |
| `cli/lib/banner.mjs` | Prints the ASCII banner. | Imported by the installer only. |
| `.claude-plugin/contrast-mcp-launcher.mjs` | Probes for a working Python (`spawnSync(bin, ["-c", ""])` at `:17-19`), then `spawn`s `contrast-mcp.py` with `stdio: "inherit"` (`:30`). | **Yes, flag this.** Registered as an MCP server in `.claude-plugin/plugin.json:13-19`, so installing the Claude Code plugin means Claude Code starts this Node process, which starts a Python process, every session. It is the one thing in the repo that executes without the user invoking it. |
| `skills/antislop-human/contrast-mcp.py` | Minimal MCP stdio server exposing one tool, `check_contrast`, over JSON-RPC. Imports only `json` and `sys` (`:6-7`). No network, no subprocess, no `eval`. | Only as the child of the launcher above. |
| `skills/antislop-human/contrast-check.py` | WCAG 2.x contrast CLI: prints a ratio and PASS/FAIL against 4.5:1 and 3:1, exit 0 only when both pass. `--selftest` reparses the reference table out of the adjacent `SKILL.md` and recomputes every row. Imports only `os`, `re`, `sys` (`:18-20`). | No. Invoked by the agent through the `Bash(python3 *)` grant in `skills/antislop-human/SKILL.md:4`, and by CI (`.github/workflows/ci.yml:29`). |
| `cli/scripts/sync-skills.mjs` | Regenerates `skills/antislop/SKILL.md` by prepending fixed frontmatter to `antislop.md` (`:28`), then mirrors `skills/` into `cli/skills/` minus `__pycache__` (`:31-35`). Refuses to sync if the core contains a `raw.githubusercontent.com` URL, citing "Snyk W012: a shipped skill must not tell the agent to download its own instructions" (`:23-26`). | Author-side only: `prepublishOnly` (`cli/package.json:35`) and CI (`.github/workflows/ci.yml:35`). |
| `cli/scripts/smoke-test.mjs`, `cli/scripts/smoke-worker.mjs` | Installer test harness: spawns the worker against a temp dir and asserts on resolved target paths and pointer-block edits. | CI only (`.github/workflows/ci.yml:46`). |
| `scripts/check-repo.mjs` | The repo's own content gate, described in its header as "The rules antislop applies to other people's repos, applied to this one." Functions include `emDashes()`, `gateCoverage()`, `skillReferences()`, `versions()`. | CI only (`.github/workflows/ci.yml:25`). Structurally the counterpart of craftkit's `check.sh`. |

**Security posture, from primary sources.** The two Python files import nothing beyond `json`, `sys`, `os`, `re`; a grep for `subprocess`, `os.system`, `eval(`, `exec(`, `urllib`, `requests`, and `socket` across both returns no match. The only child-process spawning in the repo is the MCP launcher's Python probe, and the only network reference is the documented `curl` line in the README. CI runs with `permissions: contents: read` (`.github/workflows/ci.yml:8-9`). `SECURITY.md` exists (3476 B) but was not needed for any claim above.

---

## Repository metadata

From https://api.github.com/repos/miqdadbadjuber/anti-slop, fetched 2026-09-17:

| Field | Value |
|---|---|
| `default_branch` | `main` (so no retry was needed) |
| `visibility` / `private` | `public` / `false` |
| `description` | "Rules for an AI coding agent to filter out generic AI-generated UI designs, text, and code." |
| `license.spdx_id` | `MIT` |
| `language` | `JavaScript` |
| `stargazers_count` | 2882 |
| `forks_count` | 188 |
| `created_at` | 2026-08-07 |
| `pushed_at` | 2026-09-16 |
| `archived` | `false` |
| `open_issues_count` | 2 |

Clone pinned at `743735248fbaefd76bb56619615687dfa8b3bc1e`, commit message "docs: shorten the three comparison captions in the...". No URL fetched in the course of this research returned 404, and the repository is neither private nor absent.
