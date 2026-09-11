#!/usr/bin/env node
// CraftKit Stop gate: a turn that edited source cannot end without running this
// project's verification command. Closes the gap where the agent reports done, having
// skipped the gates the skill told it to run, because nothing checked the claim.
// Blocks at most once per stop attempt (stop_hook_active), so there is no loop.
// Escape hatch: CRAFTKIT_GATE=off.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { currentTurn } = require(path.join(__dirname, 'craftkit-transcript.js'));

const CODE_EXT = /\.(ts|tsx|js|jsx|mjs|cjs|kt|java|swift|m|mm)$/i;

// Scope for the self-pass refusal, deliberately not CODE_EXT: this repo's source is shell
// and Node, so check.sh and sync.sh are code the rubric applies to, while a Markdown spec
// edit is not and must not demand a code self-pass.
const RUBRIC_EXT = /\.(ts|tsx|js|jsx|mjs|cjs|kt|java|swift|m|mm|sh|bash|zsh)$/i;

// karpathy-guidelines rule 2 requires this line from any turn that writes or edits code,
// and until now nothing checked it. Line-anchored and fence-stripped for the reason
// gate-announce-honored already needed both: the string appears in 9 source files, so a
// mid-sentence mention or a fenced example is documentation, not a claim about this turn.
// The leading-marker set includes a backtick because the first live turn this gate ran on
// wrote its claim as `ponytail self-pass: clean` and was refused. Line-anchoring is what
// rejects a quotation, not the absence of backticks: a prose mention reads "the rule wants
// a `ponytail self-pass:` line", which does not start the line.
const SELF_PASS = /^[ \t]*(?:[-*>]\s*)?[`*]{0,3}ponytail self-pass\b/im;

// Walk up for the project's own gate. check.sh outranks package.json: a repo that
// ships one has declared it the gate, and craftkit itself has both.
function requiredGate(startDir) {
  let dir = startDir;
  for (let i = 0; i < 40; i++) {
    if (fs.existsSync(path.join(dir, 'check.sh'))) {
      return {
        run: 'bash check.sh',
        patterns: [/check\.sh/],
        gatesEveryFile: true
      };
    }
    if (fs.existsSync(path.join(dir, 'package.json'))) {
      return {
        run: 'rtk tsc --noEmit  AND  rtk lint <changed files>',
        patterns: [/\b(tsc|typecheck|type-check)\b/, /\b(lint|deplint|oxlint|eslint|biome)\b/],
        gatesEveryFile: false
      };
    }
    const up = path.dirname(dir);
    if (up === dir) break;
    dir = up;
  }
  return null;
}

// Two ways a turn writes files with no Edit tool call to show for it: through the shell
// (sed -i, a heredoc, tee), and by delegating to a subagent, whose edits land in its own
// transcript. Either one means the file list has to come from git instead, and both are
// the routes an agent bypassing a skill is most likely to take.
function wroteViaShell(commands) {
  return commands.some(c =>
    /\bsed\s+-i\b|\btee\b|<<\s*'?[A-Za-z_]/.test(c) ||
    />>?\s*(?!\/dev\/|&)[^\s;&|]+/.test(c));
}

// Only consulted once the turn is known to have written something, so a working tree
// that was already dirty before the session cannot trigger the gate on its own.
function gitDirty(cwd) {
  try {
    const out = execFileSync('git', ['-C', cwd, 'status', '--porcelain', '--untracked-files=all'],
      { encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore'] });
    return out.split('\n').filter(Boolean).map(l => l.slice(3).trim()).filter(Boolean);
  } catch (e) {
    return [];
  }
}

const pass = () => process.stdout.write('{}');

let input = '';
process.stdin.on('data', c => { input += c; });
process.stdin.on('end', () => {
  if (process.env.CRAFTKIT_GATE === 'off') return pass();

  let payload;
  try { payload = JSON.parse(input); } catch (e) { return pass(); }
  if (payload.stop_hook_active) return pass();
  if (!payload.transcript_path) return pass();

  const cwd = payload.cwd || process.cwd();
  // No early return on a missing gate: the rubric's self-pass requirement is not
  // conditioned on the repo shipping check.sh or package.json, so returning here left a
  // bare shell, Rust or Go repo with no self-pass enforcement at all.
  const gate = requiredGate(cwd);

  const turn = currentTurn(payload.transcript_path);
  if (!turn.readable) return pass();

  // Deduped because turn.edits holds one entry per Edit call, so four edits to one file
  // reported "4 file(s)" and listed it four times. Caught by this gate firing on itself.
  let touched = turn.edits;
  if (wroteViaShell(turn.commands) || turn.delegated) touched = touched.concat(gitDirty(cwd));
  touched = touched.filter((f, i) => touched.indexOf(f) === i);
  const edited = !gate ? [] : gate.gatesEveryFile ? touched : touched.filter(f => CODE_EXT.test(f));
  const rubric = touched.filter(f => RUBRIC_EXT.test(f));
  if (!edited.length && !rubric.length) return pass();

  // Both refusals are collected before returning. Returning on the first means a turn
  // missing both gets told about one, fixes it, and is refused again for the other.
  const reasons = [];

  if (edited.length && !gate.patterns.every(p => turn.commands.some(c => p.test(c)))) {
    reasons.push(
      'Verification gate not run. This turn edited ' + edited.length + ' file(s): ' +
      edited.slice(0, 6).map(f => path.basename(f)).join(', ') +
      (edited.length > 6 ? ', ...' : '') + '\n' +
      'Run: ' + gate.run + '\n' +
      'Then report the actual output. If a gate genuinely cannot run here, say which and why, ' +
      'and that the change is unverified. Do not report done instead.');
  }

  if (rubric.length && !SELF_PASS.test(String(turn.assistantText || '').replace(/```[\s\S]*?```/g, ''))) {
    reasons.push(
      'No ponytail self-pass this turn, and it edited ' + rubric.length + ' source file(s): ' +
      rubric.slice(0, 6).map(f => path.basename(f)).join(', ') +
      (rubric.length > 6 ? ', ...' : '') + '\n' +
      'Scan your own diff against the six rubric tags (delete: stdlib: native: yagni: shrink: narrate:), ' +
      'cut each hit or mark it ponytail: with its ceiling, then emit one line:\n' +
      '  ponytail self-pass: clean\n' +
      '  ponytail self-pass: cut <what>, marked <what>\n' +
      'A fenced example or mid-sentence mention is documentation, not a claim about this turn.\n' +
      'Set CRAFTKIT_GATE=off to disable this gate.');
  }

  if (!reasons.length) return pass();
  process.stdout.write(JSON.stringify({ decision: 'block', reason: reasons.join('\n\n') }));
});
