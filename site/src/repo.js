export const { version: VERSION, repo: REPO } = __CRAFTKIT__;
export const INSTALL = `npm install -g ${__CRAFTKIT__.name}`;

// One display name per sync.sh ADAPTERS entry, its first word being the adapter id; check.sh holds
// the two together. The hero illustration draws these four, so a new tool also needs a new sync-engine.png.
export const TOOLS = ['Claude Code', 'Cursor', 'Gemini CLI', 'Codex CLI'];
export const TOOL_LIST = new Intl.ListFormat('en', { type: 'conjunction' }).format(TOOLS);

// check.sh resolves every literal argument to these, so a renamed README heading or a moved file
// fails the gate instead of shipping a dead link.
export const readme = (anchor) => `${REPO}#${anchor}`;
export const repoFile = (path) => `${REPO}/blob/main/${path}`;
