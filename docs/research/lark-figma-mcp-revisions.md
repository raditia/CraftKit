# Lark/Feishu and Figma MCP: revision fields for "changed since X" checks

Research date: **2026-09-24**. Primary sources only: the source of the official Lark/Feishu MCP server, read from a shallow clone of `github.com/larksuite/lark-openapi-mcp` pinned at `21920354ec6e3966b52e89152620c5085e496b55` (committed 2025-08-14, package version `0.5.1` at `package.json:3`, matching the npm `latest` of `@larksuiteoapi/lark-mcp`); the Lark/Feishu Open Platform API reference on `open.larksuite.com` and `open.feishu.cn`; and Figma's developer docs on `developers.figma.com`. No blog, listicle, or third-party summary was consulted. Every claim cites a `path:line` inside that clone or the URL it came from.

**Retrieval caveat.** The Lark/Feishu doc pages render client-side, so their content was read from the portal's own JSON endpoint (`/document_portal/v1/document/get_detail?fullPath=<path>`) on the same host, which returns the page's source markdown. Citations give the public page URL. Those pages are written in Chinese on both hosts; every Lark doc quote below is **my English translation**, not upstream text. No upstream text quoted here contained an em dash, so no punctuation was normalized.

**Scope caveat.** Lark/Feishu now ships three official agent surfaces: the local OpenAPI MCP (`lark-openapi-mcp`), a hosted remote MCP (Feishu only), and a newer `lark-cli` that the remote-MCP page itself recommends instead. The CLI is not an MCP server and was not researched (section 1.6).

## Answer

- **Lark local MCP can read a docx revision, but not in the default preset.** `docx.v1.document.get` returns `revision_id` and is exposed as a tool, but it sits outside every preset, so it must be enabled explicitly with `-t docx.v1.document.get` (section 1.2). The same holds for `drive.v1.meta.batchQuery` (`latest_modify_time`, up to 200 files per call). The only revision-ish field reachable **in the default preset** is `obj_edit_time` from `wiki.v2.space.getNode`, and only for wiki-hosted docs.
- **Lark local MCP can write docx blocks and bitable records. Its sheets writes are limited to find-and-replace.** Every docx block write (`documentBlock.patch`, `batchUpdate`, `documentBlockChildren.create`, `documentBlockDescendant.create`) is a tool. Bitable record create/update/batch tools are in the default preset. The MCP ships **no Sheets v2 tools** (no `values` read/write, no `metainfo`), so it cannot read cell values or the sheet `revision`; the only cell write is `sheets.v3.spreadsheetSheet.replace` (section 1.3).
- **Tool scoping is an allowlist.** `-t` takes tool names and/or `preset.*` names; tools outside the list are never registered. `--token-mode` then drops tools that don't support the chosen token type. Auth runs as the app (`tenant_access_token`), as a user (`user_access_token`, via `--oauth` or `-u`), or `auto`, where the model picks per call through a `useUAT` flag (section 1.4).
- **docx `document_revision_id` is a version selector, not a documented precondition.** On writes it is "the document version to operate on, -1 means latest", defaults to `-1`, and the write response returns the new `document_revision_id`. No documented error code says "revision mismatch". The closest is `1770021 too old document`, and no page defines when it fires. **Whether a stale revision rejects a write (optimistic concurrency) is not determinable from primary sources** (section 2.1).
- **Sheets and bitable have no write-side revision parameter at all.** Sheets v2 returns `revision` on reads, writes and `metainfo`, but the write request takes none. Bitable app `revision` counts structural edits; records carry `last_modified_time` only when `automatic_fields=true`. Bitable's own docs say table writes are serialized per version and should not be sent concurrently (section 2.2, 2.3).
- **Figma MCP (remote and desktop) exposes no file `version` or `lastModified` tool.** No tool in the documented list returns file-level version metadata. The "version" parameters it does have belong to generative plugins, shaders, Weave tools and Code Connect mappings (section 3.1).
- **Figma REST's cheapest reliable check is `GET /v1/files/:key/meta`** (Tier 3, `file_metadata:read`), which returns `version` and `last_touched_at` without the document tree. `GET /v1/files/:key?depth=1` also returns `version`/`lastModified`, but it is Tier 1, the most tightly rate-limited tier. Change detection is **file-level only**: nodes carry no modified timestamp, and a node-level diff means fetching the node twice (`/nodes?ids=…&version=<old>`) and comparing it client-side (section 3.2, 3.3).

---

## 1. Lark/Feishu official MCP server (`lark-openapi-mcp`)

### 1.1 Repository and surface

- `api.github.com/repos/larksuite/lark-openapi-mcp`: `archived: false`, license MIT, description "飞书/Lark官方 OpenAPI MCP" (Feishu/Lark official OpenAPI MCP), last push `2025-08-14T05:39:18Z`.
- The README marks it Beta: "This tool is currently in Beta stage" (`README.md:15`).
- Tools are generated one per OpenAPI endpoint: 1,269 distinct `name:` entries across `src/mcp-tool/tools/en/gen-tools/zod/*.ts` (count via `grep -rho "name: '[a-z_0-9]*\.v[0-9]*\.[A-Za-z.]*'" … | sort -u | wc -l`), plus three hand-written builtins: `docx.builtin.search`, `docx.builtin.import` (`tools/en/builtin-tools/docx/builtin.ts:12,86`) and `im.builtin.batchSend` (`tools/en/builtin-tools/im/buildin.ts:8`).
- Naming follows `biz.version.resource.method`, the same as the Node SDK method path (https://open.feishu.cn/document/mcp_open_tools/mcp-overview). Registered names are case-transformed, `snake` by default (`src/cli.ts:77`, `utils/case-transf.ts:4`).
- The handler returns the raw OpenAPI `data` object as JSON text (`src/mcp-tool/utils/handler.ts:46`). Whatever the endpoint returns, `revision_id` included, reaches the model unfiltered.
- The Feishu overview adds that APIs in grey release and image/file upload or download APIs are not supported in the MCP (https://open.feishu.cn/document/mcp_open_tools/mcp-overview).

### 1.2 Revision / modified-time fields reachable as tools

| Tool | Endpoint | Field it returns | In a preset? |
|---|---|---|---|
| `docx.v1.document.get` | `GET /open-apis/docx/v1/documents/:document_id` | `document.revision_id`; tool text: "Obtains the document title and the latest revision ID" (`docx_v1.ts:16833-16838`) | No |
| `docx.v1.documentBlock.list` / `.get` / `documentBlockChildren.get` | block reads | take `document_revision_id` as an input, to read a historical version (`docx_v1.ts:15917,15951,11287`) | No |
| `drive.v1.meta.batchQuery` | `POST /open-apis/drive/v1/metas/batch_query` | `latest_modify_time`, `latest_modify_user`; up to 200 docs per call (`drive_v1.ts:1112-1140`) | No |
| `drive.v1.file.list` | `GET /open-apis/drive/v1/files` | `modified_time` per file; `order_by: EditedTime` (`drive_v1.ts:555,578`) | No |
| `drive.v1.fileVersion.list` / `.get` | named-version API | manually created named versions only (section 2.4) | No |
| `wiki.v2.space.getNode` | `GET /open-apis/wiki/v2/spaces/get_node` | `obj_edit_time` ("document last edited time") | **Yes**: `preset.light`, `preset.default`, `preset.doc.default` (`constants.ts:50,90`) |
| `bitable.v1.appTableRecord.search` / `.get` / `.list` | record reads | `last_modified_time` when `automatic_fields: true` (`bitable_v1.ts:1715`, also 1591, 1632) | `search` is in `preset.light`, `preset.default`, `preset.base.*` (`constants.ts:51,70`) |
| `bitable.v1.app.get` | `GET /open-apis/bitable/v1/apps/:app_token` | app `revision` (structural, section 2.3) | No |
| `sheets.v3.spreadsheet.get` | `GET /open-apis/sheets/v3/spreadsheets/:token` | title, owner, token, url; **no revision** (section 2.2) | No |

Default-preset read tool for docx content is `docx.v1.document.rawContent` (`constants.ts:47,86`), which returns plain text only. Its response carries no revision field per its tool description (`docx_v1.ts:16851-16857`); I found no response schema in the clone to confirm the negative.

### 1.3 Write capability

- **docx blocks: yes, all block writes are tools**, none in a preset. `docx.v1.documentBlock.patch` (`docx_v1.ts:15972`), `docx.v1.documentBlock.batchUpdate` (`:4946`), `docx.v1.documentBlockChildren.create` (`:5820`), `docx.v1.documentBlockChildren.batchDelete` (`:5779`), `docx.v1.documentBlockDescendant.create` (`:11311`), plus `docx.v1.document.create` and `docx.v1.document.convert` (markdown/HTML to blocks). Each write accepts `document_revision_id` (`:16762, 5749, 11249, 5793, 15896`). The default preset's only docx write is `docx.builtin.import`, which creates a **new** document through a drive import task (`builtin.ts:26,61-64`) rather than editing an existing one.
- **bitable records: yes, in the default preset.** `preset.default` includes `appTableRecord.create` and `.update` (`constants.ts:73-77,109-114`); `preset.base.batch` swaps in `batchCreate`/`batchUpdate` (`constants.ts:79-83`); `preset.light` includes `batchCreate` (`constants.ts:52`). No record write takes a revision or precondition parameter (none of the bitable tool schemas has a `revision` input; `grep -n revision bitable_v1.ts` finds only response-side text).
- **sheets: effectively no.** No file in `src/` references `sheets/v2` or `sheets.v2` (`grep -rln "sheets/v2\|sheets.v2" src` is empty), so the v2 values read/write and `metainfo` endpoints are absent. The only cell-level write is `sheets.v3.spreadsheetSheet.replace`, find-and-replace over a range, up to 5,000 cells (`sheets_v3.ts:736-741`). No sheets tool is in any preset (`constants.ts:42-114`).

### 1.4 Scoping and auth

- **Allowlist.** `-t, --tools` takes "List of API tools to enable, separated by commas or spaces (default: "preset.default")" (`src/cli.ts:72-75`). Any `preset.*` name in the list is expanded to its members and deduped (`src/mcp-server/shared/init.ts:19-28`). An empty list falls back to `defaultToolNames` (`src/mcp-tool/mcp-tool.ts:47-51`). `filterTools` keeps only tools whose name is in `allowTools` or whose project is in `allowProjects` (`src/mcp-tool/utils/filter-tools.ts:5-9`); the CLI path only ever passes `allowTools` (`init.ts:33-35`).
- **Presets**: `preset.light`, `preset.default`, `preset.im.default`, `preset.base.default`, `preset.base.batch`, `preset.doc.default`, `preset.task.default`, `preset.calendar.default` (`constants.ts:7-40`, membership `:42-125`). The README warns: "Non-preset APIs have not undergone compatibility testing" (`README.md:183`).
- **Token mode.** `--token-mode auto | user_access_token | tenant_access_token`, default `auto` (`src/cli.ts:81-84`). A non-auto mode also filters out tools whose `accessTokens` lack that type (`filter-tools.ts:12-25`). At call time `user_access_token` always uses the user token, `tenant_access_token` never does, and `auto` defers to the per-call `useUAT` boolean in each tool's schema (`utils/get-should-use-uat.ts:3-16`, `mcp-tool.ts:186`).
- **User token sources**: `-u, --user-access-token` (beta) or `--oauth`, which runs a local auth server and refreshes or re-authorizes on expiry (`src/cli.ts:85-92`, `mcp-tool.ts:108-136`); `--scope` narrows the OAuth scope (`src/cli.ts:90-93`). App credentials (`-a`, `-s`) are mandatory in every mode (`init.ts:14-17`). The README recommends `--oauth --token-mode user_access_token` because under `auto` "some APIs AI may fallback to `tenant_access_token`" (`README.md:114`).
- Transports: `stdio` (default), `sse`, `streamable` (`src/cli.ts:94`).

### 1.5 Feishu remote MCP (hosted, Feishu only)

- Tools, per https://open.feishu.cn/document/mcp_open_tools/supported-tools: basic `search-user`, `get-user`, `fetch-file`; docs `search-doc`, `create-doc`, `fetch-doc`, `update-doc`, `list-docs`, `get-comments`, `add-comments`. The page states only the cloud-docs scenario is supported. `fetch-doc` excludes bitable and sheets content. Changelog: first release 2025-12-19; `update-doc`, `list-docs` and the comment tools added 2025-12-29.
- **Write**: `update-doc` appends, inserts or replaces content in a docx. No sheets or bitable tools exist.
- **Revision fields: not determinable from primary sources.** The page describes tools in prose only and publishes no input or output schema, so whether `fetch-doc` returns a revision, or `update-doc` accepts one, cannot be confirmed.
- **Auth and scoping**: user identity only. The server URL "represents calling Feishu tools as the currently logged-in user, equivalent to a personal key"; since 2026-02-24 new services expire after 7 days; scoping is by choosing tool sets in the config console (https://open.feishu.cn/document/mcp_open_tools/end-user-call-remote-mcp-server).
- **Deprecation**: the same page warns that the MCP Token (personal-hosted) path "will be gradually taken offline" and recommends the Feishu CLI.
- The supported-tools page does not exist on `open.larksuite.com` (portal returns "文档不存在", document does not exist, for `/mcp_open_tools/supported-tools`). Whether international Lark offers the remote MCP is **not determinable from primary sources**.

### 1.6 Out of scope: `lark-cli`

The Feishu CLI page links `https://github.com/larksuite/cli` as the source (https://open.feishu.cn/document/mcp_open_tools/feishu-cli-let-ai-actually-do-your-work-in-feishu). It is a CLI rather than an MCP server, so it was not examined.

## 2. Lark Open API: revision semantics

### 2.1 docx `revision_id` / `document_revision_id`

- **Read.** `GET /open-apis/docx/v1/documents/:document_id` "obtains the document's latest revision number, title, etc." and returns `document.revision_id` (int), described as "document version ID" (https://open.larksuite.com/document/server-docs/docs/docs/docx-v1/document/get). App rate limit: 5 req/s. The data-structure overview describes `revision_id` as "the identifier of the document version; can specify which version to query or update" (https://open.larksuite.com/document/server-docs/docs/docs/docx-v1/docx-overview).
- **Block reads** (`GET …/blocks`) accept `document_revision_id`: "the document version to query, -1 means latest. Querying the latest version needs read permission; querying a historical version needs edit permission" (https://open.larksuite.com/document/ukTMukTMukTM/uUDN04SN0QjL1QDN/document-docx/docx-v1/document-block/list). So reads can target history.
- **Writes.** `PATCH …/blocks/:block_id` and `PATCH …/blocks/batch_update` take query param `document_revision_id` (int, optional): "the document version to operate on, -1 means the latest version. Editing needs edit permission." Default `-1`, minimum `-1` (https://open.larksuite.com/document/server-docs/docs/docs/docx-v1/document-block/patch, https://open.larksuite.com/document/server-docs/docs/docs/docx-v1/document-block/batch_update). `POST …/blocks/:block_id/children` carries the same text (https://open.larksuite.com/document/ukTMukTMukTM/uUDN04SN0QjL1QDN/document-docx/docx-v1/document-block-children/create).
- **Write response** returns `document_revision_id`, "the document's version number after this update succeeds", plus `client_token` (same pages). `client_token` is an idempotency key: "empty means a new request; non-empty means an idempotent update" (patch page). It deduplicates retries and is not a concurrency guard.
- **Is `-1` latest?** Yes, stated on every read and write page above.
- **Does a stale value reject the write?** **Not determinable from primary sources.** The parameter is worded as selecting a version to operate on, not as an expected-current-version precondition. The error tables on get, patch, batch_update, block list and children create define no "revision conflict" code. They do list `400 1770021 too old document`, with remedy "confirm the specified Document version is too old" (patch, batch_update, get pages), but nowhere say what threshold makes a version too old, or whether any revision below latest triggers it. A caller can't rely on it for optimistic concurrency without testing it empirically.
- **Concurrency limit.** Per document, at most 3 edits per second (create, delete, update, batch update blocks); beyond that the API returns HTTP 429 (children create page).
- The FAQ's examples all pass `document_revision_id=-1` (https://open.larksuite.com/document/ukTMukTMukTM/uUDN04SN0QjL1QDN/document-docx/docx-v1/faq).

### 2.2 Sheets

- `PUT /open-apis/sheets/v2/spreadsheets/:spreadsheetToken/values` (write a single range): the request body is `valueRange.range` + `valueRange.values` only, with **no revision input**. The response returns `revision` ("sheet version number") (https://open.larksuite.com/document/server-docs/docs/sheets-v3/data-operation/write-data-to-a-single-range).
- `GET …/values/:range` returns top-level `revision` and `valueRange.revision` (https://open.larksuite.com/document/server-docs/docs/sheets-v3/data-operation/reading-a-single-range).
- `GET /open-apis/sheets/v2/spreadsheets/:spreadsheetToken/metainfo` returns `properties.revision` (described as "this sheet's version") alongside `sheetCount` and the per-sheet list. This is the cheapest sheet revision read: no cell data (https://open.larksuite.com/document/server-docs/docs/sheets-v3/spreadsheet/obtain-spreadsheet-metadata).
- `GET /open-apis/sheets/v3/spreadsheets/:spreadsheet_token` returns `title`, `owner_id`, `token`, `url` and **no revision** (https://open.feishu.cn/document/server-docs/docs/sheets-v3/spreadsheet/get).
- Optimistic concurrency for sheets: no write endpoint consulted accepts a revision, so there is none to use.

### 2.3 Bitable

- App `revision` (`GET /open-apis/bitable/v1/apps/:app_token`): "the Base's version number. Updated on modification, e.g. adding or deleting tables, renaming tables; starts at 1, +1 per update" (https://open.larksuite.com/document/server-docs/docs/bitable-v1/app/get). Every example given is structural. **Whether record edits bump it is not determinable from primary sources.**
- Records: `automatic_fields` on search "controls whether to compute and return created_time, last_modified_time, created_by, last_modified_by; default false" (https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/reference/bitable-v1/app-table-record/search); record get documents `last_modified_time` as "the record's most recent update time" (https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/reference/bitable-v1/app-table-record/get).
- **Writes have no precondition.** Record update (`PUT …/records/:record_id`) has no revision input; its error guidance says the underlying table processing "is serial by version and does not support concurrency", so concurrent requests to one table should be avoided (https://open.larksuite.com/document/server-docs/docs/bitable-v1/app-table-record/update).
- Whether search can filter server-side on the automatic `last_modified_time` (i.e. "records changed since T") is **not determinable from primary sources**: the filter guide targets named fields, and I found no statement that automatic fields are filterable.

### 2.4 Drive metadata

- `POST /open-apis/drive/v1/metas/batch_query`: returns `latest_modify_time` ("last edit time, Unix timestamp", a string) and `latest_modify_user` per doc; supports `doc`, `sheet`, `bitable`, `docx`, `wiki`, `file`, `folder` and more; rate limit 1000/min, 50/s (https://open.larksuite.com/document/server-docs/docs/drive-v1/file/batch_query). This is the cheapest multi-type, multi-file check: one call, up to 200 tokens.
- `GET /open-apis/drive/v1/files` (folder listing) returns `modified_time` per entry and sorts by `EditedTime` by default (https://open.feishu.cn/document/server-docs/docs/drive-v1/folder/list). The `open.larksuite.com` copy of the same page omits `modified_time` from its field list, so field parity across the two hosts is **not determinable from primary sources**.
- Wiki `get_node` returns `obj_edit_time`, "document last edited time" (https://open.larksuite.com/document/server-docs/docs/wiki-v2/space-node/get_node).
- `drive/v1/files/:file_token/versions` is the **named-version** feature: "supports users manually generating document versions", for `docx` and `sheet` only (https://open.feishu.cn/document/uAjLw4CM/ukTMukTMukTM/reference/drive-v1/file-version/overview). It does not track every edit, so it is not a change detector.
- Push alternative: event `drive.file.edit_v1` fires when a subscribed doc is edited, "including bitable field and record changes", after calling the subscribe API (https://open.larksuite.com/document/server-docs/docs/drive-v1/event/list/file-edited). The MCP exposes `drive.v1.file.subscribe` (`drive_v1.ts:648`) but, as a request/response server, has no event receiver.
- Timestamp granularity: the examples are 10-digit Unix seconds (`"latest_modify_time": "1652066345"`, batch_query page). Two edits within one second are indistinguishable, which makes the docx `revision_id` the stricter docx signal.

## 3. Figma

### 3.1 Figma MCP server (remote and desktop)

- Endpoints: remote `https://mcp.figma.com/mcp` (https://developers.figma.com/docs/figma-mcp-server/remote-server-installation/), desktop `http://127.0.0.1:3845/mcp` (https://developers.figma.com/docs/figma-mcp-server/local-server-installation/). Figma "strongly recommend[s]" the remote server, which "provides the broadest set of features" (https://developers.figma.com/docs/figma-mcp-server/).
- Tool list (https://developers.figma.com/docs/figma-mcp-server/tools-and-prompts/). Read tools: `download_assets`*, `get_code_connect_map`, `get_code_connect_suggestions`, `get_context_for_code_connect`*, `get_design_context`, `get_figjam`, `get_generative_plugin`*, `get_libraries`*, `get_metadata`, `get_motion_context`, `get_screenshot`, `get_shader`, `get_variable_defs`, `list_file_shaders`*, `list_generative_plugins`*, `list_shaders`, `search_design_system`*, `whoami`*. Write tools: `add_code_connect_map`, `create_generative_plugin`*, `create_new_file`*, `create_shader`*, `generate_diagram`*, `generate_figma_design`*, `send_code_connect_mappings`, `update_generative_plugin`*, `update_shader`*, `upload_assets`*, `use_figma`*. Weave tools are listed separately. (* = marked "Remote only" on that page.)
- **No tool returns file `version` or `lastModified`.** `get_metadata` returns "a sparse XML representation … layer IDs, names, types, position and sizes", or the page list when no `nodeId` is given (same page). The only `version` fields on the page belong to generative plugin and shader sources (a 40-character commit SHA), Weave tool versions, and Code Connect mapping source. `use_figma` runs Plugin API code, but the tools page documents no file-version read through it, so that route is **not determinable from primary sources**.
- Rate limits: Dev/Full seats up to 200/day at 10/min (Professional), 600/day at 20/min (Enterprise); View/Collab seats get up to 6/month on Organization/Enterprise. Some write tools are exempt (https://developers.figma.com/docs/figma-mcp-server/rate-limits-access/). A "has it changed?" probe through MCP would spend this budget even if a tool existed.
- Auth: per-user OAuth; enterprise-managed auth supported only for Claude via Okta XAA (same page).

### 3.2 Figma REST: file-level version fields

All from https://developers.figma.com/docs/rest-api/file-endpoints/ unless noted.

- `GET /v1/files/:key`: `lastModified` and `version` are file metadata in the response; Tier 1; `file_content:read`. `depth=1` "returns only Pages", which trims the payload but not the tier. `version` as a query param fetches a specific historical version.
- `GET /v1/files/:key/nodes?ids=…`: prose says `lastModified` and `version` are returned as file metadata, but the documented return shape lists `lastModified` without `version`. Tier 1. Also accepts `version` and `depth`.
- `GET /v1/files/:key/meta`: returns `file.version`, `file.last_touched_at`, `file.last_touched_by` with no document tree. **Tier 3**, `file_metadata:read`.
- `GET /v1/files/:key/versions`: list of `Version { id, created_at, label, description, user }`, paginated, Tier 2, `file_versions:read` (https://developers.figma.com/docs/rest-api/version-history-endpoints/, https://developers.figma.com/docs/rest-api/version-history-types/). Response order was changed to explicit creation order (types page warning).
- Rate tiers (per minute, Dev/Full seats, Professional / Organization / Enterprise): Tier 1 at 10/15/20, Tier 2 at 25/50/100, Tier 3 at 50/100/150. View/Collab seats get Tier 1 "up to 20/month" (https://developers.figma.com/docs/rest-api/rate-limits/). `/meta` is therefore both the smallest payload and the loosest limit.
- **How often `version` or `last_touched_at` changes (per edit, or per autosave checkpoint) is not documented. Not determinable from primary sources.** Both are opaque strings to compare for equality, not to order.
- Push alternative: webhook `FILE_UPDATE` "triggers within 30 minutes of editing inactivity in a file"; `FILE_VERSION_UPDATE` fires when a user creates a named version (https://developers.figma.com/docs/rest-api/webhooks-events/). Neither is reachable through MCP.

### 3.3 Node-level change detection

- No node type carries a modified timestamp or revision. The node reference documents `devStatus` (Ready for dev / Completed) but no modified-time property (https://developers.figma.com/docs/rest-api/file-node-types/).
- So change detection is **file-level only** from Figma's side. Node-level detection has to be derived: fetch `GET /v1/files/:key/nodes?ids=<id>&version=<old>` and the current node, then diff or hash client-side. That costs two Tier 1 calls, and the file-level check tells you only that *something* changed.

## 4. Summary: cheapest reliable "changed since revision X" field

| Source | Cheapest reliable field | Via MCP? | Via REST |
|---|---|---|---|
| Lark docx | `document.revision_id` (int; each write returns the post-write value, but strict +1 monotonicity is not stated for docx) | Yes, `docx.v1.document.get`, **must be added with `-t`** | `GET /open-apis/docx/v1/documents/:id` (5 req/s) |
| Lark docx, batch of many | `latest_modify_time` (Unix seconds, string) | Yes, `drive.v1.meta.batchQuery`, must be added with `-t` | `POST /open-apis/drive/v1/metas/batch_query`, 200 docs per call |
| Lark docx in a wiki | `obj_edit_time` (seconds) | **Yes, in the default preset** (`wiki.v2.space.getNode`) | `GET /open-apis/wiki/v2/spaces/get_node` |
| Lark sheets | `properties.revision` from `metainfo` | **No**: MCP has no Sheets v2 tools. Fallback is `drive.v1.meta.batchQuery` `latest_modify_time` (seconds granularity) | `GET /open-apis/sheets/v2/spreadsheets/:token/metainfo` |
| Lark bitable, whole Base | `latest_modify_time` via drive meta (inferred, not confirmed: `drive.file.edit_v1` counts bitable record edits as file edits, but no page says `latest_modify_time` moves with them) | Yes, `drive.v1.meta.batchQuery`, must be added with `-t` | batch_query |
| Lark bitable, per record | `last_modified_time` with `automatic_fields: true` | Yes, `appTableRecord.search` in the default preset | records search / get |
| Figma file | `version` (opaque string) from `/meta` | **No**: no MCP tool exposes it | `GET /v1/files/:key/meta` (Tier 3) |
| Figma node | none native; diff node JSON across `version` | No | two `GET /v1/files/:key/nodes` calls (Tier 1) |

Two caveats carry across the table. Lark's `revision_id` is a sound change detector, but it does not make writes safe: no documented write rejects a stale revision (section 2.1), so "changed since X" can be checked at read time, and a check-then-write still races. Figma's `version` equality check is sound for "changed at all", but without documented bump granularity it can't tell you how much changed (section 3.2).

## 5. T0 spike: is a content hash reproducible? (2026-09-24)

Run from Claude Code against the remote Figma MCP (`mcp.figma.com`), company Organization plan, Dev
seat. One frame in a company design file (key and name withheld: this repo is public), read with
`get_metadata` twice, back to back, with no edits between.

| Check | Result |
|---|---|
| Raw response bytes | Identical (sha256 `7e8b7701…1a458a` both reads) |
| Response shape | JSON array of 3 text parts: a `Currently selected nodes` block (82 chars), the node XML (77,337 chars), a fixed tool hint (234 chars) |
| Normalized hash (XML part only, whitespace stripped) | Identical (`064fccd7…` both reads) |

Pinned normalizer, applied to the saved tool-result file:

```bash
jq -r '.[] | .text | select(startswith("<"))' <result-file> | tr -d ' \t\r\n' | shasum -a 256
```

Findings:

- **The raw response is not a safe hash input.** Its first part echoes the user's live Figma
  selection, so a raw hash reports drift whenever the selection changes. Only the XML part is.
- **The hash was computable only because the output was saved to disk.** Claude Code writes a
  tool result to a file when it exceeds the context budget; a small result exists only in model
  context, and the agent would have to re-emit it into a shell, which is lossy. So the hash is
  reliable only where the host persists the raw result, which is not a property any skill can
  rely on across Claude Code, Cursor, Gemini CLI and Codex CLI.
- **`get_metadata` XML carries positions and sizes**, so a layout nudge is reported as drift.
  That is arguably a real design change, but it is noisier than a content edit.

Not yet run: the desktop Figma MCP server, a second host, and the Lark half (no Lark MCP is
connected in this session; `revision_id` / `latest_modify_time` movement on edit is still
unconfirmed).

**Decision for v1.46.0:** Figma node hashes stay `cannot-verify`. The one-host result is stable,
but the second finding means a skill cannot know whether its host saved the raw bytes, and the
T0 bar was identical hashes across hosts and both servers.
