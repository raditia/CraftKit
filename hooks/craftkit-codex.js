#!/usr/bin/env node
// Codex has native lifecycle hooks, but its transcript is not a stable hook API.
// Keep the turn's small verification record from documented hook payloads instead.
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { detectPlatform } = require('./craftkit-platform.js');

const CODE = /\.(ts|tsx|js|jsx|mjs|cjs|kt|java|swift|m|mm)$/i;
const output = value => process.stdout.write(JSON.stringify(value));
const statePath = session => path.join(os.tmpdir(), 'craftkit-codex-' +
  crypto.createHash('sha256').update(session).digest('hex').slice(0, 24) + '.json');
const read = file => { try { return fs.readFileSync(file, 'utf8'); } catch (_) { return ''; } };
const field = (body, name) => {
  const m = body.match(/^---\n([\s\S]*?)\n---/);
  return m && (m[1].match(new RegExp('^' + name + ':\\s*(.+)$', 'm')) || [])[1] || '';
};
const strip = body => body.replace(/^---\n[\s\S]*?\n---\s*/, '');
const save = (file, state) => {
  try { fs.writeFileSync(file, JSON.stringify(state)); } catch (_) { /* fail open */ }
};
const load = file => { try { return JSON.parse(read(file)); } catch (_) { return null; } };

function rules(cwd) {
  const dir = path.join(os.homedir(), '.craftkit', 'codex', 'rules');
  const keys = detectPlatform(cwd).keys;
  let names;
  try { names = fs.readdirSync(dir).filter(n => n.endsWith('.md')).sort(); }
  catch (_) { return ''; }
  return names.map(name => {
    const body = read(path.join(dir, name));
    const scope = field(body, 'platform');
    if (scope && !scope.split(',').map(s => s.trim()).some(s => keys.includes(s))) return '';
    return strip(body).trim();
  }).filter(Boolean).join('\n\n---\n\n');
}

function requestedSkill(prompt) {
  // Native Codex activation handles $name. Injecting an explicitly requested body
  // through the hook closes the gap when an agent skips activation. Only a leading
  // /name is treated as a command; slashes in prose and paths are not commands.
  const names = new Set();
  for (const m of String(prompt || '').matchAll(/(?:^|\s)\$([a-z][a-z0-9-]*)\b/g)) names.add(m[1]);
  const slash = String(prompt || '').match(/^\s*\/([a-z][a-z0-9-]*)\b/);
  if (slash) names.add(slash[1]);
  const bodies = [];
  for (const name of [...names].slice(0, 3)) {
    const file = path.join(os.homedir(), '.agents', 'skills', name, 'SKILL.md');
    const body = read(file);
    if (body && body.length <= 65536) bodies.push('$' + name + '\n\n' + body);
  }
  return bodies.join('\n\n---\n\n');
}

function snapshot(cwd) {
  try {
    const git = args => execFileSync('git', ['-C', cwd].concat(args),
      { encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore'] });
    const root = git(['rev-parse', '--show-toplevel']).trim();
    const head = git(['rev-parse', 'HEAD']).trim();
    const dirty = {};
    for (const line of git(['status', '--porcelain', '-z', '--no-renames', '--untracked-files=all']).split('\0').filter(Boolean)) {
      const name = line.slice(3);
      try {
        const stat = fs.statSync(path.join(root, name));
        dirty[name] = [stat.mtimeMs, stat.size];
      } catch (_) { dirty[name] = null; }
    }
    return { root, head, dirty };
  } catch (_) { return null; }
}

function changed(before, after) {
  if (!before || !after || before.root !== after.root) return [];
  const names = new Set(Object.keys(before.dirty).concat(Object.keys(after.dirty)));
  if (before.head !== after.head) {
    try {
      const files = execFileSync('git', ['-C', after.root, 'diff', '--name-only', before.head, after.head],
        { encoding: 'utf8', timeout: 5000 }).trim();
      files.split('\n').filter(Boolean).forEach(n => names.add(n));
    } catch (_) { /* the dirty set still works */ }
  }
  return [...names].filter(n => JSON.stringify(before.dirty[n]) !== JSON.stringify(after.dirty[n]));
}

function gate(cwd) {
  let dir = cwd;
  while (true) {
    if (fs.existsSync(path.join(dir, 'check.sh'))) return { run: 'bash check.sh', patterns: [/check\.sh/], all: true };
    if (fs.existsSync(path.join(dir, 'package.json'))) return {
      run: 'typecheck and lint', patterns: [/\b(tsc|typecheck|type-check)\b/, /\b(lint|eslint|biome|oxlint)\b/], all: false
    };
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

let input = '';
process.stdin.on('data', c => { input += c; });
process.stdin.on('end', () => {
  let p;
  try { p = JSON.parse(input); } catch (_) { return output({}); }
  if (process.env.CRAFTKIT_GATE === 'off' || process.env.CRAFTKIT_PANELIST) return output({});
  const event = p.hook_event_name;
  const cwd = p.cwd || process.cwd();
  if (event === 'SessionStart') {
    const body = rules(cwd);
    return output(body ? { hookSpecificOutput: { hookEventName: event,
      additionalContext: 'CraftKit installed rules. Follow the applicable instructions below.\n\n' + body } } : {});
  }
  const session = String(p.session_id || '');
  if (!session) return output({});
  const file = statePath(session);
  let state = load(file);
  if (event === 'UserPromptSubmit') {
    // A Stop block creates an automatic prompt. Preserve its original baseline.
    if (!state || !state.pending) state = { baseline: snapshot(cwd), commands: [], blocks: 0, pending: false };
    else state.pending = false;
    state.turn = p.turn_id;
    save(file, state);
    const platform = detectPlatform(cwd).label;
    const selected = requestedSkill(p.prompt);
    return output({ hookSpecificOutput: { hookEventName: event, additionalContext:
      'CraftKit: classify this request against installed skills and workflows before work. ' +
      'For a match, activate its native $skill and follow its full SKILL.md. ' +
      'Use build, review, or ship for their respective workflows; use their sequential forms when spawning is unavailable. ' +
      'If none matches, state that briefly. After edits, run the project verification command and report its result.' +
      (platform ? '\nDetected platform: ' + platform + '.' : '') +
      (selected ? '\n\nExplicitly requested CraftKit skill or command bodies:\n\n' + selected : '') } });
  }
  if (!state) return output({});
  if (event === 'PostToolUse') {
    const ti = p.tool_input || {};
    if (p.tool_name === 'Bash') {
      const command = String(ti.command || ti.cmd || '');
      if (command) state.commands.push(command);
    }
    save(file, state);
    return output({});
  }
  if (event !== 'Stop') return output({});
  const required = gate(cwd);
  if (!required) { try { fs.unlinkSync(file); } catch (_) {} return output({}); }
  const files = changed(state.baseline, snapshot(cwd))
    .filter(n => !/(^|\/)scratchpad\//.test(n))
    .filter(n => required.all || CODE.test(n));
  if (!files.length || required.patterns.every(re => state.commands.some(c => re.test(c)))) {
    try { fs.unlinkSync(file); } catch (_) {}
    return output({});
  }
  if (state.blocks >= 2) { try { fs.unlinkSync(file); } catch (_) {} return output({}); }
  state.blocks++;
  state.pending = true;
  save(file, state);
  return output({ decision: 'block', reason:
    'CraftKit verification is still required after edits to ' + files.slice(0, 6).join(', ') + '. ' +
    'Run ' + required.run + ', then report the actual result. If it cannot run, explain why the change is unverified. ' +
    'Set CRAFTKIT_GATE=off to disable this gate.' });
});
