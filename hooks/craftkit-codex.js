#!/usr/bin/env node
// Codex has native lifecycle hooks, but its transcript is not a stable hook API.
// Keep the turn's small verification record from documented hook payloads instead.
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync, spawn } = require('child_process');
const { detectPlatform } = require('./craftkit-platform.js');

const CODE = /\.(ts|tsx|js|jsx|mjs|cjs|kt|kts|java|swift|m|mm|xml|gradle|strings|bzl|json)$/i;
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
  try { fs.writeFileSync(file, JSON.stringify(state), { mode: 0o600 }); } catch (_) { /* fail open */ }
};
const load = file => { try { return JSON.parse(read(file)); } catch (_) { return null; } };
// sync.sh writes one file per gate the config sets explicitly; absent means unset.
const gateValue = name => read(path.join(os.homedir(), '.craftkit-state', 'gate-' + name)).trim();

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
    const codex = body.match(/<!-- BEGIN CRAFTKIT-CODEX -->\s*([\s\S]*?)\s*<!-- END CRAFTKIT-CODEX -->/);
    return codex ? codex[1] : strip(body).trim();
  }).filter(Boolean).join('\n\n---\n\n');
}

function requestedSkill(prompt) {
  const names = new Set();
  for (const m of String(prompt || '').matchAll(/(?:^|\s)\$([a-z][a-z0-9-]*)\b/g)) names.add(m[1]);
  const slash = String(prompt || '').match(/^\s*\/([a-z][a-z0-9-]*)\b/);
  if (slash) names.add(slash[1]);
  const pointers = [];
  for (const name of [...names].slice(0, 3)) {
    const file = path.join(os.homedir(), '.agents', 'skills', name, 'SKILL.md');
    if (fs.existsSync(file)) pointers.push('$' + name + ': read ' + file);
  }
  return pointers.join('\n');
}

function rtkRead(p, cwd) {
  const command = p.tool_input && p.tool_input.command;
  if (p.tool_name !== 'Bash' || typeof command !== 'string' ||
      !/^\s*(?:git\s+(?:status|diff|log)\b|(?:rg|grep|ls)\b)/.test(command) ||
      /[;&|<>`$()\n\r\\]/.test(command) ||
      /(?:^|\s)--(?:output|pre|hostname-bin|ext-diff|textconv)(?:[=\s]|$)/.test(command.replace(/['"]/g, ''))) return {};
  const dir = process.env.CODEX_HOME || path.join(os.homedir(), '.codex');
  const binary = read(path.join(dir, 'hooks', 'rtk-path')).trim() || 'rtk';
  try {
    const response = JSON.parse(execFileSync(binary, ['hook', 'codex'], {
      cwd, input: JSON.stringify(p), encoding: 'utf8', timeout: 2000, stdio: ['pipe', 'pipe', 'ignore']
    }));
    const hook = response.hookSpecificOutput;
    if (hook && hook.hookEventName === 'PreToolUse' && hook.permissionDecision === 'allow' &&
        hook.updatedInput && typeof hook.updatedInput.command === 'string' &&
        hook.updatedInput.command.startsWith('rtk ')) {
      // Keep reads visible to normal Codex approval checks; never rewrite mutation commands.
      const prefix = binary === 'rtk' ? binary : "'" + binary.replace(/'/g, "'\\''") + "'";
      return { hookSpecificOutput: { ...hook, updatedInput: {
        ...p.tool_input, command: prefix + hook.updatedInput.command.slice(3)
      } } };
    }
  } catch (_) { /* missing or incompatible RTK leaves the original command intact */ }
  return {};
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
        dirty[name] = crypto.createHash('sha256').update(fs.readFileSync(path.join(root, name))).digest('hex');
      } catch (_) { dirty[name] = null; }
    }
    return { root, head, dirty };
  } catch (_) { return null; }
}

function changed(before, after) {
  if (!before || !after || before.root !== after.root) return [];
  const names = new Set(Object.keys(before.dirty).concat(Object.keys(after.dirty)));
  const committed = new Set();
  if (before.head !== after.head) {
    try {
      const files = execFileSync('git', ['-C', after.root, 'diff', '--name-only', before.head, after.head],
        { encoding: 'utf8', timeout: 5000 }).trim();
      files.split('\n').filter(Boolean).forEach(n => committed.add(n));
    } catch (_) { /* the dirty set still works */ }
  }
  return [...new Set([...committed, ...[...names].filter(n => before.dirty[n] !== after.dirty[n])])];
}

function gate(cwd) {
  let dir = cwd;
  while (true) {
    if (fs.existsSync(path.join(dir, 'check.sh'))) return {
      run: 'bash check.sh', patterns: [/^(?:(?:bash|sh) )?(?:\S*\/)?check\.sh(?: |$)/], all: true
    };
    if (fs.existsSync(path.join(dir, 'package.json'))) return {
      run: 'typecheck and lint', patterns: [
        /^(?:(?:pnpm|npm|yarn|npx) (?:run |exec )?)?(?:tsc|typecheck|type-check)(?: |$)/,
        /^(?:(?:pnpm|npm|yarn|npx) (?:run |exec )?)?(?:deplint|lint|eslint|biome|oxlint)(?: |$)/
      ], all: false
    };
    const entries = fs.readdirSync(dir);
    if (entries.some(n => /^(settings|build)\.gradle(\.kts)?$/.test(n))) return {
      run: './gradlew :<module>:lintGeneralDebug :<module>:testGeneralDebugUnitTest',
      patterns: [/^(?:\S*\/)?gradlew .*\blint\w*/, /^(?:\S*\/)?gradlew .*\btest\w*/], all: false
    };
    if (entries.some(n => /\.xc(odeproj|workspace)$/.test(n) || n === 'Podfile' || n === 'Package.swift')) return {
      run: 'the project test command and swiftlint lint', patterns: [
        /^(?:bazelisk|bazel|swift) test(?: |$)|^xcodebuild .*\btest\b/,
        /^swiftlint(?: lint)?(?: |$)/
      ], all: false
    };
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

function executed(command) {
  // Only direct foreground invocations count; quoted mentions stay arguments to echo.
  if (/[`$()<>]|\|\||\|(?!\|)/.test(command)) return [];
  const tokens = command.match(/"(?:\\.|[^"\\])*"|'[^']*'|&&|[;&\n]|[^\s;'"&]+/g) || [];
  const commands = [[]];
  for (const token of tokens) {
    if ([';', '\n', '&'].includes(token)) return [];
    if (token === '&&') commands.push([]);
    else commands[commands.length - 1].push(token.replace(/^(['"])(.*)\1$/, '$2'));
  }
  return commands.map(args => {
    if (args[0] === 'rtk') args.shift();
    if (args[0]) args[0] = path.basename(args[0]);
    return args.join(' ');
  });
}

function exitCode(response) {
  if (response && typeof response.exit_code === 'number') return response.exit_code;
  return null;
}

function checks(file) {
  return read(file + '.checks').split('\n').filter(Boolean).flatMap(line => {
    try { return [JSON.parse(line)]; } catch (_) { return []; }
  });
}

// Codex 0.160 sends only stdout to PostToolUse, so verification observes the exit here.
function runVerification() {
  const [file, id, token] = process.argv.slice(3);
  const state = load(file);
  const start = state && checks(file).find(r => r.phase === 'start' && r.id === id && r.token === token &&
    r.at >= state.started && r.snapshot);
  if (!start) return process.exit(1);
  const before = snapshot(start.cwd);
  const child = spawn(process.env.SHELL || '/bin/sh', ['-c', start.command], {
    cwd: start.cwd, stdio: 'inherit'
  });
  child.on('error', () => process.exit(1));
  child.on('close', code => {
    const current = snapshot(start.cwd);
    const latest = load(file);
    if (code === 0 && latest && start.at >= latest.started && before &&
        JSON.stringify(start.snapshot) === JSON.stringify(before) &&
        JSON.stringify(before) === JSON.stringify(current)) {
      try {
        fs.appendFileSync(file + '.checks', JSON.stringify({
          at: Date.now(), id, phase: 'end', commands: start.commands, snapshot: current
        }) + '\n', { mode: 0o600 });
      } catch (_) {}
    }
    process.exit(code === null ? 1 : code);
  });
}

// Director mode port of hooks/gate-delegate.js, opt-in (CRAFTKIT_DELEGATE=on). Codex
// 0.160.0 rejects permissionDecision "ask" as unsupported, so this can only deny, and no
// hook payload field tells `codex exec` from an interactive session (permission_mode only
// mirrors the approval policy), so a default-on deny could stall automation.
// The Claude gate's source set, narrower than the verify gate's CODE, which also counts config.
const DELEGATE_EXT = /\.(ts|tsx|js|jsx|mjs|cjs|kt|java|swift|m|mm)$/i;
const THROWAWAY = /\/scratchpad\/|^\/tmp\/|^\/private\/tmp\/|^\/var\/folders\//;
// Copied from gate-delegate.js, held identical by scripts/test-codex.py.
// ponytail: perl -i, a heredoc piped to an interpreter, in-script writes, and escaped
// quotes inside a quoted span are missed. ceiling: a shell write in those shapes reaches
// the 3rd file unasked. upgrade: diff git state per call, as the verify gate does at Stop.
const QUOTED = `"[^"]*"|'[^']*'`;
function shellWrites(command, cwd) {
  const out = [];
  let m;
  const redirect = new RegExp(QUOTED + `|(?<![0-9&<>])>>?\\s*(?!\\/dev\\/|&)(${QUOTED}|[^\\s;&|<>"']+)`, 'g');
  while ((m = redirect.exec(command)) !== null) if (m[1]) out.push(m[1].replace(/^(["'])(.*)\1$/, '$2'));
  const operands = new RegExp(QUOTED + `|\\b(?:sed\\s+-i\\b|tee\\b)((?:${QUOTED}|[^;&|"'])*)`, 'g');
  while ((m = operands.exec(command)) !== null) if (m[1]) out.push.apply(out, m[1].split(/[\s'"]+/));
  return out.filter(t => DELEGATE_EXT.test(t)).map(t => path.resolve(cwd, t));
}

// A CraftKit profile installed read-only by adapters/codex.sh cannot take the edits.
function readOnlyProfile(type) {
  if (!/^[A-Za-z0-9_-]+$/.test(type)) return false;
  const body = read(path.join(process.env.CODEX_HOME || path.join(os.homedir(), '.codex'), 'agents', type + '.toml'));
  return body.startsWith('# CraftKit managed agent\n') && /^sandbox_mode = "read-only"$/m.test(body);
}

function patchFiles(text, cwd) {
  const files = [];
  for (const m of text.matchAll(/^\*\*\* (Add File|Update File|Delete File|Move to): (.+)$/gm)) {
    // A rename's Update header names the old path; the file that results is its Move to.
    if (m[1] === 'Move to') files.pop();
    files.push(path.resolve(cwd, m[2].trim()));
  }
  return files;
}

function prPreflight(p, cwd) {
  if (!['Bash', 'exec_command'].includes(p.tool_name)) return null;
  const ti = p.tool_input || {};
  const command = String(ti.command || ti.cmd || '');
  if (!/^\s*(?:rtk\s+)?(?:\/[^\s]+\/)?gh\s+pr\s+create\b/.test(command)) return null;
  const deny = reason => ({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny',
    permissionDecisionReason: 'PR preflight: ' + reason } });
  if (process.env.GH_REPO) return deny('GH_REPO overrides are unsupported; unset it and run from the target worktree.');
  const shellSyntax = command.replace(/'[^'\n]*'|"[^"\n]*"/g,
    quoted => quoted[0] === "'" ? '' : quoted.replace(/[^$`\\\n\r]/g, ''));
  if (/[`$()<>|;&\n\r\\#*?\[\]{}~!]/.test(shellSyntax)) return deny('Use a direct gh pr create command without shell expansion or chaining.');
  const tokens = command.match(/"[^"\n]*"|'[^'\n]*'|[^\s"']+/g) || [];
  if (tokens.join(' ').replace(/\s+/g, ' ') !== command.trim().replace(/\s+/g, ' ')) return deny('Use simple complete quoted arguments.');
  const args = tokens.map(token => token.replace(/^(['"])(.*)\1$/, '$2'));
  if (args.some(arg => /^(--repo(?:=|$)|--head(?:=|$)|-R|-H)/.test(arg))) return deny('Repository and head overrides are unsupported; run from the target worktree.');
  const bodyIndex = args.indexOf('--body-file');
  if (bodyIndex < 0 || args.lastIndexOf('--body-file') !== bodyIndex || !args[bodyIndex + 1] ||
      args[bodyIndex + 1].startsWith('-') || args.some(arg => /^(--body(?:=|$)|--body-file=|-b|-F)/.test(arg))) {
    return deny('Provide --body-file <markdown path>; inline body and stdin are unsupported.');
  }
  try {
    const target = typeof ti.workdir === 'string' ? path.resolve(cwd, ti.workdir) : cwd;
    const helper = require('./craftkit-pr-preflight.js');
    const record = JSON.parse(fs.readFileSync(helper.recordPath(target), 'utf8'));
    const body = fs.readFileSync(path.resolve(target, args[bodyIndex + 1]), 'utf8');
    const reason = helper.check(target, body, record);
    if (reason) return deny(reason);
    const valueFlags = new Set(['--title', '-t', '--body-file', '--base', '-B', '--label', '-l', '--reviewer', '-r', '--assignee', '-a', '--milestone', '-m', '--project', '-p', '--template', '-T']);
    let draft = false;
    for (let i = 0; i < args.length; i++) {
      if (valueFlags.has(args[i])) i++;
      else if (args[i] === '--draft') draft = true;
    }
    if (record.limitations.length && (!draft || args.some(arg => arg === '--' || /^(--draft=|-d)/.test(arg)))) {
      return deny('Validation is incomplete: use --draft and describe limitations in Evidence.');
    }
    return null;
  } catch (_) { return deny('Preflight helper, saved record or body file is missing or invalid. Run the preflight CLI first.'); }
}

function agentContract(p) {
  // flag: gates.routing. off: spawns pass through without a model/context contract. remove: never, routing is a user choice.
  if (p.tool_name !== 'spawn_agent' || gateValue('routing') === 'off') return null;
  const ti = p.tool_input || {};
  const deny = reason => ({ hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny',
    permissionDecisionReason: 'Agent contract: ' + reason } });
  if (ti.fork_turns !== 'none') return deny('Use fork_turns: none and supply the task, scoped source, project conventions and verification in message.');
  const decision = typeof ti.message === 'string' && ti.message.match(
    /^MODEL: (bounded|escalation|implementation|critical-review|user-pin|profile-pin|unavailable) - (\S[^\r\n]*)\r?\n/);
  if (!decision) return deny('Start message with MODEL: <reason> - <explanation> and a newline. Reasons: bounded, escalation, implementation, critical-review, user-pin, profile-pin, unavailable.');
  if (!ti.message.slice(decision[0].length).trim()) return deny('Include the task packet after the model decision.');
  const model = typeof ti.model === 'string' && ti.model.trim();
  if (decision[1] === 'bounded' && !model) return deny('Bounded work needs an explicit runtime-listed cheaper model; use unavailable with an explanation if model/cost information is absent.');
  if (decision[1] === 'escalation' && !model) return deny('Escalation needs an explicit runtime-listed stronger model; use unavailable and disclose the fallback if none is available.');
  if (model && ['implementation', 'critical-review', 'unavailable'].includes(decision[1])) {
    return deny('Omit model to inherit for implementation, critical-review or unavailable; explicit pins use user-pin or profile-pin.');
  }
  return null;
}

function delegate(p, file, cwd) {
  // flag: gates.director. off or unset: no delegate gate, unless unset with CRAFTKIT_DELEGATE=on. remove: never, it is a user choice.
  const director = gateValue('director');
  if ((director ? director !== 'on' : process.env.CRAFTKIT_DELEGATE !== 'on') || p.agent_id || !p.turn_id) return null;
  const ti = p.tool_input || {};
  const text = String(ti.command || ti.cmd || '');
  const log = file + '.delegate';
  const id = String(p.tool_use_id || crypto.randomUUID());
  const append = lines => {
    try { fs.appendFileSync(log, lines.map(l => p.turn_id + '\t' + id + '\t' + l + '\n').join(''), { mode: 0o600 }); }
    catch (_) {}
  };
  if (/spawn_agent$/.test(String(p.tool_name))) {
    if (!readOnlyProfile(String(ti.agent_type || '').trim())) append(['spawn_agent']);
    return null;
  }
  // apply_patch sends the raw patch as `command`; a shell `apply_patch <<EOF` carries the same headers.
  const patch = p.tool_name === 'apply_patch' || text.includes('*** Begin Patch');
  const mine = (patch ? patchFiles(text, cwd) : []).concat(p.tool_name === 'Bash' ? shellWrites(text, cwd) : [])
    .filter(f => DELEGATE_EXT.test(f) && !THROWAWAY.test(f));
  if (!mine.length) return null;
  // Appended before reading, so of two parallel calls the later reader sees both; a denied
  // call then retracts its own lines, so a refused file never counts against a later edit.
  append(mine);
  const rows = read(log).split('\n').map(l => l.split('\t')).filter(r => r[0] === String(p.turn_id) && r.length === 3);
  const retracted = new Set(rows.filter(r => r[2] === '-').map(r => r[1]));
  const live = rows.filter(r => r[2] !== '-' && !retracted.has(r[1])).map(r => r[2]);
  const files = new Set(live);
  if (files.has('spawn_agent') || files.size < 3) return null;
  append(['-']);
  return { hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason:
    'This is source file ' + files.size + ' edited this turn (' + mine[0] + '). Director mode wants work ' +
    'touching 3+ files delegated: spawn_agent with a contract that includes the verify command, then wait_agent and ' +
    'integrate its result. Re-plan the work as a delegation instead of editing directly. ' +
    'Set gates.director=off in ~/.craftkit-state/config, or unset CRAFTKIT_DELEGATE when it is not set there, to disable this gate.' } };
}

function clear(file) {
  for (const name of [file, file + '.checks', file + '.delegate']) {
    try { fs.unlinkSync(name); } catch (_) {}
  }
}

let input = '';
if (process.argv[2] === '--verify') runVerification();
else {
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
  if (event === 'PreToolUse') {
    const agentDenied = agentContract(p);
    if (agentDenied) return output(agentDenied);
    const prDenied = prPreflight(p, cwd);
    if (prDenied) return output(prDenied);
    let denied = null;
    try { denied = delegate(p, file, cwd); } catch (_) { /* fail open */ }
    if (denied) return output(denied);
  }
  let state = load(file);
  if (state && !Number.isFinite(state.started)) {
    state.started = Date.now();
    delete state.commands;
    save(file, state);
  }
  if (event === 'UserPromptSubmit') {
    try { fs.unlinkSync(file + '.delegate'); } catch (_) {}
    // A Stop block creates an automatic prompt. Preserve its original baseline.
    if (!state || !state.pending) state = { baseline: snapshot(cwd), started: Date.now(), blocks: 0, pending: false };
    else state.pending = false;
    state.turn = p.turn_id;
    save(file, state);
    const platform = detectPlatform(cwd).label;
    const selected = requestedSkill(p.prompt);
    // flag: gates.routing / gates.verify. off: omit that group's prompt instructions. remove: never, the groups are user choices.
    const routing = gateValue('routing') !== 'off' ?
      'Follow installed Codex skill routing.' : '';
    const verify = gateValue('verify') !== 'off' ? 'After edits, run the project verification command and report its result.' : '';
    return output({ hookSpecificOutput: { hookEventName: event, additionalContext:
      'CraftKit: ' + [routing, verify].filter(Boolean).join(' ') +
      (platform ? '\nDetected platform: ' + platform + '.' : '') +
      (selected ? '\n\nExplicitly requested CraftKit skills:\n' + selected : '') } });
  }
  const compressed = event === 'PreToolUse' ? rtkRead(p, cwd) : {};
  if (!state) return output(compressed);
  // flag: gates.verify. off: no verification bookkeeping and no Stop block. remove: never, it is a user choice.
  if (gateValue('verify') === 'off') {
    if (event === 'Stop') clear(file);
    return output(compressed);
  }
  if (event === 'PreToolUse' || event === 'PostToolUse') {
    const ti = p.tool_input || {};
    if (p.tool_name === 'Bash') {
      const command = String(ti.command || ti.cmd || '');
      const required = gate(cwd);
      const commands = executed(command);
      if (required && required.patterns.some(re => commands.some(c => re.test(c)))) {
        const current = snapshot(cwd);
        const phase = event === 'PreToolUse' ? 'start' : 'end';
        if (phase === 'end') {
          const start = checks(file).find(record => record.phase === 'start' &&
            record.id === p.tool_use_id && record.at >= state.started && record.snapshot &&
            JSON.stringify(record.snapshot) === JSON.stringify(current));
          if (!start || exitCode(p.tool_response) !== 0) return output({});
        }
        if (!p.tool_use_id) return output({});
        const record = { at: Date.now(), id: p.tool_use_id, phase, commands, snapshot: current };
        if (phase === 'start') Object.assign(record, { command, cwd, token: crypto.randomUUID() });
        // Each hook appends one record, so concurrent subagents cannot overwrite peers.
        try { fs.appendFileSync(file + '.checks', JSON.stringify(record) + '\n', { mode: 0o600 }); } catch (_) {}
        if (phase === 'start' && current) {
          const quote = s => "'" + String(s).replace(/'/g, "'\\''") + "'";
          return output({ hookSpecificOutput: { hookEventName: event, permissionDecision: 'allow', updatedInput: {
            command: [process.execPath, __filename, '--verify', file, p.tool_use_id, record.token].map(quote).join(' ')
          } } });
        }
      }
    }
    return output(compressed);
  }
  if (event !== 'Stop') return output({});
  const required = gate(cwd);
  if (!required) { clear(file); return output({}); }
  const current = snapshot(cwd);
  const files = changed(state.baseline, current)
    .filter(n => !/(^|\/)scratchpad\//.test(n))
    .filter(n => required.all || CODE.test(n));
  const verified = checks(file).filter(record => record.phase === 'end' && record.at >= state.started && record.snapshot &&
    JSON.stringify(record.snapshot) === JSON.stringify(current));
  if (!files.length || required.patterns.every(re => verified.some(record => record.commands.some(c => re.test(c))))) {
    clear(file);
    return output({});
  }
  if (state.blocks >= 2) { clear(file); return output({}); }
  state.blocks++;
  state.pending = true;
  save(file, state);
  return output({ decision: 'block', reason:
    'CraftKit verification is still required after edits to ' + files.slice(0, 6).join(', ') + '. ' +
    'Run ' + required.run + ', then report the actual result. If it cannot run, explain why the change is unverified. ' +
    'Set CRAFTKIT_GATE=off to disable this gate.' });
});
}
