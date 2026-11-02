# Upstreams

Every external repo CraftKit adapts text from or integrates with, and the upstream commit it was last reconciled against. The baseline turns a drift check into an exact diff instead of a changelog read from memory.

## Adapted text

These repos' content was rewritten into CraftKit files. Licenses and attribution live in `LICENSE`.

| Upstream | Adapted into | Baseline | Reconciled | Baseline source |
|----------|--------------|----------|------------|-----------------|
| [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | `rules/karpathy-guidelines.md` (ponytail rubric), `skills/ponytail-{review,audit,debt}`, `agents/ponytail-review.md` | `16352ac229eb` (tag v5.3.2) | v1.60.0, 2026-10-19 | reconciled |
| [mattpocock/skills](https://github.com/mattpocock/skills) | `skills/{grill,research,handoff}`, CLAUDE.md "Writing levers" | `49dd158d1076` | v1.60.0, 2026-10-19 | reconciled |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | `skills/{adr,docs,interview,spec,plan}` | `aeac41d4d005` | v1.60.0, 2026-10-19 | reconciled |
| [addyosmani/clarity](https://github.com/addyosmani/clarity) | `skills/clarity` (SKILL.md + references condensed; lint script, evals and wrapper commands dropped) | `e27ceeff6036` | v1.62.0, 2026-10-27 | reconciled |
| [UditAkhourii/adhd](https://github.com/UditAkhourii/adhd) | `skills/ideate` | `7b91ce601ed9` | v1.60.0, 2026-10-19 | reconciled |
| [tjboudreaux/cc-thinking-skills](https://github.com/tjboudreaux/cc-thinking-skills) | `skills/think` | `7b8fece345df` | v1.60.0, 2026-10-19 | reconciled |
| [miqdadbadjuber/anti-slop](https://github.com/miqdadbadjuber/anti-slop) | `skills/fe-design` (from `antislop-ui`, `antislop-layoutmobile`) | `439a2ef5b9dd` | v1.60.0, 2026-10-19 | reconciled, pinned in `docs/research/anti-slop.md` |

"Last upstream commit on or before that date" baselines were derived after the fact, so a diff from them can include a change CraftKit already absorbed. Replace each with the exact SHA the next time that upstream is reconciled.

Pending decisions, deferred at v1.60.0:

- Ponytail v5 rewrote its rules and rebuilt `/ponytail-review` as a full review, which overlaps `/code-quality`.
- Ponytail v5.1 replaced the `ponytail:` marker with a neutral `shortcut:` marker.
- mattpocock's `to-questionnaire` skill.
- Re-verify `docs/research/codex-background-subagents.md` against codex 0.164 once it is stable.

## Integrations

These tools are installed or wired, not adapted. Drift here means a breaking change to an install command, hook format, or name CraftKit depends on.

| Upstream | Wired in | Version in use | Pinned? |
|----------|----------|----------------|---------|
| [rtk-ai/rtk](https://github.com/rtk-ai/rtk) | `sync.sh` `ensure_tools` (brew, or the install script from `master`; upstream default branch is now `develop`), `hooks/craftkit-read-cap.js` | 1.0.1 | No, installs latest |
| [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) | prose only (`rules/using-agent-skills.md`, `docs/guide.md`); CraftKit does not install it | 2.7.0 plugin; upstream 4.0.1 | User's plugin manager |
| [Graphify-Labs/graphify](https://github.com/Graphify-Labs/graphify) | `skills/debug`, `skills/fe-performance` (`graphify affected`); `adapters/claude.sh` guards the managed block against its marker removal | 0.9.70 | No |
| [blader/humanizer](https://github.com/blader/humanizer) | `sync.sh` clones `HEAD` once when the skill is absent and never updates it; used by `/pr-message` and `/docs` | 2.8.2 on this machine; upstream v3.1.0 renumbered its patterns, so CraftKit names them instead of citing numbers (v1.60.0) | No, first clone wins |
| [openai/codex](https://github.com/openai/codex) | `adapters/codex.sh` (hooks.json, agent TOML profiles), `hooks/craftkit-codex.js` | 0.163.0; `docs/research/codex-background-subagents.md` pins rust-v0.160.0 | No |
| [google-gemini/gemini-cli](https://github.com/google-gemini/gemini-cli) | `adapters/gemini.sh`; the model-routing table relies on its `pro`/`flash`/`flash-lite` aliases | not recorded | No |

Repos cited only in `docs/research/` notes (supermemory, larksuite) carry their own pins there and are not tracked here.

## Checking for drift

```bash
gh api repos/<owner>/<repo>/compare/<baseline>...HEAD \
  --jq '.files[].filename' | sort -u
```

Read only the changed files that map to a CraftKit file in the tables above. For each change, record a verdict: adopt, already covered, or decline, with a one-line reason.

## After reconciling

1. Add the verdicts to the release's `CHANGELOG.md` section, including what was declined and why.
2. Set the row's Baseline to the upstream SHA you diffed against, and Reconciled to the release.
3. A new upstream gets a row here and an entry in `LICENSE` in the same change.
