#!/usr/bin/env node
// Context sources: the per-project list of team docs repos that planning skills search.
// Owns ~/.craftkit/context-sources.json (project root -> sources) and the shallow clones under
// ~/.craftkit/context-cache/ (ADR-0003). Called through context-source.sh.
//
//   connect <url>            add a source to this project, cloning its cache if missing
//   replace <old> <new>      swap one source; the old cache is pruned if nothing else uses it
//   disconnect <source>      remove one source; same pruning
//   status                   this project's sources, plus stale entries anywhere
//   forget-stale             drop entries whose project root is gone, then prune
//   refresh                  fetch every source once; one freshness line each (the resolve step)
//   search <term>...         rank files across this project's caches under one read budget
//
// Exit: 0 ok · 1 usage · 2 refused (bad url, no access, unknown source, unreadable store) ·
// 3 no node (from the wrapper) · 4 a source has no usable copy, so the caller must ask the
// user · 5 unexpected runtime error. An unconnected project prints nothing and exits 0 for
// refresh and search, without running git, so planning there is unchanged.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const HOME = path.join(os.homedir(), '.craftkit');
const STORE = path.join(HOME, 'context-sources.json');
const CACHE = path.join(HOME, 'context-cache');
const LOCKS = path.join(CACHE, '.locks');
const TMP = path.join(CACHE, '.tmp');
const READ_BUDGET = 8;
const MAX_TEXT_BYTES = 1024 * 1024;
const GIT_TIMEOUT = 60000;
const LOCK_LEASE = 180000;
const TEXT_EXT = new Set(['.md', '.markdown', '.txt', '.sql', '.json', '.yaml', '.yml', '.csv']);
const GAP_EXT = new Set(['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx']);
const NAME = '[A-Za-z0-9_.-]+';

class Refusal extends Error { constructor(code, msg) { super(msg); this.code = code; } }
const die = (code, msg) => { throw new Refusal(code, msg); };

// Walk up to .git (a directory, or a file in a worktree) instead of asking git, so the
// unconnected path never spawns a process. realpath makes a symlinked or differently cased
// path to one checkout the same key.
function projectRoot() {
  let dir;
  try { dir = fs.realpathSync.native(process.cwd()); } catch (e) { return null; }
  for (;;) {
    if (fs.existsSync(path.join(dir, '.git'))) return dir;
    const up = path.dirname(dir);
    if (up === dir) return null;
    dir = up;
  }
}

// One repo, one cache: https, ssh and owner/repo shorthand all reduce to github.com/<o>/<r>.
// A token in the URL is refused, because the store must never hold a credential, and the
// error never echoes what was typed.
function normalize(input) {
  const raw = String(input || '').trim();
  const pick = (o, r, remote) => {
    if (/^\.+$/.test(o) || /^\.+$/.test(r)) die(2, 'owner and repo cannot be "." or ".."');
    return { key: `github.com/${o}/${r}`.toLowerCase(), remote };
  };
  let m = raw.match(new RegExp(`^https?://([^/@]+@)?github\\.com/(${NAME})/(${NAME}?)(?:\\.git)?/?$`, 'i'));
  if (m) {
    if (m[1]) die(2, 'URL carries credentials; use your git credential helper or ssh instead');
    return pick(m[2], m[3], `https://github.com/${m[2]}/${m[3]}`);
  }
  m = raw.match(new RegExp(`^(?:ssh://)?git@github\\.com[:/](${NAME})/(${NAME}?)(?:\\.git)?/?$`, 'i'));
  if (m) return pick(m[1], m[2], `git@github.com:${m[1]}/${m[2]}.git`);
  m = raw.match(new RegExp(`^(${NAME})/(${NAME}?)(?:\\.git)?$`));
  if (m) return pick(m[1], m[2], `https://github.com/${m[1]}/${m[2]}`);
  die(2, 'not a github.com repo (expected https://github.com/<owner>/<repo>, git@github.com:<owner>/<repo>, or <owner>/<repo>)');
}

// "+" cannot appear in a GitHub owner or repo name, so the directory name maps back to one
// key, and locks and temp clones live in their own namespaces where no repo name can land.
const cacheName = key => key.replace(/\//g, '+');
const cacheDir = key => path.join(CACHE, cacheName(key));

function load() {
  let text;
  try { text = fs.readFileSync(STORE, 'utf8'); } catch (e) {
    if (e.code === 'ENOENT') return { version: 1, projects: {} };
    die(2, `store unreadable (${e.code}): ${STORE}`);
  }
  let store;
  try { store = JSON.parse(text); } catch (e) { die(2, `store is not valid JSON, left untouched: ${STORE}`); }
  if (!store || typeof store.projects !== 'object' ||
      Object.values(store.projects).some(p => !p || !Array.isArray(p.sources))) {
    die(2, `store has an unexpected shape, left untouched: ${STORE}`);
  }
  return store;
}
function save(store) {
  fs.mkdirSync(HOME, { recursive: true });
  const tmp = `${STORE}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2) + '\n', { mode: 0o600 });
  fs.renameSync(tmp, STORE);
}

function git(args) {
  const env = { ...process.env, GIT_TERMINAL_PROMPT: '0', GIT_CEILING_DIRECTORIES: CACHE };
  if (!env.GIT_SSH_COMMAND) env.GIT_SSH_COMMAND = 'ssh -o BatchMode=yes';
  const r = spawnSync('git', args, { encoding: 'utf8', env, timeout: GIT_TIMEOUT });
  return { ok: r.status === 0, out: r.stdout || '', err: (r.stderr || (r.error && r.error.message) || '').trim() };
}
const lastLine = s => (s.split('\n').filter(Boolean).pop() || 'unknown error').slice(0, 200);
const headOf = dir => {
  if (!fs.existsSync(path.join(dir, '.git'))) return null;
  const r = git(['-C', dir, 'rev-parse', 'HEAD']);
  return r.ok ? r.out.trim() : null;
};

// mkdir is the atomic lock. A lock older than the lease is taken as abandoned; the lease is
// three times the git timeout, so a live fetch always finishes before its lock can be taken.
// A lock that cannot be created at all (a host sandbox, a read-only home) returns at once.
function withLock(name, fn) {
  const lock = path.join(LOCKS, `${name}.lock`);
  const deadline = Date.now() + 30000;
  try { fs.mkdirSync(LOCKS, { recursive: true, mode: 0o700 }); } catch (e) { return { locked: false, why: `cache not writable (${e.code})` }; }
  for (;;) {
    try { fs.mkdirSync(lock); break; } catch (e) {
      if (e.code !== 'EEXIST') return { locked: false, why: `cache not writable (${e.code})` };
      if (Date.now() > deadline) return { locked: false, why: 'another refresh holds the lock' };
      try { if (Date.now() - fs.statSync(lock).mtimeMs > LOCK_LEASE) fs.rmSync(lock, { recursive: true, force: true }); } catch (_) { /* released meanwhile */ }
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
    }
  }
  try { return { locked: true, value: fn() }; } finally { fs.rmSync(lock, { recursive: true, force: true }); }
}
const storeLocked = fn => {
  const r = withLock('store', fn);
  if (!r.locked) die(2, `store not writable: ${r.why}`);
  return r.value;
};

function insideCache(dir) {
  const r = path.resolve(dir);
  if (!r.startsWith(CACHE + path.sep) || r.startsWith(LOCKS) || r.startsWith(TMP)) die(5, `refusing to touch ${r}`);
  return r;
}

// Caller holds the cache lock. Clone into the temp namespace and rename, so a half-finished
// clone is never mistaken for a usable copy; temp clones left by a killed run are swept.
function cloneLocked(src) {
  const dir = insideCache(cacheDir(src.key));
  if (headOf(dir)) return { ok: true };
  try {
    fs.mkdirSync(TMP, { recursive: true, mode: 0o700 });
    for (const t of fs.readdirSync(TMP)) {
      const p = path.join(TMP, t);
      if (t.startsWith(`${cacheName(src.key)}-`) && Date.now() - fs.statSync(p).mtimeMs > LOCK_LEASE) fs.rmSync(p, { recursive: true, force: true });
    }
    const tmp = path.join(TMP, `${cacheName(src.key)}-${process.pid}`);
    fs.rmSync(tmp, { recursive: true, force: true });
    const r = git(['clone', '--quiet', '--depth', '1', '--', src.remote, tmp]);
    if (!r.ok) { fs.rmSync(tmp, { recursive: true, force: true }); return { ok: false, why: lastLine(r.err) }; }
    fs.rmSync(dir, { recursive: true, force: true });
    fs.renameSync(tmp, dir);
    fs.chmodSync(dir, 0o700);
    return { ok: true };
  } catch (e) {
    return { ok: false, why: `cache not writable (${e.code || e.message})` };
  }
}
function ensureCache(src) {
  const r = withLock(cacheName(src.key), () => cloneLocked(src));
  return r.locked ? r.value : { ok: false, why: r.why };
}

// Every entry counts, including one whose root is missing right now: an unmounted drive or a
// moved checkout must not lose its cache because another project disconnected. Stale entries
// leave only through an explicit forget-stale.
const referenced = (store, key) => Object.values(store.projects).some(p => p.sources.some(s => s.key === key));

function prune(key) {
  withLock(cacheName(key), () => {
    if (referenced(load(), key)) return;
    const dir = insideCache(cacheDir(key));
    if (!fs.existsSync(dir)) return;
    const du = spawnSync('du', ['-sh', dir], { encoding: 'utf8' });
    const size = du.status === 0 ? du.stdout.split('\t')[0] : 'size unknown';
    fs.rmSync(dir, { recursive: true, force: true });
    console.log(`pruned ${dir} (${size})`);
  });
}

// Read paths use the nearest enclosing root that has an entry, so planning from a submodule or
// a nested checkout still finds a connection made at the outer root.
function connectedRoot(store) {
  let root = projectRoot();
  while (root) {
    if (sourcesOf(store, root).length) return root;
    let up = path.dirname(root);
    root = null;
    for (;;) {
      if (fs.existsSync(path.join(up, '.git'))) { root = up; break; }
      const next = path.dirname(up);
      if (next === up) break;
      up = next;
    }
  }
  return null;
}

function requireRoot() {
  const root = projectRoot();
  if (!root) die(2, 'not inside a git project');
  return root;
}
const sourcesOf = (store, root) => (root && store.projects[root] && store.projects[root].sources) || [];
function setSources(store, root, sources) {
  if (sources.length) store.projects[root] = { sources }; else delete store.projects[root];
}
function findSource(store, root, input) {
  const { key } = normalize(input);
  const hit = sourcesOf(store, root).find(s => s.key === key);
  if (!hit) die(2, `${key} is not connected to this project`);
  return hit;
}

// The entry is recorded before the clone, so a concurrent prune elsewhere sees the reference
// and keeps the cache; a failed clone takes the entry back out.
function addThenFetch(root, src) {
  storeLocked(() => { const st = load(); setSources(st, root, sourcesOf(st, root).concat([src])); save(st); });
  const c = ensureCache(src);
  if (c.ok) return c;
  storeLocked(() => { const st = load(); setSources(st, root, sourcesOf(st, root).filter(s => s.key !== src.key)); save(st); });
  return c;
}

function connect(url) {
  const root = requireRoot();
  const src = normalize(url);
  if (sourcesOf(load(), root).some(s => s.key === src.key)) { console.log(`already connected ${src.key}`); return; }
  const c = addThenFetch(root, src);
  if (!c.ok) die(2, `cannot fetch ${src.key}: ${c.why}`);
  const head = headOf(cacheDir(src.key));
  console.log(`connected ${src.key}@${head ? head.slice(0, 12) : 'none'}`);
}

function disconnect(input) {
  const root = requireRoot();
  const old = storeLocked(() => {
    const st = load();
    const hit = findSource(st, root, input);
    setSources(st, root, sourcesOf(st, root).filter(s => s.key !== hit.key));
    save(st);
    return hit;
  });
  console.log(`disconnected ${old.key}`);
  prune(old.key);
}

function replace(oldInput, newUrl) {
  const root = requireRoot();
  const old = findSource(load(), root, oldInput);
  const src = normalize(newUrl);
  if (src.key === old.key) { console.log(`already connected ${src.key}`); return; }
  if (!sourcesOf(load(), root).some(s => s.key === src.key)) {
    const c = addThenFetch(root, src);
    if (!c.ok) die(2, `cannot fetch ${src.key}: ${c.why}; ${old.key} stays connected`);
  }
  storeLocked(() => { const st = load(); setSources(st, root, sourcesOf(st, root).filter(s => s.key !== old.key)); save(st); });
  console.log(`replaced ${old.key} with ${src.key}`);
  prune(old.key);
}

function status() {
  const root = requireRoot();
  const store = load();
  const mine = sourcesOf(store, root);
  if (!mine.length) console.log('no sources connected');
  for (const s of mine) {
    const dir = cacheDir(s.key);
    const head = headOf(dir);
    const branch = head ? git(['-C', dir, 'symbolic-ref', '--short', 'refs/remotes/origin/HEAD']) : { ok: false };
    const sharers = Object.keys(store.projects).filter(r => r !== root && store.projects[r].sources.some(x => x.key === s.key));
    console.log(`source=${s.key} sha=${head || 'none'} branch=${branch.ok ? branch.out.trim() : 'unknown'} path=${dir}` +
      (sharers.length ? ` shared-with=${sharers.join(',')}` : ''));
  }
  for (const r of Object.keys(store.projects)) if (!fs.existsSync(r)) console.log(`stale project=${r}`);
}

function forgetStale() {
  const gone = storeLocked(() => {
    const st = load();
    const stale = Object.keys(st.projects).filter(r => !fs.existsSync(r));
    const keys = [];
    for (const r of stale) { keys.push(...st.projects[r].sources.map(s => s.key)); delete st.projects[r]; console.log(`forgot project=${r}`); }
    save(st);
    return keys;
  });
  for (const k of new Set(gone)) prune(k);
}

function refreshOne(s) {
  const dir = cacheDir(s.key);
  const before = headOf(dir);
  const r = withLock(cacheName(s.key), () => {
    if (!before) {
      const c = cloneLocked(s);
      return c.ok ? { state: 'clean', sha: headOf(dir) } : { state: 'no-copy', why: c.why };
    }
    const f = git(['-C', dir, 'fetch', '--quiet', '--depth', '1', 'origin']);
    if (!f.ok) return { state: 'cannot-verify', sha: before, why: lastLine(f.err) };
    const now = git(['-C', dir, 'rev-parse', 'refs/remotes/origin/HEAD']);
    if (!now.ok) return { state: 'cannot-verify', sha: before, why: 'remote default branch unknown' };
    const want = now.out.trim();
    if (want === before) return { state: 'clean', sha: before };
    const reset = git(['-C', dir, 'reset', '--quiet', '--hard', want]);
    const after = headOf(dir);
    if (!reset.ok || after !== want) return { state: 'cannot-verify', sha: after || before, why: `update failed: ${lastLine(reset.err)}` };
    return { state: 'drifted', sha: after, from: before };
  });
  if (r.locked) return r.value;
  return before ? { state: 'cannot-verify', sha: before, why: r.why } : { state: 'no-copy', why: r.why };
}

function refresh() {
  const store = load();
  const mine = sourcesOf(store, connectedRoot(store));
  for (const s of mine) {
    const r = refreshOne(s);
    if (r.state === 'no-copy') process.exitCode = 4;
    console.log(`state=${r.state} source=${s.key} sha=${r.sha || 'none'}` + (r.from ? ` from=${r.from}` : '') +
      ` path=${cacheDir(s.key)}` + (r.why ? ` reason=${r.why.replace(/\s+/g, ' ')}` : ''));
  }
}

// One budget across every source: each source with a hit gets its best file first, so no
// connected repo is silently skipped, then the rest goes by score. A file scores mostly by
// how many distinct terms it holds, so one long file repeating a word cannot bury a short
// decision. Symlinks are never followed and path= / file= are JSON strings, with control
// characters in a name refused outright: a docs repo must not point the reader at local files
// or forge an output line through a filename.
// ponytail: plain substring matching, no stemming or synonyms. ceiling: a decision phrased in
// other words is missed, which callers must report as coverage, not agreement. upgrade:
// semantic search if misses show up in the T12 eval.
function search(terms) {
  const store = load();
  const mine = sourcesOf(store, connectedRoot(store));
  if (!mine.length) return;
  const words = terms.map(t => t.toLowerCase()).filter(Boolean);
  if (!words.length) die(1, 'search needs at least one term');
  const hits = [];
  const summary = [];
  for (const s of mine) {
    const dir = cacheDir(s.key);
    const sha = headOf(dir) || 'none';
    const ls = sha === 'none' ? { ok: false } : git(['-C', dir, 'ls-files', '-z']);
    const files = ls.ok ? ls.out.split('\0').filter(Boolean) : [];
    const skipped = {};
    const skip = (rel, why, pathHit) => {
      skipped[why] = (skipped[why] || 0) + 1;
      if (pathHit) console.log(`gap source=${s.key} path=${rel.startsWith('"') ? rel : JSON.stringify(rel)} reason=${why}`);
    };
    let searched = 0;
    for (const rel of files) {
      if (/[\u0000-\u001f\u007f]/.test(rel)) { skip(JSON.stringify(rel), 'unsafe-name', true); continue; }
      const file = path.join(dir, rel);
      const ext = path.extname(rel).toLowerCase();
      const pathHit = words.some(w => rel.toLowerCase().includes(w));
      if (GAP_EXT.has(ext)) { skip(rel, 'unsupported-format', pathHit); continue; }
      if (!TEXT_EXT.has(ext)) { skip(rel, 'other-type', false); continue; }
      let st;
      try { st = fs.lstatSync(file); } catch (e) { skip(rel, 'unreadable', pathHit); continue; }
      if (!st.isFile()) { skip(rel, 'symlink', pathHit); continue; }
      if (st.size > MAX_TEXT_BYTES) { skip(rel, 'too-large', pathHit); continue; }
      let text;
      try { text = fs.readFileSync(file, 'utf8'); } catch (e) { skip(rel, 'unreadable', pathHit); continue; }
      if (text.startsWith('version https://git-lfs')) { skip(rel, 'lfs-pointer', pathHit); continue; }
      if (text.slice(0, 8192).includes('\0')) { skip(rel, 'binary', pathHit); continue; }
      searched++;
      const found = new Set();
      let occurrences = 0;
      const at = [];
      text.split('\n').forEach((line, i) => {
        const l = line.toLowerCase();
        let n = 0;
        for (const w of words) { const c = l.split(w).length - 1; if (c) { found.add(w); n += c; } }
        if (n) { occurrences += n; if (at.length < 10) at.push(i + 1); }
      });
      const score = found.size * 10 + Math.min(occurrences, 10) + (pathHit ? 5 : 0);
      if (found.size || pathHit) hits.push({ source: s.key, sha, file, rel, score, at });
    }
    summary.push({ key: s.key, searched, skipped });
  }
  hits.sort((a, b) => b.score - a.score || (a.source + a.rel < b.source + b.rel ? -1 : 1));
  const picked = [];
  for (const s of mine) {
    const best = hits.find(h => h.source === s.key);
    if (best && picked.length < READ_BUDGET) picked.push(best);
  }
  for (const h of hits) if (picked.length < READ_BUDGET && !picked.includes(h)) picked.push(h);
  for (const h of picked) {
    console.log(`read source=${h.source} sha=${h.sha} path=${JSON.stringify(h.rel)} score=${h.score} lines=${h.at.join(',')} file=${JSON.stringify(h.file)}`);
  }
  for (const s of summary) {
    const sk = Object.keys(s.skipped).sort().map(k => `${k}:${s.skipped[k]}`).join(',') || 'none';
    console.log(`coverage source=${s.key} searched=${s.searched} read=${picked.filter(h => h.source === s.key).length} skipped=${sk}`);
  }
}

const [cmd, ...args] = process.argv.slice(2);
const need = n => { if (args.length !== n) die(1, `${cmd} takes ${n} argument(s)`); };
try {
  switch (cmd) {
    case 'connect': need(1); connect(args[0]); break;
    case 'replace': need(2); replace(args[0], args[1]); break;
    case 'disconnect': need(1); disconnect(args[0]); break;
    case 'status': need(0); status(); break;
    case 'forget-stale': need(0); forgetStale(); break;
    case 'refresh': need(0); refresh(); break;
    case 'search': search(args); break;
    default: die(1, 'usage: connect <url> | replace <old> <new> | disconnect <source> | status | forget-stale | refresh | search <term>...');
  }
} catch (e) {
  process.stderr.write(`context-source: ${e instanceof Refusal ? e.message : `runtime error: ${e.message}`}\n`);
  process.exitCode = e instanceof Refusal ? e.code : 5;
}
