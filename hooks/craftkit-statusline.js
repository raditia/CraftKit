#!/usr/bin/env node
// Agent dashboard status line: prints model, effort, context, cost and the running subagent
// count, and saves them as <session>.status.json so scripts/dashboard.py can show the same
// numbers. When the user already had a status line, sync saved it to
// ~/.craftkit-state/statusline.json; it runs first, with the same stdin, and this appends.
// Running = a file in <session>.agents/ touched within HIDE_MS, the same rule the dashboard uses.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const HIDE_MS = 24 * 3600 * 1000;
const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0);
const text = (v, fallback) => (typeof v === 'string' ? v.replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ').slice(0, 40) : fallback);

function theirs(raw) {
  // An inner run (their command somehow calling this script) must not wrap again, or each render
  // would spawn itself until the timeouts cascade.
  if (process.env.CRAFTKIT_STATUSLINE_INNER) return '';
  try {
    const saved = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.craftkit-state', 'statusline.json'), 'utf8'));
    if (!saved || typeof saved.command !== 'string' || saved.command.includes('craftkit-statusline.js')) return '';
    // A slow, failing or runaway status line of theirs must not blank or stall ours. SIGKILL so a
    // grandchild of the shell cannot outlive the timeout.
    const r = spawnSync('/bin/sh', ['-c', saved.command], {
      input: raw, encoding: 'utf8', timeout: 2000, killSignal: 'SIGKILL', maxBuffer: 64 * 1024,
      env: { ...process.env, CRAFTKIT_STATUSLINE_INNER: '1' },
    });
    return r.error || r.status !== 0 ? '' : (r.stdout || '').trimEnd();
  } catch (_) {
    return '';
  }
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  let p = {};
  try { p = JSON.parse(raw) || {}; } catch (_) {}
  const model = text(p.model && p.model.display_name, '?');
  const effort = text(p.effort && p.effort.level, '-');
  const ctx = Math.floor(num(p.context_window && p.context_window.used_percentage));
  const cost = num(p.cost && p.cost.total_cost_usd);
  const dir = path.join(os.homedir(), '.craftkit', 'agent-tree', 'events');
  const sid = String(p.session_id || '').replace(/[^A-Za-z0-9-]/g, '');
  let run = 0;
  if (sid) {
    try {
      fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
      // Only the fields the dashboard shows are kept; the raw payload also carries cwd and transcript paths.
      const snapshot = { model: { display_name: model }, effort: { level: effort }, context_window: { used_percentage: ctx }, cost: { total_cost_usd: cost } };
      // A temp name per process: refreshes overlap, and a shared name lets one truncate another's write.
      const status = path.join(dir, `${sid}.status.json`);
      const tmp = `${status}.${process.pid}.tmp`;
      try {
        fs.writeFileSync(tmp, JSON.stringify(snapshot), { mode: 0o600 });
        fs.renameSync(tmp, status);
      } catch (_) { fs.rmSync(tmp, { force: true }); }
    } catch (_) {}
    const agents = path.join(dir, `${sid}.agents`);
    const now = Date.now();
    let names = [];
    try { names = fs.readdirSync(agents); } catch (_) {}
    // Per file, because a subagent stopping between readdir and stat must not zero the count.
    run = names.filter((f) => {
      try { return now - fs.statSync(path.join(agents, f)).mtimeMs < HIDE_MS; } catch (_) { return false; }
    }).length;
  }
  const before = theirs(raw);
  process.stdout.write(
    (before ? `${before} ` : '') +
    `\x1b[38;5;209m${model}\x1b[0m effort [${effort}] ctx [${ctx}%] $${cost.toFixed(2)} ` +
    `\x1b[38;5;111msubagents [${run} running]\x1b[0m`
  );
});
