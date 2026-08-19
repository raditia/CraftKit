# Self-updating model IDs for the non-Claude routing rows

Research date: **2026-08-19**. Primary sources only (`ai.google.dev`, `cloud.google.com`, `platform.openai.com`, `cursor.com/docs`, and the first-party `google-gemini/gemini-cli` + `openai/codex` repos). Claims that can only be sourced secondarily are marked **UNVERIFIED**.

## Answer

- **Gemini CLI — solved, and better than the API aliases.** Gemini CLI ships its *own* first-party alias layer (`auto`, `pro`, `flash`, `flash-lite`) that resolves at runtime against the CLI's shipped defaults plus the account's preview entitlement — structurally the same mechanism as Claude Code's `sonnet`/`opus`. Use these, not the API's `-latest` aliases. Proof they self-update: the CLI's `flash-lite` alias already resolves to `gemini-3.1-flash-lite` in source while the docs table still claims `gemini-2.5-flash-lite`.
- **Codex CLI — both current IDs are dead or dying, and no self-updating OpenAI coding/reasoning ID exists.** `codex-mini-latest` was retired **2026-02-12** (its `-latest` suffix was never a rolling alias — OpenAI classifies it as a snapshot); `o3` shuts down **2026-12-11**. OpenAI's undated aliases like `gpt-5.6` pin the *minor* version, so they still go stale. The one truly self-updating option is to **omit `model` entirely** and let Codex CLI's server-refreshed catalog pick the default, tiering by `model_reasoning_effort` instead.
- **Cursor — unmanageable by design.** No committable file selects a model. Cursor rules, skills, `.cursor/cli.json`, and `.cursor/environment.json` all lack a `model` field; model choice lives in the interactive picker, the *global* `~/.cursor/cli-config.json`, the `cursor-agent --model` flag, or the user/team account default. The row should stop pretending to be actionable.

---

## 1. Gemini

### The Gemini API does expose `-latest` aliases, with hot-swap semantics

The API documents four release channels. Verbatim, the Latest channel:

> "Points to the latest release for a specific model variation. This can be a stable, preview or experimental release. This alias will get hot-swapped with every new release of a specific model variation. For breaking changes, a 2-week notice will be provided through email before the version behind latest is changed. For example: `gemini-flash-latest`."

— https://ai.google.dev/gemini-api/docs/models

Contrast the Stable channel, verbatim: *"Points to a specific stable model. Stable models usually don't change. **Most production apps should use a specific stable model.** For example: `gemini-3.6-flash`."* (https://ai.google.dev/gemini-api/docs/models) — Google's own recommendation is *against* pointing production at a `-latest` alias.

**Which aliases exist today.** `gemini-flash-latest` and `gemini-pro-latest` are confirmed real by release-notes entries recording their hot-swaps (https://ai.google.dev/gemini-api/docs/changelog):

| Alias | Recorded swap | Date |
|---|---|---|
| `gemini-pro-latest` | → `gemini-3-pro-preview` | 2026-01-21 |
| `gemini-flash-latest` | → `gemini-3-flash-preview` | 2026-01-21 |
| `gemini-flash-latest` | → `gemini-3.5-flash` | 2026-05-19 |

`gemini-flash-lite-latest` appears in **no** primary source I could reach — not the models page, not the changelog. Treat it as non-existent unless verified against a live `models.list` call.

### Yes — the aliases cross major version boundaries on their own

This is the decisive risk finding. `gemini-flash-latest` moved from the 2.x family onto `gemini-3-flash-preview` on 2026-01-21 (https://ai.google.dev/gemini-api/docs/changelog). Two things follow:

1. A major-version jump happens with **no** action from the alias holder — exactly the maintenance win wanted, and exactly the behavioral risk.
2. The alias landed on a **preview** model, which the docs explicitly permit ("can be a stable, preview or experimental release"). Preview models carry *"more restrictive rate limits"* and *"will be deprecated with at least 2 weeks notice"* (https://ai.google.dev/gemini-api/docs/models). So an alias can silently move a workflow onto a rate-limited, deprecation-scheduled model.

A Google developer-blog snippet also states these aliases mean "rate limits, cost, and features available may fluctuate between releases," but the brief bars blog sources — **UNVERIFIED** as doc text, though the docs' own "stable, preview or experimental" wording establishes the same exposure independently.

Note the newest Pro is preview-only: the models page's Gemini 3 table lists `gemini-3.1-pro-preview` with no stable Gemini 3 Pro variant (https://ai.google.dev/gemini-api/docs/models). Any "newest Pro" pointer is therefore a pointer at a preview model today.

### Gemini CLI: accepts aliases, and has its own better ones

**The CLI defines a first-party alias set**, documented under Model selection — *"You can use either model aliases (user-friendly names) or concrete model names"* (`docs/cli/cli-reference.md`, https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/cli-reference.md):

| Alias | Docs say it resolves to | Description |
|---|---|---|
| `auto` | `gemini-2.5-pro` or `gemini-3-pro-preview` | **Default.** Preview model if preview features enabled, else standard pro |
| `pro` | `gemini-2.5-pro` or `gemini-3-pro-preview` | Complex reasoning |
| `flash` | `gemini-2.5-flash` | Fast, balanced |
| `flash-lite` | `gemini-2.5-flash-lite` | Fastest, simple tasks |

In source these are `GEMINI_MODEL_ALIAS_AUTO / _PRO / _FLASH / _FLASH_LITE` = `'auto' / 'pro' / 'flash' / 'flash-lite'`, resolved by `resolveModel()` (`packages/core/src/config/models.ts:110-113`, `:148-260`, https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/config/models.ts).

**The aliases demonstrably self-update, including across a major version.** The docs table above says `flash-lite` → `gemini-2.5-flash-lite`, but source now reads:

```ts
export const DEFAULT_GEMINI_FLASH_LITE_MODEL = 'gemini-3.1-flash-lite';
```

(`packages/core/src/config/models.ts:81`). The alias crossed 2.5 → 3.1 with the docs lagging behind — the alias target is a shipped CLI constant, so it advances on CLI upgrade with no config edit. Resolution is also **entitlement-aware**: `resolveModel()` downgrades preview targets to stable when `hasAccessToPreview` is false (`:238-257`), so `pro` yields the best Pro the account can actually reach. That is the Claude Code `sonnet`/`opus` property.

**All three input surfaces accept the same strings.** They converge on one line before resolution:

```ts
argv.model || process.env['GEMINI_MODEL'] || settings.model?.name;
```

(`packages/cli/src/config/config.ts:844`), matching the documented precedence — `--model` flag, then `GEMINI_MODEL` env, then `model.name` in `settings.json`, then the default, which *"is `auto`"* (`docs/cli/model-routing.md:44-59`). The `settings.json` key is `model.name`, "The Gemini model to use for conversations" (`docs/cli/settings.md:105`).

**No allowlist rejects an alias or an unknown ID.** Three independent confirmations:

1. `--model`/`-m` is declared `type: 'string'`, `nargs: 1` with **no `choices` array** (`packages/cli/src/config/config.ts:289-293`) — contrast `--output-format`, which does constrain choices.
2. The `settings.json` `model.name` property is `type: 'string'` with **no enum** (`packages/cli/src/config/settingsSchema.ts:1071-1076`).
3. `resolveModel()`'s `default:` branch is a passthrough — `resolved = normalizedModel` (`packages/core/src/config/models.ts:220-223`), and the docs confirm: *"If not found, the requested string is treated as the raw model name"* (`docs/cli/generation-settings.md:108`).

There **is** a `VALID_GEMINI_MODELS` set, but it does not gate input — it is referenced only in quota/fallback handling (`packages/cli/src/ui/hooks/useQuotaAndFallback.ts:177,188`). The `isActiveModel()` function that checks it has **no call sites outside its own definition file**. So `--model gemini-flash-latest` is passed through to the API unvalidated; it would work if and only if the API accepts it.

---

## 2. Codex CLI / OpenAI

### Both IDs currently in the table are dead or dying

**Source-domain note:** `platform.openai.com/docs/models` and `/docs/deprecations` now **301** to `developers.openai.com/api/docs/...`. Every OpenAI docs URL below is that redirect target — still first-party, reached via OpenAI's own redirect.

| ID in our table | Status | Evidence |
|---|---|---|
| `codex-mini-latest` | **RETIRED 2026-02-12** — dead ~6 months | https://developers.openai.com/api/docs/deprecations |
| `o3` | **DEPRECATED**, snapshot `o3-2025-04-16` shuts down **2026-12-11** (~4 months out) | https://developers.openai.com/api/docs/deprecations |

Verbatim on the first: *"On November 17th, 2025, we notified developers using `codex-mini-latest` model of its deprecation and removal from the API on February 12, 2026."* Documented replacement: `gpt-5-codex-mini` — which has itself since been superseded and now 404s (https://developers.openai.com/api/docs/models/gpt-5-codex-mini). Neither `codex-mini-latest` nor `o3` appears on the current models list (https://developers.openai.com/api/docs/models).

**Trap worth recording:** the per-model pages https://developers.openai.com/api/docs/models/o3 and `/models/codex-mini-latest` both still render **with no deprecation banner** — the o3 page only notes it is "succeeded by GPT-5". They are unmaintained legacy pages. The deprecations page plus absence from the models list are the authoritative lifecycle signals.

### `codex-mini-latest`'s `-latest` was not a self-updating alias

OpenAI's own deprecation heading classifies it as a **snapshot**: *"2025-11-17: codex-mini-latest model snapshot"* (https://developers.openai.com/api/docs/deprecations). Its model page lists `codex-mini-latest` as the sole entry in its own Snapshots section: the ID *is* the snapshot, with no dated build beneath it for a pointer to roll onto.

OpenAI's documented mechanism is undated alias → dated snapshot. Verbatim: *"Snapshots let you lock in a specific version of the model so that performance and behavior remain consistent"*, with dated snapshots `gpt-4o-2024-11-20`, `gpt-4o-2024-08-06`, `gpt-4o-2024-05-13` (https://developers.openai.com/api/docs/models/gpt-4o).

**Honest limit:** OpenAI never publishes an explicit *definition* of the `-latest` suffix on any reachable page — even `chatgpt-4o-latest`, its canonical rolling ID, carries no semantics text. So "genuine self-updating alias" cannot be positively confirmed or denied by direct definition. What *is* primary-sourced: OpenAI classifies `codex-mini-latest` as a snapshot and gives it no dated variant. Any stronger claim is **UNVERIFIED**. Moot regardless — the ID is retired.

**`-latest` IDs do still exist, but not for coding/reasoning:** `daybreak-red-latest` and `daybreak-blue-latest`, *"An alias for advanced cybersecurity models"* (https://developers.openai.com/api/docs/models).

**The current alias style is undated-but-minor-pinned.** Verbatim: *"The `gpt-5.6` alias routes requests to GPT-5.6 Sol"* (https://developers.openai.com/api/docs/models/gpt-5.6-sol). So `gpt-5.6` is a real alias — but it pins the **minor version**, so it goes stale at 5.7. That is the crux: **OpenAI exposes no fully self-updating ID for its coding/reasoning models.**

### What Codex CLI accepts — and the genuinely self-updating lever

Repo cloned at HEAD `6cc2ba8`, committed **2026-08-19** (same-day current).

**There is no `DEFAULT_MODEL` constant anymore — the default is server-driven.** A `codex-rs/models-manager` crate fetches a remote catalog, caches it (`models_cache.json`, TTL 300s), and falls back to a bundled `include_str!("../models.json")` (`codex-rs/models-manager/src/lib.rs:15`). Default resolution (`codex-rs/models-manager/src/manager.rs:597`):

```rust
fn default_model_from_available(available: Vec<ModelPreset>) -> String {
    available.iter().find(|model| model.is_default)
        .or_else(|| available.first())
```

`is_default` is assigned at runtime by picker visibility (`codex-rs/protocol/src/openai_models.rs:868`), not baked into the file. The bundled catalog holds 8 models in priority order — `gpt-5.6-sol` (1), `gpt-5.6-terra` (2), `gpt-5.6-luna` (3), `gpt-5.5` (7), `gpt-5.4` (16, hidden), `gpt-5.4-mini` (23, hidden), `gpt-5.2` (29), `codex-auto-review` (43, hidden) — none setting `is_default`, so the offline fallback resolves to top-priority visible: `gpt-5.6-sol`.

**This is the answer for Codex CLI: omit `model` entirely.** Leaving the key unset delegates to a catalog the CLI refreshes from the server every 300s — self-updating without naming any ID, and strictly better than any string we could pin.

**Free-form passthrough — nothing validates a model ID.**
- Config key `pub model: Option<String>` (`codex-rs/config/src/config_toml.rs:155`). The struct's `#[schemars(deny_unknown_fields)]` restricts unknown *keys*, not model *values*.
- Flag `#[arg(long, short = 'm')] pub model: Option<String>` (`codex-rs/utils/cli/src/shared_options.rs:22`) — plain `Option<String>`, no `value_parser`.
- With provider fallback **off** (the CLI/delegate path, `codex_delegate.rs:90`), the string passes through verbatim (`manager.rs:544`). With fallback **on** (app-server path), an ID absent from the catalog is *silently swapped* for the catalog default, logged `"replaced unavailable requested model with provider default"` (`codex-rs/core/src/session/mod.rs:629`).
- Hard proof: the repo's own fixtures still set retired IDs — `model = "o3"` (`codex-rs/core/src/config/config_tests.rs:9316`) and `"codex-mini-latest"` (`codex-rs/protocol/src/protocol.rs:5863`). Retired IDs parse fine. **A stale ID therefore fails at the API call or gets silently swapped — never at config-parse time**, which is exactly why the drift was invisible.

**`model_reasoning_effort` is the second self-updating lever** (`config_toml.rs:347`). Enum (`openai_models.rs:50`): `none, minimal, low, medium` (default), `high, xhigh, max, ultra`, plus `Custom(String)` — unknown strings are accepted, not rejected (`:143`); only empty errors. Per the bundled catalog, `ultra` is supported only by `gpt-5.6-sol` and `gpt-5.6-terra`. So tiers can be expressed as **effort on the unpinned default model** rather than as three model IDs.

Note `docs/config.md` is now a 726-byte stub linking to `developers.openai.com/codex/config-*`; the Rust source above is the only in-repo authority.

### Current OpenAI reasoning/coding IDs

All undated aliases; the docs list **no dated snapshots** for the GPT-5.6 family (https://developers.openai.com/api/docs/models):

- `gpt-5.6-sol` — frontier; `gpt-5.6` alias routes to it; default reasoning `low`; the documented replacement for `o3`
- `gpt-5.6-terra` (default `medium`), `gpt-5.6-luna` (default `medium`)
- `gpt-5.6-cyber`, `daybreak-red-latest`, `daybreak-blue-latest` — cybersecurity-specialized
- Older, still in the bundled catalog: `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.2`

The `codex-*` naming has been folded into the `gpt-5.x` line — the repo's migration table records `gpt-5-codex` → `gpt-5.1-codex-max`, `gpt-5-codex-mini` → `gpt-5.1-codex-mini`, `gpt-5` → `gpt-5.1` (`codex-rs/tui/src/model_migration.rs:435-526`). The only surviving `codex-`prefixed slug in the shipped catalog is the internal `codex-auto-review`.

---

## 3. Cursor

**There is no repo-committed model selector.** Every documented surface is an interactive picker, a per-user/global config, or a runtime flag.

| Surface | Has a `model` field? | Source |
|---|---|---|
| `.cursor/rules/*.mdc` frontmatter | No — only `description`, `globs`, `alwaysApply` | https://cursor.com/docs/rules |
| `.cursor/skills/*/SKILL.md` (commands were folded into Skills) | No — `name`, `description`, `paths`, `disable-model-invocation`, `metadata` | https://cursor.com/docs/skills |
| `.cursor/cli.json` (project) | No — *"Only permissions can be configured at the project level."* The `model` object exists only in global `~/.cursor/cli-config.json` | https://cursor.com/docs/cli/reference/configuration |
| `.cursor/environment.json` (Cloud Agents) | No `model` property at any level — confirmed against the first-party JSON schema | https://www.cursor.com/schemas/environment.schema.json |
| `.cursor/hooks.json` (is version-controlled) | Receives `model`/`model_id` as *input*; no documented way to set it | https://cursor.com/docs/hooks |

`disable-model-invocation` is a boolean about whether the agent may auto-invoke a skill — not a model selector.

**A CLI flag does exist:** `cursor-agent` documents `--model <model>` ("Model to use") and `--list-models`, plus interactive `/model [filter]` (https://cursor.com/docs/cli/reference/parameters, https://cursor.com/docs/cli/reference/slash-commands). No `MODEL` env var and no precedence rules are documented.

**Model IDs are runtime-discovered, and both alias and pinned forms coexist.** Cursor publishes no static slug table; the models page lists *display names* ("Grok 4.6", "Composer 2.5", Claude Opus 5 / Sonnet 5 / Fable 5), not API IDs (https://cursor.com/docs/models). Exact strings that do appear in primary docs: `auto`, `gpt-5`, `sonnet-4-thinking` (https://cursor.com/docs/cli/reference/configuration) and `composer-2`, `claude-4.6-sonnet-thinking` (https://cursor.com/docs/cloud-agent/api/endpoints). The canonical list is an endpoint, not a doc — `GET /v1/models` *"Returns the recommended models you can pass to the `model.id` field"*. Cloud-agent precedence, verbatim: *"When omitted, Cursor resolves your user default model, then your team default model, then a system default."*

**Auto mode is the self-updating option:** *"Auto has three modes: Auto Cost, Auto Balance, and Auto Intelligence"* (https://cursor.com/docs/models). Omitting a model entirely also resolves through the account default chain above.

The only committable lever is soft — prose ("use model X") inside a rule or skill body, which the agent may or may not honor. A `beforeSubmitPrompt` hook could *inspect* `model_id` and block, but overriding is not documented: **UNVERIFIED** inference, not a feature.

---

## 4. Recommended table

### Verdict per row

| Row | Self-updating ID available? | Verdict |
|---|---|---|
| Gemini CLI | **Yes** — the CLI's own `pro`/`flash`/`flash-lite` aliases | Adopt. Entitlement-aware, already the CLI's documented default mechanism. |
| Codex CLI | **Partly** — no self-updating *model ID* exists; the server-driven catalog default does | Stop naming a model. Express tiers as reasoning effort on the unset default. |
| Cursor | **No config surface at all** | Mark unmanageable. `auto` is the only self-updating lever, and only interactively. |

### Paste-ready rows

For `rules/using-agent-skills.md:424-426` (5-column form):

```
| Gemini CLI | `flash-lite` | `flash` | `pro` | 2× `pro` → `pro` judge |
| Cursor | not repo-configurable — `auto`, or the account default chain | `auto` | picker / `cursor-agent --model` | 2× escalate → same-tier judge |
| Codex CLI | omit `model`; `model_reasoning_effort = "low"` | omit `model`; effort `medium` (default) | omit `model`; effort `high` | 2× escalate → same-tier judge |
```

For `README.md:693-695` (4-column form, no Cheapest column):

```
| Gemini CLI | `flash` | `pro` | 2× `pro` → `pro` judge |
| Cursor | `auto` (not repo-configurable) | picker / `cursor-agent --model` | — |
| Codex CLI | omit `model`; effort `medium` | omit `model`; effort `high` | — |
```

For `commands/pr-message.md:7`, replace the cheapest-tier list `gemini-2.5-flash` · `gpt-4o-mini` · `codex-mini-latest` with:

```
`flash-lite` · Cursor `auto` · Codex default @ effort `low`
```

### Risk notes attached to these choices

- **Gemini CLI aliases will cross major versions silently** — `flash-lite` already moved 2.5 → 3.1 without a config edit. Accept it: that is the whole point, and the resolution is entitlement-aware so it cannot land on a model the account cannot call. Preferred over the API's `gemini-flash-latest`, which Google explicitly steers production away from and which can land on a *preview* model with restrictive rate limits.
- **Do not adopt `gemini-flash-latest` / `gemini-pro-latest`.** They work (the CLI passes unknown strings through unvalidated), but they can hot-swap onto preview or experimental builds by documented design, and Google's own guidance is that *"most production apps should use a specific stable model."* The CLI aliases give the same freshness with a stability floor.
- **`gpt-5.6` is a trap that looks like an alias.** It is undated, so it reads self-updating, but it pins the minor version and dies at 5.7 — the exact failure mode we are removing. Omitting the key entirely is the only OpenAI option that truly self-updates.
- **Reasoning effort is a weaker tier signal than a model swap.** All three Codex tiers resolve to the same model, differing only in effort. If tier separation by capability matters more than staleness-proofing, pin `gpt-5.6-luna` / `gpt-5.6-terra` / `gpt-5.6-sol` and accept a re-edit at 5.7. Recommendation: take the effort form — a wrong-but-live model beats a right-but-retired one.

---

## Open questions / staleness risk

- **The repo's own guard does not cover these rows.** `check.sh` check 17 greps only `claude-(haiku|sonnet|opus|fable)-[0-9]` across `rules/ skills/ commands/ agents/`. Gemini and OpenAI pinned IDs pass it untouched — which is precisely why `codex-mini-latest` sat in the table for ~6 months after retirement. **Recommended follow-up:** extend that regex (e.g. `gemini-[0-9]`, `gpt-[0-9]`, `\bo[0-9]\b`, `codex-mini`) once these rows are aliased, so the guard that keeps the Claude rows honest covers all four.
- **Blast radius is 3 files, not 1.** Stale IDs live at `rules/using-agent-skills.md:424-426`, `README.md:693-695`, and `commands/pr-message.md:7`. The README table omits the Cheapest column, so the two tables are not interchangeable.
- **`gemini-flash-lite-latest` is unconfirmed.** Absent from the models page and the changelog. Do not reference it without a live `models.list` check. (Immaterial to the recommendation, which uses the CLI alias.)
- **Gemini CLI's docs lag its source.** `docs/cli/cli-reference.md` still maps `flash-lite` → `gemini-2.5-flash-lite` while source says `gemini-3.1-flash-lite`, and the alias table still shows only 2.5/3-preview targets. The alias *names* are stable; their documented targets are not a reliable current statement.
- **OpenAI never defines `-latest` semantics anywhere reachable.** The strongest primary claim available is classification-by-heading ("snapshot") plus absence of a dated variant. A definitive answer on rolling behavior would need OpenAI to document the suffix, which it does not.
- **OpenAI's per-model pages are not lifecycle-maintained** — `/models/o3` and `/models/codex-mini-latest` render without deprecation banners. Always cross-check `/api/docs/deprecations` and the models list; a model page alone is not evidence a model is live.
- **Two Codex claims sit outside the allowed source set.** `developers.openai.com/codex/models` **308**s to `learn.chatgpt.com/docs/models` (OpenAI-operated but outside the brief's allowlist). Claims reached only there — that the Power default uses `gpt-5.6-sol` at medium reasoning, and that `gpt-5.4` models retire 2026-08-31 — are **UNVERIFIED** and excluded from the recommendation.
- **Cursor's `.cursor/commands/*.md` frontmatter has no live primary page.** Commands were folded into Skills; any claim about that file's fields is now secondary-only → **UNVERIFIED**.
- **Cursor's canonical model list is an endpoint, not a doc** (`GET /v1/models`). Any Cursor ID written into this repo is unverifiable from docs alone, reinforcing the "unmanageable" verdict.
- **Near-term recheck trigger:** `o3` shuts down **2026-12-11**. Any remaining `o3` reference must be gone before then. Gemini 3 has no stable Pro variant yet (`gemini-3.1-pro-preview` only) — worth a recheck when one ships, since `pro` will move onto it automatically.
