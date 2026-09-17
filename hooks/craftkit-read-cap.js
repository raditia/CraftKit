#!/usr/bin/env node
// CraftKit PreToolUse rewrite: an uncapped whole-file read gets a line cap.
// `rtk hook claude` already rewrites `cat F` to `rtk read F`, but passes no flags at any
// size, so a 2000-line file still lands whole and is re-sent every turn after. This adds
// the cap rtk already supports. It rewrites, it never refuses: nothing here can block a
// call, and a skipped rewrite leaves today's behavior.
// `-m` and not `-l`: the `-l` filters strip comments and nothing else, measured 10577 to
// 5506 bytes on craftkit-routing.js and a no-op on markdown, so they delete the `why`
// comments plus every ponytail:/flag: marker that karpathy-guidelines makes contract.
// Truncation loses the tail, which rtk names in its own output ("[340 more lines]"), and a
// named tail is recoverable where a stripped marker is not.
// Escape hatch: CRAFTKIT_READ_CAP=off.

const path = require('path');
const { BIG_LINES, overLines } = require(path.join(__dirname, 'craftkit-filesize.js'));

// `rtk read -m N` is not a plain cap. Measured on rtk 0.49.0: a file of n lines passes whole
// when n <= N, and shows exactly N/2 lines when n > N, so BIG_LINES serves as both the
// threshold and the flag value and the model sees half of it for anything past.
// ponytail: depends on that halving, which rtk does not document. ceiling: a file just past
// the line drops to half in one hop, and an rtk release could change the ratio. upgrade:
// check.sh check 35 pins the semantics, so a change fails the gate instead of silently
// halving again; gate-read-size.js delegates instead of truncating, on the Read path.

const pass = () => process.stdout.write('{}');

// A metachar means the output is being post-processed, and `cat f | wc -l` capped at 400
// reports 400. Only a bare whole-file read is safe to rewrite.
const SHELL_META = /[|&;<>`$(){}*?[\]]|\n/;

// `cat F` or an already-rewritten `rtk read F`, single file, no flags. Both shapes, because
// this hook and rtk's share one event and the merge order of two updatedInput results is
// not ours to pick: matching only one shape would mean firing only on one order.
function targetFile(cmd) {
  const m = /^\s*(?:cat|rtk\s+read)\s+(?:(['"])([^'"]+)\1|([^\s'"]+))\s*$/.exec(cmd);
  return m ? (m[2] || m[3]) : null;
}

let input = '';
process.stdin.on('data', c => { input += c; });
process.stdin.on('end', () => {
  if (process.env.CRAFTKIT_READ_CAP === 'off') return pass();

  let payload;
  try { payload = JSON.parse(input); } catch (e) { return pass(); }

  const cmd = String((payload.tool_input || {}).command || '');
  if (!cmd || SHELL_META.test(cmd)) return pass();

  const file = targetFile(cmd);
  if (!file) return pass();
  if (!overLines(path.resolve(String(payload.cwd || process.cwd()), file))) return pass();

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecisionReason: 'CraftKit read cap: over ' + BIG_LINES + ' lines',
      updatedInput: { command: 'rtk read -m ' + BIG_LINES + ' ' + file }
    }
  }));
});
