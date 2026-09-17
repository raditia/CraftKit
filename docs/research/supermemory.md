# supermemory (supermemoryai/supermemory): data residency and dependency shape

Research date: **2026-09-17**. Primary sources only: the repository's own files, read from a shallow clone pinned at `814f92731add938f542b3205763638e9cc33bf6a` (committed 2026-09-16), plus the GitHub REST API for repository and release metadata, the npm registry for published-package manifests, and the project's own docs source, which lives in this repo at `apps/docs/` and builds `supermemory.ai/docs`. One first-party non-repo artifact was fetched: `https://supermemory.ai/install`, the shell installer the README tells users to pipe into bash. No blog post, write-up, listicle, or third-party summary was consulted. Every claim below cites a `path:line` inside that clone, or the URL it came from.

**Verbatim-quoting caveat.** Upstream prose and one error-message string use the em dash character. This repo's `check.sh` check 19 greps `docs/` for that byte and exempts only `CHANGELOG` and `CRAFTKIT-INJECTED-RULES` lines, so reproducing it here would fail the gate. Every quote below renders it as a comma or parentheses. That is the single normalization applied; everything else inside quote marks is byte-exact.

## Answer

- **Data residency splits along a line that is not the line the README draws.** Every component whose source is actually in this repo is remote-first and defaults to `https://api.supermemory.ai`; the default is hardcoded in at least eight separate places (section 3). The one component that stores data locally, `supermemory-server` (writes to `./.supermemory`, serves `http://localhost:6767`), **is not in this repository.** It ships as a prebuilt 270 MB to 312 MB binary attached to this repo's GitHub Releases, and the tracked tree contains no source for it, no build script, no release workflow, and no submodule (section 5).
- **The "open source" claim for the local binary is circular.** `apps/docs/self-hosting/overview.mdx:20` says the binary is "open source" and links `https://git.new/memory`, which redirects to `github.com/Dhravya/supermemory`, then to `github.com/supermemoryai/supermemory`: this repo, which does not contain it. The self-hosted binary's behavior, including the telemetry claim at `configuration.mdx:121`, is therefore **not determinable from primary sources**.
- **A supermemory API key is required for every in-repo component, with no account-free mode.** `packages/tools/src/shared/context.ts:52-56` throws without `SUPERMEMORY_API_KEY`; the MCP worker rejects unauthenticated requests with 401 (`apps/mcp/src/server/index.ts:207`) and validates bearer tokens against `api.supermemory.ai`. The account-free mode exists only in the out-of-repo binary, which mints its own key on first boot.
- **Self-hosting requires no vector DB, no object storage, and no Cloudflare account, but does require one LLM provider key that is the user's own.** No `docker-compose.yml` and no `Dockerfile` exist anywhere in the tree. Embeddings default to a local model with no key (section 6).
- **MIT at the root, but three licenses across the tree**, and the client SDK that every wrapper depends on is Apache-2.0 in a different repo. No BSL, Elastic, Commons Clause, or "fair source" component anywhere (section 7).
- **No postinstall script in any of the 16 package manifests.** Nothing auto-registers into an editor or agent from this repo. The one auto-run surface is the `curl | bash` installer, which starts the server via `exec` when it has a TTY (section 9).

---

## 1. Repository metadata

From `https://api.github.com/repos/supermemoryai/supermemory`:

| Field | Value |
|---|---|
| `default_branch` | `main` |
| `license` | `{"key": "mit", "spdx_id": "MIT"}` |
| `archived` / `disabled` / `fork` | `False` / `False` / `False` |
| `visibility` | `public` |
| `stargazers_count` | 29778 |
| `forks_count` | 2611 |
| `open_issues_count` | 102 |
| `created_at` | `2024-02-27T20:10:04Z` |
| `pushed_at` | `2026-09-17T03:46:20Z` |
| `homepage` | `https://supermemory.ai/docs` |
| `language` | `TypeScript` |

API `description`, verbatim: *"Memory and context engine + app that is extremely fast, scalable, and can be run fully locally. The Memory API for the AI era."* Section 5 is the load-bearing qualifier on "run fully locally".

779 tracked files.

---

## 2. File listing, top two directory levels

Tracked files at the root (`git ls-files | grep -v /`):

```
.gitignore        CLAUDE.md         CONTRIBUTING.md   LICENSE
README.md         README.zh-CN.md   biome.json        bun.lock
package.json      portless.json     turbo.json
```

Second level, with tracked-file counts and a classification per the brief's question 1:

| Path | Files | Classification | Published as |
|---|---|---|---|
| `.github/workflows` | 12 | CI config | n/a |
| `apps/docs` | 252 | **docs site source** (Mintlify) | `supermemory.ai/docs` |
| `apps/mcp` | 115 | **MCP server** (Cloudflare Worker) | `mcp.supermemory.ai` |
| `apps/web` | 26 | **hosted SaaS console** (Next.js, private) | `console.supermemory.ai` |
| `apps/memory-graph-playground` | 18 | demo app (private) | n/a |
| `apps/sdk-playground` | 26 | demo app (private) | n/a |
| `apps/raycast-extension` | 15 | **desktop extension** (Raycast) | Raycast Store |
| `packages/tools` | 83 | **client SDK wrapper** | npm `@supermemory/tools` |
| `packages/ai-sdk` | 8 | **client SDK wrapper** (re-export shim) | npm `@supermemory/ai-sdk` |
| `packages/memory-graph` | 42 | **React viz component** | npm `@supermemory/memory-graph` |
| `packages/openai-sdk-python` | 14 | **client SDK wrapper** | PyPI `supermemory-openai-sdk` |
| `packages/agent-framework-python` | 17 | **client SDK wrapper** | PyPI `supermemory-agent-framework` |
| `packages/pipecat-sdk-python` | 9 | **client SDK wrapper** | PyPI `supermemory-pipecat` |
| `packages/cartesia-sdk-python` | 9 | **client SDK wrapper** | PyPI `supermemory-cartesia` |
| `packages/lib` | 16 | internal lib (private) | n/a |
| `packages/ui` | 69 | internal component lib (private) | n/a |
| `packages/hooks` | 7 | internal React hooks (private) | n/a |
| `packages/validation` | 5 | internal zod schemas (private) | n/a |
| `packages/docs-test` | 17 | doc-example test harness (private) | n/a |
| `skills/supermemory` | 8 | **agent skill** (prose + references) | n/a |

`git ls-files` prints one apparent extra top-level entry, `"apps`. It is not a directory: seven `apps/docs/images/Screenshot *.png` filenames contain a narrow no-break space (`\342\200\257`), so git quotes the whole path. There are four real top-level directories: `.github`, `apps`, `packages`, `skills`.

**So: several of these at once, in a monorepo.** Hosted SaaS console, an MCP server, client SDKs in two languages, a browser-adjacent desktop extension, an agent skill, and a docs site. **There is no CLI and no self-hostable server in the tree**, despite the README advertising both (section 5).

---

## 3. Where data goes, per component

**Every in-repo component that moves user data sends it to `https://api.supermemory.ai`.** That string is the hardcoded default in:

| `path:line` | Component |
|---|---|
| `packages/tools/src/shared/context.ts:10` | `@supermemory/tools`, shared client factory |
| `packages/tools/src/openai/middleware.ts:20` | `@supermemory/tools`, OpenAI middleware |
| `packages/tools/src/shared/forget-memory.ts:1` | `@supermemory/tools`, forget path |
| `packages/tools/src/conversations-client.ts:120` | `@supermemory/tools`, conversations client |
| `packages/openai-sdk-python/src/supermemory_openai/middleware.py:38` | `supermemory-openai-sdk` |
| `apps/mcp/src/server/index.ts:21` | MCP worker, upstream API |
| `apps/mcp/wrangler.jsonc:14` | MCP worker, deploy-time binding |
| `apps/raycast-extension/src/api.ts:54` | Raycast extension |
| `packages/lib/api.ts:447`, `auth.ts:14`, `auth.middleware.ts:13` | web console |

The canonical form, `packages/tools/src/shared/context.ts:9-13`:

```ts
export const normalizeBaseUrl = (url?: string): string => {
	const defaultUrl = "https://api.supermemory.ai"
	if (!url) return defaultUrl
	return url.endsWith("/") ? url.slice(0, -1) : url
}
```

Python, `packages/openai-sdk-python/src/supermemory_openai/middleware.py:38`:

```python
DEFAULT_SUPERMEMORY_BASE_URL = "https://api.supermemory.ai"
```

MCP worker, `apps/mcp/src/server/index.ts:21-22`:

```ts
const DEFAULT_API_URL = "https://api.supermemory.ai"
const DEFAULT_MCP_RESOURCE = "https://mcp.supermemory.ai/mcp"
```

**Overridable in all but one place.** The TypeScript and Python wrappers accept `baseUrl` / `base_url`, and `packages/tools/src/shared/context.ts:38-40` passes it through only when it differs from the default. **The Raycast extension is the exception:** `apps/raycast-extension/src/api.ts:54` sets `const API_BASE_URL = "https://api.supermemory.ai"` as a module constant, and its only user preference is `apiKey` (`apps/raycast-extension/package.json:44-46`). There is no base-URL override, so it cannot be pointed at a self-hosted server.

**Two components store nothing remotely.** `packages/memory-graph` is a pure React visualization component: a grep for `fetch(`, `axios`, and `https://` across `packages/memory-graph/src` returns nothing outside `mock-data.ts`. `skills/supermemory` is prose plus five reference Markdown files, with no executable code.

**The MCP worker's own state is Cloudflare-side, not local.** Two Durable Objects with SQLite storage, `SupermemoryMCP` and `SpaceState` (`apps/mcp/wrangler.jsonc:25-47`), plus an R2 bucket for the console's cache (`apps/web/wrangler.jsonc:25-30`).

**Local storage exists only in the out-of-repo binary:** `SUPERMEMORY_DATA_DIR`, default `./.supermemory` (`apps/docs/self-hosting/configuration.mdx:17`), with uploaded files "stored on local disk inside `$SUPERMEMORY_DATA_DIR` and served by the server at `/files/:key`" (`configuration.mdx:62`).

---

## 4. API key requirement

**Required, with no in-repo account-free mode.** Config surface is one env var, `SUPERMEMORY_API_KEY`, with an explicit throw when it is absent. `packages/tools/src/shared/context.ts:51-58`, quoted with the error string's em dash rendered as a comma:

```ts
export function validateApiKey(apiKey?: string): string {
	const providedApiKey = apiKey ?? process.env.SUPERMEMORY_API_KEY

	if (!providedApiKey) {
		throw new Error(
			"SUPERMEMORY_API_KEY is not set, provide it via `options.apiKey` or set `process.env.SUPERMEMORY_API_KEY`",
		)
	}
```

The same env var and the same throw repeat at `packages/tools/src/vercel/index.ts:122-126`, `packages/tools/src/voltagent/middleware.ts:84-87`, `packages/tools/src/openai/middleware.ts:766-769`, `packages/tools/src/openai/index.ts:67-69`, and `packages/agent-framework-python/src/supermemory_agent_framework/connection.py:50`.

The base-URL env vars are not uniform across the ecosystem, which matters when pointing a client at a self-hosted server. Three distinct names appear in the docs: `SUPERMEMORY_API_URL` (Codex and Cursor plugins, `apps/docs/integrations/codex.mdx:14`, `cursor.mdx:138`), `SUPERMEMORY_BASE_URL` (OpenClaw plugin, `apps/docs/integrations/openclaw.mdx:11`), and `NEXT_PUBLIC_BACKEND_URL` (web console, `packages/lib/api.ts:447`).

**The MCP server requires an account, not just a key.** It is OAuth-only: `apps/mcp/src/server/index.ts:207` returns `unauthorizedResponse(...)` when no token is present, and `apps/mcp/src/server/auth/index.ts:31-36` validates the bearer token by calling the upstream API with it. Discovery runs through `/.well-known/oauth-protected-resource/mcp` (`apps/mcp/README.md:42-43`).

**The only no-account mode is the out-of-repo binary**, which self-issues a key: "An API key, generated for you, printed on first boot" (`apps/docs/self-hosting/overview.mdx:28`, dash normalized).

---

## 5. Self-hosting: a documented path, not a buildable one

This is the decisive finding, and it needs all four pieces of evidence together.

**The README and docs promise a self-hosted server.** `README.md:317-325` gives `curl -fsSL https://supermemory.ai/install | bash`, `npx supermemory local`, and `supermemory-server`, with `README.md:327` stating the API "runs against `http://localhost:6767`". `apps/docs/self-hosting/overview.mdx:20` adds: *"No Docker. No database to provision. No config files. It boots in seconds with everything built in, and it's open source"*, hyperlinking `https://git.new/memory`.

**That link resolves back to this repo.** Redirect chain, fetched 2026-09-17:

```
https://git.new/memory        -> 302 -> https://github.com/Dhravya/supermemory
https://github.com/Dhravya/supermemory -> 301 -> https://github.com/supermemoryai/supermemory
```

**The binary's source is not in this repo.** Four independent confirmations against the pinned clone:

1. `git ls-files | grep -iE 'supermemory-server|local-server|engine'` returns exactly one path, and it is a picture: `apps/docs/images/what-is-supermemory-engine.jpg`.
2. No package manifest declares a `bin` field. All 16 were checked; every `bin` is `None`.
3. `grep -rln 'supermemory-server\|server-v' .github/` returns nothing. None of the 12 workflows builds or releases it; they publish the SDK wrappers (`publish-tools.yml`, `publish-ai-sdk.yml`, `publish-memory-graph.yml`, and the four Python ones).
4. No `.gitmodules`. Nothing is vendored in from elsewhere.

**It is distributed as a prebuilt binary on this repo's Releases.** The installer names the source explicitly (`https://supermemory.ai/install:7-9`, dash normalized): *"Detects your OS+arch, downloads the matching binary from the supermemoryai/supermemory GitHub Releases, verifies sha256, and (if run interactively) asks for an LLM API key."* Its constants, `install:27-29`:

```bash
REPO="supermemoryai/supermemory"
BIN_NAME="supermemory-server"
RELEASES_URL="https://github.com/$REPO/releases"
```

`https://api.github.com/repos/supermemoryai/supermemory/releases` confirms the assets. Newest release `server-v0.0.8`, published `2026-08-17T18:39:22Z`:

| Asset | Bytes |
|---|---|
| `supermemory-server-darwin-arm64` | 270741952 |
| `supermemory-server-darwin-x64` | 285968048 |
| `supermemory-server-linux-arm64` | 282461981 |
| `supermemory-server-linux-x64` | 312295037 |
| `supermemory-server-windows-x64.exe` | 291315712 |
| `install.sh`, `manifest.json`, five `.sha256` files | small |

Integrity is checked, not attested: the installer reads the expected digest out of `manifest.json` from the same release and compares (`install:191-210`), so it proves the download matched what that release published, not that the release matched any source. There is no signature and no provenance attestation. On macOS it applies an **ad-hoc code signature of its own** when the binary fails verification (`install:75-87`): `codesign --force --sign - "$1"`.

**Consequences for the brief's question 4.** A genuinely self-hostable path exists and is documented in detail, but it is a **binary-only** path: not buildable, auditable, or forkable from this repository, and not reproducible. There is no `docker-compose.yml`, no `Dockerfile`, and no Kubernetes manifest anywhere in the tree. The `wrangler.jsonc` files are not a self-hosting route: `apps/mcp/wrangler.jsonc:17-23` pins a custom domain on `supermemory.ai`, and `apps/web/wrangler.jsonc:28` pins the R2 bucket `supermemory-console-cache`, so both deploy the vendor's own production, not a tenant's.

---

## 6. External services self-hosting still needs

From `apps/docs/self-hosting/configuration.mdx`, which is the docs source for `supermemory.ai/docs/self-hosting/configuration`:

| Service | Required? | Evidence |
|---|---|---|
| **LLM provider** (one of OpenAI, Anthropic, Gemini, Groq, Cloudflare Workers AI, GCP Vertex) | **Required**, user's own key | `configuration.mdx:21-30`: *"Configure at least one LLM provider"* |
| **Embeddings provider** | **Optional.** Local by default, no key | `configuration.mdx:66`, `overview.mdx:27`: default `Xenova/bge-base-en-v1.5` (768d) |
| **Vector database** | **Not required** | `overview.mdx:26`: graph engine is embedded, *"No database to stand up, no connection strings"* |
| **Object storage** | **Not required** | `configuration.mdx:62`: local disk under `$SUPERMEMORY_DATA_DIR` |
| **Cloudflare account** | **Not required** for the binary; required only to deploy `apps/mcp` or `apps/web` | `apps/mcp/wrangler.jsonc`, `apps/web/wrangler.jsonc` |
| **supermemory account** | **Not required** | `overview.mdx:28`: key generated on first boot |

Provider env vars, `configuration.mdx:23-30`: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `GROQ_API_KEY`, `WORKERS_AI_API_KEY` plus `CLOUDFLARE_ACCOUNT_ID`, `GOOGLE_VERTEX_PROJECT_ID` plus `GOOGLE_VERTEX_LOCATION`. Selection is positional: *"With multiple providers configured, the first one in the order above is used"* (`:36`).

**A genuinely zero-egress configuration is documented.** `overview.mdx:37-42` and `configuration.mdx:44-51` point the OpenAI-compatible client at a local runner:

```bash
OPENAI_BASE_URL=http://localhost:11434/v1
OPENAI_API_KEY=ollama        # any non-empty string for local runners
OPENAI_MODEL=gpt-oss:20b
```

`overview.mdx:44`: *"Local graph engine, local embeddings, local LLM. Your data never leaves the building."*

**Two caveats the docs themselves record.** Multi-modal ingestion is not provider-neutral: *"Image, video, and high-fidelity PDF understanding require a Gemini or Vertex AI key"* (`configuration.mdx:39`). And the self-hosted feature set is a subset: `overview.mdx:69-70` marks Connectors and Supermemory MCP as platform-only, and `configuration.mdx:129-134` repeats it, adding that *"Any other environment variables you may find referenced in the codebase are platform-only: the self-hosted binary ignores them even when set"* (`:136`).

**One discrepancy worth flagging.** The docs say embeddings need no key (`configuration.mdx:66`) while the installer prompt says *"supermemory-server needs at least one LLM API key for embeddings/summaries"* (`install:248`). Reading both, the LLM key is required for extraction and summarization while embeddings stay local, so the installer's wording is loose rather than contradictory; but the precise boundary is **not determinable from primary sources** without the binary.

---

## 7. License

**Root: MIT.** `LICENSE:1-3` reads `MIT License` / `Copyright (c) 2025 supermemory`, with the standard attribution clause at `:12-13`: *"The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software."* The GitHub API agrees (`spdx_id: MIT`).

**Different licenses do appear inside the tree,** so a blanket "the repo is MIT" is imprecise:

| Path | License | Source |
|---|---|---|
| repository root | **MIT** | `LICENSE:1` |
| `skills/supermemory/` | **Apache-2.0** | `skills/supermemory/LICENSE:1-2` |
| `packages/tools` | MIT (declared) | `packages/tools/package.json` `"license": "MIT"` |
| `packages/memory-graph` | MIT (declared) | `packages/memory-graph/package.json` |
| `apps/raycast-extension` | MIT (declared) | `apps/raycast-extension/package.json` |
| the four Python packages | MIT (declared) | each `pyproject.toml:10`, plus `license-files = ["LICENSE"]` on two |
| `packages/ai-sdk` and every `@repo/*` package | no `license` field | falls under root MIT |

**The API client every wrapper depends on is Apache-2.0 and lives elsewhere.** `packages/tools/package.json` depends on `"supermemory": "^4.25.4"`, and the npm registry manifest for `supermemory@4.25.4` gives `"license": "Apache-2.0"` and `"repository": {"url": "git+https://github.com/supermemoryai/sdk-ts.git"}`. So the HTTP client doing the actual data transmission is a separate, separately licensed repository. `@supermemory/tools@2.3.0` registry manifest confirms MIT and `"directory": "packages/tools"` in this repo.

Only five `LICENSE` files exist in the tree, and their first lines are: `LICENSE`, `packages/tools/LICENSE`, `packages/agent-framework-python/LICENSE`, and `packages/openai-sdk-python/LICENSE` all read `MIT License`; `skills/supermemory/LICENSE` reads `Apache License`. The other MIT declarations (`memory-graph`, `cartesia-sdk-python`, `pipecat-sdk-python`, the Raycast extension) are manifest fields with no accompanying file.

**No source-available-but-not-open component.** `git grep -il` across the tracked tree for `business source`, `BUSL`, `BSL-1`, `elastic license`, `commons clause`, `SSPL`, `fair source`, and `noncommercial` returns no files. The one restriction any component carries is Apache-2.0's patent and notice terms on `skills/supermemory` and on the out-of-repo `sdk-ts`.

**The binary's license is not stated in this repo.** `local-vs-enterprise.mdx:8` calls Supermemory local *"free, open source"*, but no LICENSE file accompanies the release assets and the tree carries no source to license. Whether the root MIT grant covers the shipped binary is **not determinable from primary sources**.

---

## 8. MCP server

**One MCP server, hosted, in `apps/mcp/`.** Not a published npm package: `apps/mcp/package.json` names it `supermemory-mcp` at version `1.0.0` with no `bin`, no `files`, and no publish workflow. It is a Cloudflare Worker (`apps/mcp/wrangler.jsonc:3,7`, `"name": "supermemory-mcp"`, `"main": "src/server/index.ts"`).

**Configuration is a remote URL, not a command.** `README.md:137-145` and `apps/mcp/README.md:32-40` give the same block:

```json
{
  "mcpServers": {
    "supermemory": {
      "url": "https://mcp.supermemory.ai/mcp"
    }
  }
}
```

There is no stdio transport and no local mode. The route is pinned to the vendor's zone (`wrangler.jsonc:17-23`), and the docs list MCP as platform-only, unavailable self-hosted (`overview.mdx:70`).

**It talks to a remote API.** Every request is OAuth-validated against `https://api.supermemory.ai` (`apps/mcp/src/server/index.ts:21`, `auth/index.ts:31-36`), so the worker is a proxy, not a store, apart from the active-space Durable Object (`apps/mcp/README.md:10-12`).

**Fifteen tools, registered at `apps/mcp/src/server/tools/index.ts:18-33`**, in three tiers per `apps/mcp/README.md:45-70`:

| Tier | Tools |
|---|---|
| Model-visible | `search_memory`, `listDocuments`, `getDocument`, `listMemories`, `listSpaces`, `whoAmI`, `add_memory` |
| MCP App launchers | `select-space`, `memory-graph`, `guided-save`, `upload-file` |
| App-only, hidden from the model | `set-active-tag`, `save-memory`, `prepare-file-upload`, `fetch-graph-data` |

**The README's tool table does not describe this server.** `README.md:151-155` lists three tools, `memory`, `recall`, and `context`, none of which appears in the registry above. Those names belong to the editor plugins, which are five separate repositories (`README.md:122-127`: `claude-supermemory`, `cursor-supermemory`, `codex-supermemory`, `openclaw-supermemory`, `opencode-supermemory`), none of them in scope here. Anyone auditing tool surface from the README alone will audit the wrong list.

---

## 9. Executable and auto-run surface

**No install-time execution.** A grep for `"postinstall"`, `"preinstall"`, and `"prepare"` across all 16 `package.json` files matches nothing. The single hit is a publish guard, `apps/raycast-extension/package.json:71`, whose `prepublishOnly` prints a warning and `exit 1` to stop an accidental `npm publish`; it never runs on install. The registry manifests for `supermemory@4.25.4` and `@supermemory/tools@2.3.0` likewise declare no install hooks.

**Nothing auto-registers into an editor or agent.** `git ls-files` finds no `.claude-plugin/`, `plugin.json`, `marketplace.json`, `hooks.json`, `settings.json`, or `.mcp.json` anywhere in the tree. The MCP config in section 8 is documentation the user pastes by hand.

**The one auto-run surface is the installer**, and it is the route the README puts first (`README.md:96-98`). Behavior, from `https://supermemory.ai/install`:

- **Downloads and executes a 270 MB to 312 MB opaque binary** from GitHub Releases, sha256-checked against a manifest in the same release (`install:186-210`).
- **Writes two paths outside the repo:** the binary under `$HOME/.supermemory` (default) and a wrapper script at `$HOME/.local/bin/supermemory-server` (`install:30-31`, `:277-294`). The wrapper `set -a`, sources `~/.supermemory/env`, and `exec`s the binary.
- **Prompts for, and stores in plaintext, one of the user's own model-provider keys.** `install:245-269` offers OpenAI, Anthropic, or Gemini and writes the value to `~/.supermemory/env` at mode `600`. `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, or `GEMINI_API_KEY` already exported are written through without a prompt (`install:236-243`, documented at `:17-19`).
- **Re-attaches `/dev/tty` to prompt through a pipe** (`install:89-93`), so `curl | bash` is interactive by design.
- **Starts the server automatically** when a TTY is available: `install:328` is `exec "$wrapper"`, gated on `should_auto_start()` (`:95-99`), which is suppressed by `SUPERMEMORY_NO_START=1` or `SUPERMEMORY_NO_PROMPT=1`. It declines to auto-start as root (`:323-327`).
- **Re-signs the binary on macOS** with an ad-hoc signature when verification fails (`install:75-87`).

**Telemetry: two call sites, both in vendor-operated components, neither in a client SDK.**

1. **MCP worker, PostHog, opt-in by deploy config.** `apps/mcp/src/server/analytics.ts:2` imports `posthog-node`; `:5` sets `const DEFAULT_POSTHOG_HOST = "https://us.i.posthog.com"`. It no-ops without a key, `analytics.ts:110-113`:

```ts
	const apiKey = env.POSTHOG_API_KEY
	if (!apiKey) return { record: () => undefined }

	const client = posthogClient(apiKey, env.POSTHOG_HOST || DEFAULT_POSTHOG_HOST)
```

`apps/mcp/.dev.vars.example:7-8` marks `POSTHOG_API_KEY` `#(optional)`, and no key is committed. The event is `mcp_tool_executed`, `distinctId` the `userId`, grouped by `organizationId`, carrying `tool_name`, `outcome`, `duration_ms`, `mcp_client_name`, `mcp_client_version`, `space_explicit`, `oauth_client_id`, and `error_type` (`analytics.ts:75-103`). This is the vendor's own deployment measuring its own service, not something a user of the SDK ships.

2. **Web console, PostHog, key committed and always on.** `packages/lib/posthog.tsx:45-47`:

```ts
			posthog.init("phc_ShqecfUPQgf16lWu6ZMUzduQvcWzCywrkCz5KHwmWsv", {
				api_host: `${backendUrl}/orange`,
				ui_host: "https://us.i.posthog.com",
```

Note `api_host` is a **reverse proxy on supermemory's own API host** (`${backendUrl}/orange`, where `backendUrl` defaults to `https://api.supermemory.ai` at `:42-43`), so console analytics egress is first-party-looking traffic rather than a recognizable PostHog domain. This is the hosted console, private (`apps/web/package.json` `"private": true`), and not something a self-hoster runs.

**Zero telemetry in every published client package.** A case-insensitive grep for `posthog|sentry|segment|amplitude|mixpanel|analytics|telemetry` across `packages/tools/src`, `packages/ai-sdk/src`, `packages/memory-graph/src`, and all four `packages/*-python/src` trees returns exactly one hit, and it is a string in fixture data: `packages/memory-graph/src/mock-data.ts:137`. Sentry appears only in the root build script (`package.json:10-11`, `sentry:sourcemaps` plus `postbuild`), which uploads sourcemaps at the vendor's build time and ships nothing to consumers.

**The binary's telemetry claim cannot be checked.** `configuration.mdx:119-125` states: *"The self-hosted binary sends no analytics, there is nothing to opt out of"*, with one switch, `SUPERMEMORY_DISABLE_TELEMETRY`, described as disabling *"internal AI SDK telemetry instrumentation"*. Since the binary is not in this repo (section 5), that claim is **not determinable from primary sources**. The two statements also sit oddly together: a component that sends no analytics needs no disable switch.

---

## 10. Embeddings and LLM calls

**The published wrappers call model providers with the user's own keys, and never with supermemory's.** `packages/tools/package.json` depends on `@ai-sdk/anthropic`, `@ai-sdk/openai`, `ai`, and `openai`, but the wrapper's job is to wrap a model instance the caller constructs. `README.md:247-248` shows the shape:

```typescript
import { withSupermemory } from "@supermemory/tools/ai-sdk";
const model = withSupermemory(openai("gpt-4o"), { containerTag: "user_123", customId: "conv-1" });
```

The provider key is bound to `openai(...)` by the caller, outside the wrapper. No provider key is read from the environment anywhere in `packages/tools/src` except in tests.

**On the hosted platform the extraction models are supermemory's own and undisclosed.** `configuration.mdx:21`: *"In production, Supermemory uses its own proprietary models tuned for long-horizon data understanding."* `local-vs-enterprise.mdx:17` puts it in the comparison table as "Proprietary models tuned for long-horizon data understanding" against self-hosted's "Bring your own key". Which upstream provider those models run on is **not determinable from primary sources**.

**Self-hosted, every model call is the user's own key** (section 6), and embeddings default to a local model with no key at all: `SUPERMEMORY_EMBEDDING_PROVIDER=local`, `SUPERMEMORY_EMBEDDING_MODEL=Xenova/bge-base-en-v1.5`, `SUPERMEMORY_EMBEDDING_DIMENSIONS=768` (`configuration.mdx:70-75`). Remote alternatives are `openai`, `gemini`, or any OpenAI-compatible endpoint via `SUPERMEMORY_EMBEDDING_BASE_URL`, all opt-in.

**The default self-hosted chat model is a pinned id**, `OPENAI_MODEL` default `gpt-5.1` (`configuration.mdx:56`), with `OPENAI_FAST_MODEL` and `OPENAI_TEXT_MODEL` defaulting to it. This is the staleness pattern `docs/research/self-updating-model-ids.md` documents: an undated OpenAI alias pins the minor version and goes stale at the next release.

---

## Open questions / staleness risk

- **The central unverifiable is the binary.** Everything in sections 5, 6, 9, and 10 about `supermemory-server` rests on the repo's own docs describing a component the repo does not contain. Reading the docs cannot establish where the binary sends data, whether it phones home, or what license covers it. Anyone who needs those answers must instrument the binary on a network sandbox; the repository cannot settle them, and no amount of further reading here will.
- **`git.new/memory` is a third-party shortener in the trust path.** Two first-party docs pages (`overview.mdx:20`, `local-vs-enterprise.mdx:25`) route their "open source" and "support" links through `git.new`, whose redirect target can change without a docs edit. It resolved to this repo on 2026-09-17; that is a point-in-time fact, not a stable one.
- **The README's MCP tool table is wrong for this repo's MCP server** (section 8). If craftkit or anything else ever cites supermemory's MCP surface, cite `apps/mcp/src/server/tools/index.ts:18-33` or `apps/mcp/README.md:45-70`, never `README.md:151-155`.
- **The Raycast extension cannot be pointed at a self-hosted server** (`apps/raycast-extension/src/api.ts:54`). If self-hosting is the reason for adopting supermemory, that component is out of scope by construction, and a future base-URL preference would be the thing to recheck.
- **Version drift is fast and the clone is a snapshot.** `pushed_at` is `2026-09-17T03:46:20Z`, the same day as this note, against a clone pinned to the prior day's commit. Release `server-v0.0.8` is from 2026-08-17. Both the tree and the binary line move independently, and the binary line is the one with no commit history to read.
- **Benchmark claims were deliberately not verified.** `README.md:32-33` and `:346-358` assert `#1` on LongMemEval, LoCoMo, and ConvoMem, plus `95% Recall@15` and a `99.4%` context reduction, sourcing them to `supermemory.ai/research`. Those are first-party marketing assertions about third-party benchmarks; confirming them means running the benchmarks, not reading the repo. Treat every figure in those lines as **unverified**.
- **The `supermemory` client SDK was out of scope and is the larger attack surface.** `github.com/supermemoryai/sdk-ts` (Apache-2.0) is what every wrapper in this repo delegates HTTP to, and it was checked here only through its npm registry manifest, enough to confirm license, repository, and absence of install hooks. Its request behavior, retry logic, and any header it adds are unexamined. That repo, not this one, is where a data-egress audit of the SDK path should start.
