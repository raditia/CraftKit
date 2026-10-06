#!/usr/bin/env node
// CraftKit Stop gate: a turn that edited source cannot end without running this
// project's verification command. Closes the gap where the agent reports done, having
// skipped the gates the skill told it to run, because nothing checked the claim.
// Blocks at most twice per turn, counted, so a turn gets one real second chance and the
// loop still terminates. Honoring stop_hook_active unconditionally meant only the first
// stop attempt was judged, so a blocked turn could change nothing and stop again.
// Escape hatch: CRAFTKIT_GATE=off.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { currentTurn, turnBudget } = require(path.join(__dirname, 'craftkit-transcript.js'));

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

// Only consulted once the turn is known to have written something, and only files modified
// since the turn began count. Without the cut, any shell redirect or agent spawn made
// every file already dirty before the session look like this turn's edit, so one stale
// untracked doc gated every delegating turn. ctime joins mtime because a chmod moves only
// ctime. A missing file (deleted) or an unknown start time counts, failing toward the gate
// firing.
function gitDirty(cwd, since) {
  const git = args => execFileSync('git', ['-C', cwd].concat(args),
    { encoding: 'utf8', timeout: 5000, stdio: ['ignore', 'pipe', 'ignore'] });
  try {
    const root = git(['rev-parse', '--show-toplevel']).trim();
    // -z leaves names unquoted and prints a rename or copy as "XY dest\0source".
    const entries = git(['status', '--porcelain', '-z', '--untracked-files=all']).split('\0');
    const files = [];
    for (let i = 0; i < entries.length; i++) {
      if (!entries[i]) continue;
      const rel = entries[i].slice(3);
      // An isolation: worktree spawn leaves its checkout untracked here; the agent's edits
      // are its own to verify. Matched repo-relative, so a session running inside a
      // worktree still gates its own files.
      if (!rel.startsWith('.claude/worktrees/')) files.push(path.join(root, rel));
      if (/[RC]/.test(entries[i].slice(0, 2))) i++;
    }
    return files.filter(f => {
      if (!Number.isFinite(since)) return true;
      try { const s = fs.statSync(f); return Math.max(s.mtimeMs, s.ctimeMs) >= since; } catch (e) { return true; }
    });
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
  if (!payload.transcript_path) return pass();

  const cwd = payload.cwd || process.cwd();
  const gate = requiredGate(cwd);
  if (!gate) return pass();

  const turn = currentTurn(payload.transcript_path);
  if (!turn.readable) return pass();

  // Deduped because turn.edits holds one entry per Edit call, so four edits to one file
  // reported "4 file(s)" and listed it four times. Caught by this gate firing on itself.
  // Scratchpad and temp files are throwaway by design, so they cannot be the reason a turn
  // owes a verification run. gate-skill-first has always excluded them; this gate did not,
  // and in a repo where check.sh makes every path count, drafting a PR body in the
  // scratchpad demanded a full gate run. A gate that fires on throwaway files is the
  // click-through trainer these gates are written to avoid.
  const THROWAWAY = /\/scratchpad\/|^\/tmp\/|^\/private\/tmp\/|^\/var\/folders\//;
  let touched = turn.edits.filter(f => !THROWAWAY.test(f));
  // A notification turn reports on an agent whose edits predate the turn, so its cut is
  // the agent's spawn. No spawn found leaves it NaN, which counts every dirty file: the turn
  // start would exclude all of the agent's edits.
  const since = turn.notification ? turn.spawnedAt : turn.startedAt;
  if (wroteViaShell(turn.commands) || turn.delegated || turn.notification) {
    touched = touched.concat(gitDirty(cwd, since));
  }
  touched = touched.filter((f, i) => touched.indexOf(f) === i);
  const edited = gate.gatesEveryFile ? touched : touched.filter(f => CODE_EXT.test(f));
  if (!edited.length) return pass();

  if (gate.patterns.every(p => turn.commands.some(c => p.test(c)))) return pass();


  // Budget checked only once the turn is known to be failing, so a compliant turn spends
  // nothing and a later failure in the same turn still has its chance.
  const session = String(payload.session_id || 'nosession');
  if (turn.turnId && !turnBudget(session, turn.turnId, 'verify', 2)) return pass();

  process.stdout.write(JSON.stringify({
    decision: 'block',
    reason:
      'Verification gate not run. This turn edited ' + edited.length + ' file(s): ' +
      edited.slice(0, 6).map(f => path.basename(f)).join(', ') +
      (edited.length > 6 ? ', ...' : '') + '\n' +
      'Run: ' + gate.run + '\n' +
      'Then report the actual output. If a gate genuinely cannot run here, say which and why, ' +
      'and that the change is unverified. Do not report done instead.\n' +
      'Set CRAFTKIT_GATE=off to disable this gate.'
  }));
});
