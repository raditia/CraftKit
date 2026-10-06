#!/usr/bin/env node
// CraftKit PreToolUse gate: from the second distinct source file edited in one main-session
// turn, every source edit asks to hand the work to a background agent (director mode, rule
// 12a), until the turn spawns one. Asking only once let a headless batch land the rest.
// Rule text alone measured 0/5 delegation on multi-file tasks (director-mode plan, T2b):
// the model read rule 12a and overruled it on task size. This is the half that can stop
// the call. "ask", never "deny": the human keeps the override, and a declined ask (auto
// under headless) is what forces the re-plan.
// Cost: approving direct multi-file work interactively means one prompt per further edit.
// Escape hatch: CRAFTKIT_GATE=off.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { currentTurn } = require(path.join(__dirname, 'craftkit-transcript.js'));

// Same extension set as gate-skill-first and gate-verify-on-stop, so a planning doc
// (docs/planning/*.md) is never source and never counts toward the threshold.
const CODE_EXT = /\.(ts|tsx|js|jsx|mjs|cjs|kt|java|swift|m|mm)$/i;
// Copied from gate-verify-on-stop.js rather than required: that file is a hook, not a
// module, and requiring it would run its stdin handler.
const THROWAWAY = /\/scratchpad\/|^\/tmp\/|^\/private\/tmp\/|^\/var\/folders\//;
const counts = f => CODE_EXT.test(f) && !THROWAWAY.test(f);

// The files a shell command writes: redirect targets, and the operands of sed -i and tee.
// Same write shapes as wroteViaShell in gate-verify-on-stop.js, narrowed to the written
// paths so `node src/a.js > out.log` does not count src/a.js as edited.
// ponytail: perl -i, a heredoc piped to an interpreter, and in-script writes are missed.
// ceiling: a shell write in those shapes reaches the 2nd file unasked. upgrade: diff git
// state per call, as the verify gate does at Stop.
function shellWrites(command, cwd) {
  const out = [];
  let m;
  const redirect = /(?:^|[^0-9&<>])>>?\s*(?!\/dev\/|&)([^\s;&|<>]+)/g;
  while ((m = redirect.exec(command)) !== null) out.push(m[1]);
  const operands = /\b(?:sed\s+-i\b|tee\b)([^;&|]*)/g;
  while ((m = operands.exec(command)) !== null) out.push.apply(out, m[1].split(/[\s'"]+/));
  return out.filter(t => CODE_EXT.test(t)).map(t => path.resolve(cwd, t));
}

// PreToolUse for parallel calls in one assistant message can run before the sibling
// tool_use entries reach the transcript, so the gate keeps its own record of what it saw.
// Appends are one short line each, which concurrent hooks cannot interleave mid-line.
// ponytail: the file grows one line per source edit for the session's lifetime. ceiling:
// a very long session reads a few hundred KB per call. upgrade: truncate on a new turnId.
function seen(session, turnId, files) {
  const log = path.join(os.tmpdir(), 'craftkit-gate', session + '.delegate-files');
  let prior = [];
  try {
    prior = fs.readFileSync(log, 'utf8').split('\n')
      .filter(l => l.startsWith(turnId + '\t')).map(l => l.slice(turnId.length + 1));
  } catch (e) { /* nothing recorded on this session yet */ }
  try {
    fs.mkdirSync(path.dirname(log), { recursive: true });
    fs.appendFileSync(log, files.map(f => turnId + '\t' + f + '\n').join(''));
  } catch (e) { /* unrecorded: the transcript count still applies */ }
  return prior;
}

const pass = () => process.stdout.write('{}');

let input = '';
process.stdin.on('data', c => { input += c; });
process.stdin.on('end', () => {
  if (process.env.CRAFTKIT_GATE === 'off') return pass();

  let payload;
  try { payload = JSON.parse(input); } catch (e) { return pass(); }

  const ti = payload.tool_input || {};
  const cwd = String(payload.cwd || process.cwd());
  const mine = (payload.tool_name === 'Bash'
    ? shellWrites(String(ti.command || ''), cwd)
    : [String(ti.file_path || ti.notebook_path || '')]).filter(counts);
  if (!mine.length) return pass();
  const file = mine[0];

  if (!payload.transcript_path) return pass();
  const turn = currentTurn(payload.transcript_path);
  // An unreadable transcript is a gate that cannot see, so it must not block.
  if (!turn.readable) return pass();
  // A subagent is the delegate already, a background-task event is not a prompt, and a
  // turn that spawned an agent has delegated.
  if (turn.sidechain || turn.notification || turn.delegated) return pass();

  const session = String(payload.session_id || 'nosession');
  const recorded = turn.turnId ? seen(session, turn.turnId, mine) : [];
  // The current call may already be in the transcript, so dedupe rather than add one.
  const shell = [].concat.apply([], turn.commands.map(c => shellWrites(c, cwd)));
  const files = new Set(turn.edits.concat(shell).filter(counts).concat(recorded, mine));
  if (files.size < 2) return pass();

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'ask',
      permissionDecisionReason:
        'This is source file ' + files.size + ' edited this turn (' + file + '). Director mode (rule 12a) ' +
        'wants multi-file work handed to a background agent: Agent tool with run_in_background: true, ' +
        'and a contract that includes the verify command. If this is declined, re-plan the work ' +
        'as a delegation instead of continuing to edit directly.\n' +
        'Set CRAFTKIT_GATE=off to disable this gate.'
    }
  }));
});
