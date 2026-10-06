#!/usr/bin/env node
// CraftKit PreToolUse gate: from the second distinct source file edited in one main-session
// turn, every source edit asks to hand the work to a background agent (director mode, rule
// 12a), until the turn spawns one. Asking only once let a headless batch land the rest.
// Rule text alone measured 0/5 delegation on multi-file tasks (director-mode plan, T2b):
// the model read rule 12a and overruled it on task size. This is the half that can stop
// the call. "ask", never "deny": the human keeps the override, and a declined ask (auto
// under headless) is what forces the re-plan.
// Cost: approving direct multi-file work interactively means one prompt per further edit.
// Unattended sessions pass: an ask there is auto-denied, which would fail a scripted job
// outright instead of redirecting a human. CLAUDE_CODE_SESSION_ATTENDED is 0 under
// claude -p and 1 interactively (observed on 2.1.291); unset reads as attended.
// Escape hatches: CRAFTKIT_DELEGATE=off (this gate), CRAFTKIT_GATE=off (every gate).

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
// A quoted span is consumed whole before either shape can match inside it, so a `>` in a
// commit message or grep pattern is not a write; a quoted target is unquoted.
// ponytail: perl -i, a heredoc piped to an interpreter, in-script writes, and escaped
// quotes inside a quoted span are missed. ceiling: a shell write in those shapes reaches
// the 2nd file unasked. upgrade: diff git state per call, as the verify gate does at Stop.
const QUOTED = `"[^"]*"|'[^']*'`;
function shellWrites(command, cwd) {
  const out = [];
  let m;
  const redirect = new RegExp(QUOTED + `|(?<![0-9&<>])>>?\\s*(?!\\/dev\\/|&)(${QUOTED}|[^\\s;&|<>"']+)`, 'g');
  while ((m = redirect.exec(command)) !== null) if (m[1]) out.push(m[1].replace(/^(["'])(.*)\1$/, '$2'));
  const operands = new RegExp(QUOTED + `|\\b(?:sed\\s+-i\\b|tee\\b)((?:${QUOTED}|[^;&|"'])*)`, 'g');
  while ((m = operands.exec(command)) !== null) if (m[1]) out.push.apply(out, m[1].split(/[\s'"]+/));
  return out.filter(t => CODE_EXT.test(t)).map(t => path.resolve(cwd, t));
}

// PreToolUse for parallel calls in one assistant message can run before the sibling
// tool_use entries reach the transcript, so the gate keeps its own record of what it saw.
// Appends are one short line each, which concurrent hooks cannot interleave mid-line, and
// each call appends before it reads, so of two concurrent calls the later reader sees both.
// ponytail: the file grows one line per source edit for the session's lifetime. ceiling:
// a very long session reads a few hundred KB per call. upgrade: truncate on a new turnId.
function seen(session, turnId, files) {
  const log = path.join(os.tmpdir(), 'craftkit-gate', session + '.delegate-files');
  try {
    fs.mkdirSync(path.dirname(log), { recursive: true });
    fs.appendFileSync(log, files.map(f => turnId + '\t' + f + '\n').join(''));
  } catch (e) { /* unrecorded: the transcript count still applies */ }
  try {
    return fs.readFileSync(log, 'utf8').split('\n')
      .filter(l => l.startsWith(turnId + '\t')).map(l => l.slice(turnId.length + 1));
  } catch (e) { return []; }
}

// Explore and Plan are built in; a craftkit profile is read-only when its installed
// frontmatter grants no write tool. agents/ sits beside hooks/ under ~/.claude.
const WRITE_TOOL = /\b(Edit|Write|MultiEdit|NotebookEdit|Bash)\b|\*/;
function readOnly(type) {
  if (type === 'Explore' || type === 'Plan') return true;
  if (!/^[A-Za-z0-9_-]+$/.test(type)) return false;
  try {
    const tools = fs.readFileSync(path.join(__dirname, '..', 'agents', type + '.md'), 'utf8')
      .match(/^---\n[\s\S]*?^tools:(.*)$/m);
    return Boolean(tools) && !WRITE_TOOL.test(tools[1]);
  } catch (e) { return false; }
}
// Only a spawn that takes the work counts: a background agent, or one that can edit. A
// foreground read-only lookup leaves every edit with the main session.
const handedOff = s => s.background || !readOnly(s.type || 'general-purpose');

const pass = () => process.stdout.write('{}');

let input = '';
process.stdin.on('data', c => { input += c; });
process.stdin.on('end', () => {
  try { gate(); } catch (e) { pass(); }
});

function gate() {
  if (process.env.CRAFTKIT_GATE === 'off' || process.env.CRAFTKIT_DELEGATE === 'off') return pass();
  if (process.env.CLAUDE_CODE_SESSION_ATTENDED === '0') return pass();

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
  // turn that handed the work to an agent has delegated.
  if (turn.sidechain || turn.notification || turn.spawns.some(handedOff)) return pass();

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
        'Set CRAFTKIT_DELEGATE=off to disable this gate.'
    }
  }));
}
