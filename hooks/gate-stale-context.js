#!/usr/bin/env node
// CraftKit PreToolUse gate: editing a file the context doc describes, after that file
// changed underneath the doc, asks first. Closes the session-belief gap: a doc read at
// turn 3 and acted on at turn 40 describes a file that may have moved since.
//
// Keyed on mtime against the doc, NOT on git. A context doc is generated from a dirty
// worktree, so its summary already covers the uncommitted work; diffing against the commit
// it records would re-report every one of those files as drifted and fire on almost every
// edit of a feature branch. "Changed after the doc was written" is the actual question, and
// mtime answers it in one stat. craftkit-drift.js answers the other question (has the
// branch moved since the baseline) for the context skills' freshness step.
//
// ponytail: mtime, so a git checkout or branch switch restamps files and reads as drift.
// ceiling: a branch switch makes every described file look changed. upgrade: none needed,
// because a branch switch already invalidates the doc through the branch-mismatch check in
// standard context loading, which regenerates before any of this is consulted.
//
// Decision is "ask", never "deny", and once per turn, for the reason gate-skill-first
// documents: a per-edit prompt on a ten-edit turn trains you to click through.
// Escape hatch: CRAFTKIT_GATE=off.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { currentTurn } = require(path.join(__dirname, 'craftkit-transcript.js'));

const STAMP_DIR = path.join(os.tmpdir(), 'craftkit-gate');

function askedAlready(session, turnId) {
  try {
    return fs.readFileSync(path.join(STAMP_DIR, session + '.stale'), 'utf8').trim() === turnId;
  } catch (e) {
    return false;
  }
}

function recordAsk(session, turnId) {
  try {
    fs.mkdirSync(STAMP_DIR, { recursive: true });
    fs.writeFileSync(path.join(STAMP_DIR, session + '.stale'), turnId);
  } catch (e) { /* an unwritable tmpdir costs a repeat prompt, not a broken gate */ }
}

function findContextDoc(startDir) {
  let dir = startDir;
  for (let i = 0; i < 40; i++) {
    const p = path.join(dir, 'docs', 'context.md');
    if (fs.existsSync(p)) return p;
    const up = path.dirname(dir);
    if (up === dir) break;
    dir = up;
  }
  return null;
}

// Only a file the doc actually mentions: the doc is the thing going stale, so a file it
// never described cannot be described staly. Basename, because docs reference short paths.
function docMentions(docText, file) {
  const base = path.basename(file);
  return base.length > 2 && docText.indexOf(base) !== -1;
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
  if (!file) return pass();
  if (/\/scratchpad\/|^\/tmp\/|^\/private\/tmp\//.test(file)) return pass();

  const cwd = payload.cwd || process.cwd();
  const doc = findContextDoc(cwd);
  if (!doc) return pass();

  let docStat, fileStat, docText;
  try {
    docStat = fs.statSync(doc);
    fileStat = fs.statSync(file);
    docText = fs.readFileSync(doc, 'utf8');
  } catch (e) {
    // A file being created has no stat yet, and a doc that cannot be read cannot be stale.
    return pass();
  }

  if (!docMentions(docText, file)) return pass();
  // A one-second grace window: the doc and the file are often written in the same pass,
  // and filesystem timestamp granularity should not manufacture drift.
  if (fileStat.mtimeMs <= docStat.mtimeMs + 1000) return pass();

  if (!payload.transcript_path) return pass();
  const turn = currentTurn(payload.transcript_path);
  if (!turn.readable) return pass();
  // The parent turn owns context freshness; a subagent got its content handed to it.
  if (turn.sidechain) return pass();
  // A file this turn already edited is one the agent knows the current state of.
  if (turn.edits.indexOf(file) !== -1) return pass();

  const session = String(payload.session_id || 'nosession');
  if (turn.turnId) {
    if (askedAlready(session, turn.turnId)) return pass();
    recordAsk(session, turn.turnId);
  }

  const ago = Math.round((fileStat.mtimeMs - docStat.mtimeMs) / 1000);
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'ask',
      permissionDecisionReason:
        path.basename(file) + ' changed ' + ago + 's after ' + path.relative(cwd, doc) +
        ' was written, and that doc describes it.\n' +
        'Anything you concluded from the doc about this file may be stale. Re-read the file, ' +
        'or regenerate the context doc, before editing on top of it.\n' +
        'Approve to edit anyway. Set CRAFTKIT_GATE=off to disable this gate.'
    }
  }));
});
