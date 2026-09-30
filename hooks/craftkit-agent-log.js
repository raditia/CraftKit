#!/usr/bin/env node
// Agent dashboard event logger: appends one compact JSON line per hook event to
// ~/.craftkit/agent-tree/events/<session>.jsonl, and keeps <session>.agents/<agent> for each
// running subagent (created on start, touched per tool call, deleted on stop, cleared at
// session end), which scripts/dashboard.py and craftkit-statusline.js read. Registered for
// SubagentStart, SubagentStop, PostToolUse and SessionEnd on Claude Code and Codex
// (argv[2] = "codex"). Only installed when the dashboard is opted
// into (CRAFTKIT_DASHBOARD=1), and it fails open: a logging error never blocks a tool call.
const fs = require('fs');
const os = require('os');
const path = require('path');

const DIR = path.join(os.homedir(), '.craftkit', 'agent-tree', 'events');
const WEEK_MS = 7 * 86400 * 1000;
// A logged command can carry a credential; the dashboard needs the shape of the call, not the secret.
// Named values (flag, env var, header or JSON key, with = : or a space), URL user:pass, curl -u, and
// well-known token prefixes. Shape-based, so it narrows exposure rather than guaranteeing none.
const SECRETS = [
  [/(authorization["']?\s*[:=]\s*["']?(?:[a-z]+\s+)?)[^\s"']+/gi, '$1***'],
  [/((?:--?)?[\w-]*(?:token|password|passwd|secret|api[_-]?key|access[_-]?key)[\w-]*["']?\s*[=:\s]\s*["']?)[^\s"']+/gi, '$1***'],
  [/(bearer\s+)[^\s"']+/gi, '$1***'],
  [/(\s-u\s*)[^\s:]+:[^\s"']+/g, '$1***'],
  [/(\w+:\/\/)[^\s\/:@]+:[^\s\/@]+@/g, '$1***@'],
  [/\b(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{8,}|xox[abpr]-[A-Za-z0-9-]{8,}|AKIA[A-Z0-9]{12,}|AIza[A-Za-z0-9_-]{20,})/g, '***'],
  [/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9._-]+/g, '***'],
  [/((?:cookie["']?\s*[:=]\s*["']?|\s-b\s+["']?))[^"'\n]+/gi, '$1***'],
  [/(\s-p)[^\s"']+/g, '$1***'],
];
const mask = (v) => SECRETS.reduce((acc, [re, to]) => acc.replace(re, to), v);
const id = (v) => String(v || '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 100) || null;

const text = (v, n) => (v == null ? null
  : String(v).replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ').slice(0, n));

function summarize(input) {
  const i = input || {};
  const v = i.file_path ?? i.pattern ?? i.description ?? i.command ?? i.url ?? i.query;
  // Bounded before masking: the patterns backtrack, and a long heredoc or blob would make every tool call slow.
  return v == null ? null : text(mask(String(v).slice(0, 2000)), 60);
}

function prune() {
  const now = Date.now();
  for (const f of fs.readdirSync(DIR)) {
    try {
      const p = path.join(DIR, f);
      if (now - fs.statSync(p).mtimeMs > WEEK_MS) fs.rmSync(p, { recursive: true, force: true });
    } catch (_) {}
  }
}

function track(sid, event, aid, type) {
  const dir = path.join(DIR, `${sid}.agents`);
  const endMark = path.join(DIR, `${sid}.ended`);
  // The marker lets the dashboard drop an ended session without reading its log; any later
  // event means the session was resumed, so it comes back.
  if (event === 'SessionEnd') {
    fs.writeFileSync(endMark, '', { mode: 0o600 });
    return fs.rmSync(dir, { recursive: true, force: true });
  }
  // New work proves a resume: a subagent starting, or the main session's own tool call once the
  // end is a couple of seconds old. A tool or stop hook finishing just after SessionEnd must not
  // bring an ended session back.
  if (event === 'SubagentStart') fs.rmSync(endMark, { force: true });
  else if (event === 'PostToolUse' && !aid) {
    try { if (Date.now() - fs.statSync(endMark).mtimeMs > 2000) fs.rmSync(endMark, { force: true }); } catch (_) {}
  }
  if (!aid) return;
  const file = path.join(dir, aid);
  if (event === 'SubagentStop') return fs.rmSync(file, { force: true });
  // Only a real start creates a box. Claude Code also fires SubagentStop, with no start and no
  // type, for its own internal helpers, and a tool hook finishing after the stop hook must not
  // bring a finished agent back.
  if (event === 'SubagentStart') {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    return fs.writeFileSync(file, type || 'agent', { mode: 0o600 });
  }
  try { fs.utimesSync(file, new Date(), new Date()); } catch (_) {}
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  try {
    const p = JSON.parse(raw);
    if (!p || typeof p !== 'object') return;
    const now = new Date();
    const line = {
      t: now.toTimeString().slice(0, 8),
      ts: Math.floor(now.getTime() / 1000),
      src: process.argv[2] === 'codex' ? 'codex' : 'claude',
      model: typeof p.model === 'string' ? text(p.model, 40) : null,
      // Folder name only: enough to tell sessions apart on the dashboard without logging where it lives.
      proj: p.cwd ? text(path.basename(String(p.cwd)), 40) : null,
      e: text(p.hook_event_name, 30) || 'unknown',
      aid: id(p.agent_id),
      type: text(p.agent_type, 40),
      tool: text(p.tool_name, 40),
      what: summarize(p.tool_input),
    };
    const sid = String(p.session_id || 'unknown').replace(/[^A-Za-z0-9-]/g, '') || 'unknown';
    const file = path.join(DIR, `${sid}.jsonl`);
    fs.mkdirSync(DIR, { recursive: true, mode: 0o700 });
    if (!fs.existsSync(file)) {
      // mkdir's mode applies only to a directory it creates; tighten one that already existed.
      fs.chmodSync(DIR, 0o700);
      prune();
    }
    fs.appendFileSync(file, JSON.stringify(line) + '\n', { mode: 0o600 });
    track(sid, line.e, line.aid, line.type);
  } catch (_) {}
});
