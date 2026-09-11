#!/usr/bin/env node
// CraftKit PreToolUse gate: editing source code requires a skill invoked in this turn.
// The UserPromptSubmit routing hook only injects text, and text is advisory, which is
// how an agent announces a skill and then hand-rolls the work anyway. This is the half
// that can stop the call.
// Scoped to the session, not the turn: the measured misses are continuations of work that
// routed several turns earlier. Decision is "ask", never "deny": the human keeps the
// override, the agent does not.
// Escape hatch: CRAFTKIT_GATE=off.

const path = require('path');
const { currentTurn, onceInTurn } = require(path.join(__dirname, 'craftkit-transcript.js'));

const CODE_EXT = /\.(ts|tsx|js|jsx|mjs|cjs|kt|java|swift|m|mm)$/i;

function hint(file) {
  if (/\.(kt|java)$/i.test(file)) return '/android-scaffold · /android-test · /android-review';
  if (/\.(swift|m|mm)$/i.test(file)) return '/ios-scaffold · /ios-test · /ios-review';
  return '/parallel-build (feature) · /fix (bug) · /fe-test (tests) · /fe-scaffold (new module)';
}

const pass = () => process.stdout.write('{}');

let input = '';
process.stdin.on('data', c => { input += c; });
process.stdin.on('end', () => {
  if (process.env.CRAFTKIT_GATE === 'off') return pass();

  let payload;
  try { payload = JSON.parse(input); } catch (e) { return pass(); }

  const ti = payload.tool_input || {};
  const file = String(ti.file_path || ti.notebook_path || '');
  if (!CODE_EXT.test(file)) return pass();
  // Scratchpad files are throwaway by design and route to no skill.
  if (/\/scratchpad\/|^\/tmp\/|^\/private\/tmp\//.test(file)) return pass();

  if (!payload.transcript_path) return pass();
  const turn = currentTurn(payload.transcript_path);
  // An unreadable transcript is a gate that cannot see, so it must not block.
  if (!turn.readable) return pass();
  if (turn.skills.length || turn.slashCommand) return pass();
  // Session scope, not turn scope. T-1 measured 76 source-editing turns: asking on every
  // unrouted one fires at 62%, while asking only when the session has never routed fires
  // at 18% and still catches the miss population. The turns in between are continuations
  // ("apply the fixes", "go with option 2") whose routing decision was made earlier, and
  // re-asking there is the click-through training this gate cannot afford.
  if (turn.priorSkills > 0) return pass();
  // A background-task event is not a prompt and carries no routing intent.
  if (turn.notification) return pass();
  // A subagent gets its own transcript, so the parent's Skill call is not in it and every
  // subagent edit would prompt. The parent turn is the right place to enforce routing, and
  // a background agent may have no one able to answer the prompt anyway.
  if (turn.sidechain) return pass();

  const session = String(payload.session_id || 'nosession');
  if (turn.turnId && !onceInTurn(session, turn.turnId, 'asked')) return pass();

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'ask',
      permissionDecisionReason:
        'No skill was invoked this turn, and this edits source: ' + file + '\n' +
        'Announcing a skill is not invoking it. Call the Skill tool, or state why none applies.\n' +
        'Likely: ' + hint(file) + '\n' +
        'Approve to edit unrouted. Set CRAFTKIT_GATE=off to disable this gate.'
    }
  }));
});
