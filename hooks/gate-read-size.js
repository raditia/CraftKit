#!/usr/bin/env node
// CraftKit PreToolUse gate: a whole-file Read past BIG_LINES asks before the file lands.
// craftkit-read-cap.js covers the Bash path, but `rtk hook claude` only intercepts Bash, so
// the Read tool, the bigger channel, had nothing on it. A file read whole is re-sent with
// every turn after, which is what makes one careless read cost for the rest of the session.
// It offers a delegation rather than a truncation: the bulk-read agent reads the file and
// returns bullets carrying file:line, so the file enters its context and not this one.
//
// Decision is "deny", and this is the one gate that does not ask. Two measured reasons.
// First, "ask" resolves to allow under auto-accept without surfacing anything: it fired on an
// 810-line read, wrote its turn stamp, and the file landed whole regardless, so the gate read
// as coverage while doing nothing. Second, a deny reason is delivered to the model, which is
// the only channel that can carry the cheaper path.
// Truncating instead, the way craftkit-read-cap.js does on the Bash path, is what this would
// otherwise be: injecting `limit` through updatedInput. It is unsafe here, because rtk prints
// "[N more lines]" inside its own output while the Read tool prints nothing, so the model
// would hold 800 lines of a 2000-line file with no sign the file continued. A silent partial
// read produces confident claims about code that was never in context, which costs more than
// a complete read does.
// The escape paths are what make the refusal affordable: offset/limit is never gated, Grep is
// never gated, a subagent read always passes, and CRAFTKIT_READ_GATE=off turns it off.
// The other gates also state the fact that this one asserts is different in kind: they judge
// whether a skill applies, which a human should be able to overrule, while this one asserts a
// file's line count and proposes a route.
// Escape hatch: CRAFTKIT_READ_GATE=off.

const path = require('path');
const { currentTurn } = require(path.join(__dirname, 'craftkit-transcript.js'));
const { BIG_LINES, overLines, lineCount } = require(path.join(__dirname, 'craftkit-filesize.js'));

// Line count is meaningless on these, and bullets are the wrong shape for an image or a
// rendered page, so they are never the gate's business.
const NON_TEXT = /\.(png|jpe?g|gif|webp|bmp|ico|pdf|zip|gz|tgz|mp4|mov|woff2?|ttf|otf)$/i;

const pass = () => process.stdout.write('{}');

let input = '';
process.stdin.on('data', c => { input += c; });
process.stdin.on('end', () => {
  if (process.env.CRAFTKIT_READ_GATE === 'off') return pass();

  let payload;
  try { payload = JSON.parse(input); } catch (e) { return pass(); }

  const ti = payload.tool_input || {};
  const file = String(ti.file_path || '');
  if (!file || NON_TEXT.test(file)) return pass();
  // A bounded read is the behavior this gate is asking for, so it never interrupts one.
  if (ti.limit != null || ti.offset != null || ti.pages != null) return pass();

  if (!payload.transcript_path) return pass();
  const turn = currentTurn(payload.transcript_path);
  if (!turn.readable) return pass();
  // The bulk-read agent reads the file this gate just refused. Gating inside the subagent
  // would refuse the delegation it exists to offer, and a background agent has nobody to
  // answer the prompt anyway.
  if (turn.sidechain) return pass();
  if (turn.notification) return pass();

  if (!overLines(file, BIG_LINES)) return pass();

  // No once-per-turn budget, unlike the other gates. Theirs exists so a ten-edit turn does not
  // cost ten prompts and train the click-through. This one shows no prompt, so the budget would
  // buy nothing and cost the enforcement: the 2nd through Nth large read of a turn would land.

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason:
        'Refused: ' + file + ' is ' + lineCount(file) + ' lines, and a file read whole is re-sent on\n' +
        'every turn for the rest of the session. Three ways through, none of them gated:\n' +
        '1. Delegate. Spawn the bulk-read agent with this path and your actual question. It reads\n' +
        '   the file in its own context and returns bullets carrying file:line.\n' +
        '2. Read a slice. Read(file_path, offset, limit) is never refused, at any size. Grep first\n' +
        '   if you do not know where to look, then read that range.\n' +
        '3. If you need the exact text to edit, read the slice containing it. bulk-read bullets\n' +
        '   cannot back an edit, which is why they name a line range instead.\n' +
        'Reading the whole file in consecutive slices costs what the whole read cost, so it is not\n' +
        'one of the three. Set CRAFTKIT_READ_GATE=off if this refusal is wrong.'
    }
  }));
});
