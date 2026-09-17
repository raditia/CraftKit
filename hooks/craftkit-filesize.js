#!/usr/bin/env node
// CraftKit shared file-size answer, read by the Bash read cap and the Read gate.
// Shared for the same reason craftkit-platform.js is: two copies of "how big is big"
// would let one path truncate a file the other waved through, and the disagreement would
// only show up as an inconsistent read budget nobody could explain.

const fs = require('fs');

// The line past which a whole-file read is expensive enough to intervene on. Also the
// value passed to `rtk read -m`, because rtk 0.49.0 shows a file whole at or under N and
// exactly N/2 over it, so one number is both the threshold and the flag.
// Chosen high on purpose: the Read gate prompts, and a gate that fires on ordinary files
// trains the click-through that makes it useless.
const BIG_LINES = 800;

// Reading a file just to count newlines is bounded here. Past this size it is over any
// plausible threshold, and loading it to prove that costs more than the answer.
const STAT_SHORTCUT = 4 * 1024 * 1024;

// Returns true only when the file is known to exceed `limit` lines. Anything unreadable,
// missing, or not a regular file answers false: both callers must fail open, because a
// size probe that guesses is worse than one that abstains.
function overLines(abs, limit) {
  const max = typeof limit === 'number' ? limit : BIG_LINES;
  let st;
  try { st = fs.statSync(abs); } catch (e) { return false; }
  if (!st.isFile()) return false;
  if (st.size > STAT_SHORTCUT) return true;
  let lines = 0;
  try {
    const buf = fs.readFileSync(abs);
    for (let i = 0; i < buf.length; i++) if (buf[i] === 10 && ++lines > max) return true;
  } catch (e) { return false; }
  return false;
}

// Exact count, for a gate that names the number in the message it shows a human.
function lineCount(abs) {
  try {
    const buf = fs.readFileSync(abs);
    let n = 0;
    for (let i = 0; i < buf.length; i++) if (buf[i] === 10) n++;
    return n;
  } catch (e) { return 0; }
}

module.exports = { BIG_LINES, overLines, lineCount };
