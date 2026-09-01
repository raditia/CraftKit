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
  const gate = requiredGate(cwd);
  if (!gate) return pass();

  const turn = currentTurn(payload.transcript_path);
  if (!turn.readable) return pass();

  let touched = turn.edits;
  if (wroteViaShell(turn.commands) || turn.delegated) touched = touched.concat(gitDirty(cwd));
  const edited = gate.gatesEveryFile ? touched : touched.filter(f => CODE_EXT.test(f));
  if (!edited.length) return pass();

  if (gate.patterns.every(p => turn.commands.some(c => p.test(c)))) return pass();

  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason:
      'Verification gate not run. This turn edited ' + edited.length + ' file(s): ' +
      edited.slice(0, 6).map(f => path.basename(f)).join(', ') +
      (edited.length > 6 ? ', ...' : '') + '\n' +
      'Run: ' + gate.run + '\n' +
      'Then report the actual output. If a gate genuinely cannot run here, say which and why, ' +
      'and that the change is unverified. Do not report done instead.'
  }));
});
