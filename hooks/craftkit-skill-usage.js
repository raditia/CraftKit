#!/usr/bin/env node
// Skill usage metrics (Claude Code only): appends one JSON line per Skill tool call to
// ~/.craftkit/skill-usage.jsonl. Records skill name, session id, project folder name and an
// error flag; never the prompt, args or tool output. Registered for PostToolUse and
// PostToolUseFailure on `Skill`, and only when CRAFTKIT_SKILL_METRICS=1 (or skill.metrics=on
// in the craftkit config) opted in. Fails open: a logging error never blocks a tool call.
// ponytail: file grows without bound, since retention analysis needs history. ceiling: large
// files slow scripts/skill-usage.js. upgrade: rotate when the file passes N MB.
const fs = require('fs');
const os = require('os');
const path = require('path');

const clean = (v, n) => String(v == null ? '' : v).replace(/[^A-Za-z0-9_:.-]/g, '').slice(0, n);

let raw = '';
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', () => {
  try {
    const ev = JSON.parse(raw);
    const skill = clean(ev.tool_input && ev.tool_input.skill, 80);
    if (!skill) return;
    const resp = ev.tool_response;
    const error = ev.hook_event_name === 'PostToolUseFailure'
      || !!(resp && typeof resp === 'object' && resp.is_error);
    const dir = path.join(os.homedir(), '.craftkit');
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    const line = JSON.stringify({
      ts: Math.floor(Date.now() / 1000),
      skill,
      session: clean(ev.session_id, 80),
      src: 'claude',
      proj: clean(path.basename(ev.cwd || ''), 80),
      error,
    });
    fs.appendFileSync(path.join(dir, 'skill-usage.jsonl'), line + '\n', { mode: 0o600 });
  } catch (e) { /* fail open */ }
});
