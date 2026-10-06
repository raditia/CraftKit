#!/usr/bin/env node
// CraftKit PreToolUse gate: the second distinct source file edited in one main-session
// turn asks to hand the work to a background agent (director mode, rule 12a).
// Rule text alone measured 0/5 delegation on multi-file tasks (director-mode plan, T2b):
// the model read rule 12a and overruled it on task size. This is the half that can stop
// the call. "ask", never "deny": the human keeps the override, and a declined ask (auto
// under headless) is what forces the re-plan.
// Escape hatch: CRAFTKIT_GATE=off.

const path = require('path');
const { currentTurn, onceInTurn } = require(path.join(__dirname, 'craftkit-transcript.js'));

// Same extension set as gate-skill-first and gate-verify-on-stop, so a planning doc
// (docs/planning/*.md) is never source and never counts toward the threshold.
const CODE_EXT = /\.(ts|tsx|js|jsx|mjs|cjs|kt|java|swift|m|mm)$/i;
// Copied from gate-verify-on-stop.js rather than required: that file is a hook, not a
// module, and requiring it would run its stdin handler.
const THROWAWAY = /\/scratchpad\/|^\/tmp\/|^\/private\/tmp\/|^\/var\/folders\//;
const counts = f => CODE_EXT.test(f) && !THROWAWAY.test(f);

const pass = () => process.stdout.write('{}');

let input = '';
process.stdin.on('data', c => { input += c; });
process.stdin.on('end', () => {
  if (process.env.CRAFTKIT_GATE === 'off') return pass();

  let payload;
  try { payload = JSON.parse(input); } catch (e) { return pass(); }

  const ti = payload.tool_input || {};
  const file = String(ti.file_path || ti.notebook_path || '');
  if (!counts(file)) return pass();

  if (!payload.transcript_path) return pass();
  const turn = currentTurn(payload.transcript_path);
  // An unreadable transcript is a gate that cannot see, so it must not block.
  if (!turn.readable) return pass();
  // A subagent is the delegate already, and a background-task event is not a prompt.
  if (turn.sidechain || turn.notification) return pass();

  // The current call may already be in the transcript, so dedupe rather than add one.
  const files = new Set(turn.edits.filter(counts).concat(file));
  if (files.size < 2) return pass();

  const session = String(payload.session_id || 'nosession');
  if (turn.turnId && !onceInTurn(session, turn.turnId, 'delegate')) return pass();

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'ask',
      permissionDecisionReason:
        'This is the 2nd source file edited this turn (' + file + '). Director mode (rule 12a) ' +
        'wants multi-file work handed to a background agent: Agent tool with run_in_background: true, ' +
        'and a contract that includes the verify command. If this is declined, re-plan the work ' +
        'as a delegation instead of continuing to edit directly.\n' +
        'Set CRAFTKIT_GATE=off to disable this gate.'
    }
  }));
});
