#!/usr/bin/env node
// Shared transcript scanner for the CraftKit enforcement gates. Both gates decide
// against "what happened in the CURRENT turn", so the definition of a turn lives here
// once: a disagreement between the two would make one of them fire on the wrong turn,
// which is indistinguishable from a broken gate.
// Installed alongside the gates by adapters/claude.sh; required by relative path.

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

// Only the tail is read: a turn is at the end by definition, and a long session
// transcript reaches tens of MB, which is not worth re-reading on every Edit.
const TAIL_BYTES = 1024 * 1024;

function readTailLines(transcriptPath) {
  let fd;
  try {
    fd = fs.openSync(transcriptPath, 'r');
    const size = fs.fstatSync(fd).size;
    const start = Math.max(0, size - TAIL_BYTES);
    const buf = Buffer.alloc(size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const lines = buf.toString('utf8').split('\n');
    // A mid-line start yields a partial first line that will not parse anyway.
    if (start > 0) lines.shift();
    // truncated says the session's earlier turns are outside this window, which is what
    // stops priorSkills from being read as "the session never routed".
    return { lines: lines, truncated: start > 0 };
  } catch (e) {
    return { lines: [], truncated: false };
  } finally {
    if (fd !== undefined) { try { fs.closeSync(fd); } catch (e) { /* nothing to do */ } }
  }
}

// Counts Skill calls across the WHOLE file, for when the tail window missed the session
// start. Needed because the transcript only grows: once a session passes TAIL_BYTES,
// every later turn sees a truncated window, so treating "unknown" as "never routed" would
// have flipped a session-scoped gate off permanently partway through. A plain pattern
// count, no JSON parse, because the only question is how many Skill calls exist.
//
// Incremental: every Read, Edit and Stop in a long session lands here, and a full rescan
// grows with the transcript (116ms at 37MB). The transcript is append-only JSONL, so the
// count up to the last complete line is final; a stamp keeps that byte offset and count,
// and each call scans only what was appended since. Only whole lines are counted, so a
// match can never straddle the saved offset. A file shorter than the offset was replaced,
// not appended to, and is rescanned from zero. An unwritable stamp costs speed, not
// correctness: the count is still returned, the next call just starts over.
const SKILL_CALL = /"name"\s*:\s*"Skill"/g;

function countSkillCalls(transcriptPath) {
  const stamp = path.join(os.tmpdir(), 'craftkit-gate', 'skills-' +
    crypto.createHash('sha1').update(transcriptPath).digest('hex').slice(0, 16));
  let lineStart = 0, total = 0;
  try {
    const parts = fs.readFileSync(stamp, 'utf8').trim().split(/\s+/);
    lineStart = Number(parts[0]) || 0;
    total = Number(parts[1]) || 0;
  } catch (e) { /* no stamp yet, so scan from the start */ }
  let fd;
  try {
    fd = fs.openSync(transcriptPath, 'r');
    if (fs.fstatSync(fd).size < lineStart) { lineStart = 0; total = 0; }
    const buf = Buffer.alloc(1024 * 1024);
    let pending = Buffer.alloc(0);
    let pos = lineStart;
    let read;
    while ((read = fs.readSync(fd, buf, 0, buf.length, pos)) > 0) {
      pos += read;
      const chunk = pending.length ? Buffer.concat([pending, buf.subarray(0, read)]) : buf.subarray(0, read);
      const cut = chunk.lastIndexOf(0x0a) + 1;
      total += (chunk.toString('utf8', 0, cut).match(SKILL_CALL) || []).length;
      lineStart += cut;
      pending = Buffer.from(chunk.subarray(cut));
    }
  } catch (e) {
    return 0;
  } finally {
    if (fd !== undefined) { try { fs.closeSync(fd); } catch (e) { /* nothing to do */ } }
  }
  try {
    fs.mkdirSync(path.dirname(stamp), { recursive: true });
    fs.writeFileSync(stamp, lineStart + ' ' + total);
  } catch (e) { /* uncached: the next call rescans, the count above still stands */ }
  return total;
}

// A real user turn, as opposed to a tool_result, which the transcript also records
// with role user and which would otherwise reset the turn after every tool call.
// Injected entries are the other role-user impostor, and they carry text rather than a
// tool_result, so they need their own exclusion: a Skill body (isMeta + turnCompanion +
// sourceToolUseID) and stop-hook feedback (isMeta + session_id) both land mid-turn. Read
// as turn starts they truncate the turn, which made both gates fire on turns that HAD
// routed and let post-skill edits through unseen. Keyed negatively on isMeta rather than
// positively on promptSource, which a real prompt carries, because the local command echo
// (<command-name>) lacks promptSource and must still arm slashCommand below.
// ponytail: isMeta is an undocumented transcript field. ceiling: a format change reverts
// both gates to reading a truncated turn. upgrade: the check.sh fixtures pin the shape, so
// the gate fails loudly instead of degrading quietly.
function isUserTurn(entry) {
  if (!entry || entry.type !== 'user') return false;
  if (entry.isMeta === true) return false;
  const content = entry.message && entry.message.content;
  if (typeof content === 'string') return true;
  if (!Array.isArray(content)) return false;
  return !content.some(c => c && c.type === 'tool_result');
}

function userText(entry) {
  const content = entry.message && entry.message.content;
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.filter(c => c && c.type === 'text').map(c => c.text || '').join('\n');
}

// Identity of the turn, so a gate can remember it already acted this turn. The
// transcript's own uuid is preferred: hashing the text alone would collide on a repeated
// prompt ("continue" twice) and read as the same turn.
function turnIdOf(entry, text) {
  if (entry && typeof entry.uuid === 'string' && entry.uuid) return entry.uuid;
  return crypto.createHash('sha1').update(text || '').digest('hex').slice(0, 16);
}

// What the agent did since the user last spoke. Returns edits (file paths), commands
// (bash command strings), skills (Skill tool invocations), slashCommand (the user
// typed /<skill> themselves, which arms the gate just as a Skill call does), turnId
// (stable identity of this turn), sidechain (this transcript belongs to a subagent, which
// gets its own file under <session>/subagents/), delegated (the turn spawned an agent,
// so files may have been written where this transcript cannot see them), slashCommands
// (the names the user typed, so a gate can match an announcement against them),
// assistantText (everything the agent said this turn, which is where an announcement of a
// skill lives when no Skill call followed it), notification (the turn was opened by a
// background-task event rather than a prompt), and priorSkills (Skill calls in EARLIER
// turns of this session, so a gate can spare a continuation of already-routed work,
// counted across the whole file when the tail window missed the session start).
function currentTurn(transcriptPath) {
  const out = { edits: [], commands: [], skills: [], slashCommand: false, readable: false,
                turnId: '', sidechain: false, delegated: false, slashCommands: [],
                assistantText: '', notification: false, priorSkills: 0 };
  const tail = readTailLines(transcriptPath);
  const lines = tail.lines;
  if (!lines.length) return out;
  out.readable = true;

  const entries = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    try { entries.push(JSON.parse(line)); } catch (e) { /* truncated or non-JSON line */ }
  }

  let start = 0;
  for (let i = entries.length - 1; i >= 0; i--) {
    if (isUserTurn(entries[i])) { start = i; break; }
  }
  // No user turn inside the tail means the turn is longer than TAIL_BYTES. Scanning
  // the whole tail then over-counts history rather than under-counting this turn,
  // which fails toward letting the agent through instead of blocking it wrongly.

  // Whether the SESSION routed before this turn, not just whether this turn did. See the
  // rationale at the consuming site, gate-skill-first.js.
  for (let i = 0; i < start; i++) {
    const content = entries[i].message && entries[i].message.content;
    if (!Array.isArray(content)) continue;
    for (const item of content) {
      if (item && item.type === 'tool_use' && item.name === 'Skill') out.priorSkills++;
    }
  }

  if (entries[start] && isUserTurn(entries[start])) {
    const text = userText(entries[start]);
    out.slashCommand = /<command-name>/.test(text);
    // A background-task event is not a prompt, so it carries no routing intent to judge.
    // Only task-notification: a system-reminder can prefix a genuine prompt in the same
    // entry, and matching it would silently disarm the gate on ordinary routable work.
    out.notification = /^\s*<task-notification\b/.test(text);
    let sc;
    const scRe = /<command-name>\s*\/?([A-Za-z0-9:_-]+)/g;
    while ((sc = scRe.exec(text)) !== null) out.slashCommands.push(sc[1]);
    out.turnId = turnIdOf(entries[start], text);
    out.sidechain = entries[start].isSidechain === true;
  }

  const said = [];
  for (let i = start; i < entries.length; i++) {
    const content = entries[i].message && entries[i].message.content;
    if (!Array.isArray(content)) continue;
    const isAssistant = entries[i].type === 'assistant';
    for (const item of content) {
      if (isAssistant && item && item.type === 'text' && item.text) said.push(String(item.text));
      if (!item || item.type !== 'tool_use') continue;
      const input = item.input || {};
      if (item.name === 'Skill') out.skills.push(input.skill || 'unknown');
      else if (item.name === 'Agent' || item.name === 'Task') out.delegated = true;
      else if (item.name === 'Bash') out.commands.push(String(input.command || ''));
      else if (/^(Edit|Write|MultiEdit|NotebookEdit)$/.test(item.name)) {
        const f = input.file_path || input.notebook_path;
        if (f) out.edits.push(String(f));
      }
    }
  }
  out.assistantText = said.join('\n');
  // Only now, and only when the window was short: the whole-file count includes this
  // turn's own calls, so subtract them to get what happened strictly earlier.
  if (tail.truncated) {
    out.priorSkills = Math.max(0, countSkillCalls(transcriptPath) - out.skills.length);
  }
  return out;
}

// A bounded budget of interruptions per turn, shared by every gate. Returns true while the
// turn still has budget for this key, and counts the action.
//
// Two callers with different needs. The PreToolUse gates want exactly one prompt per turn,
// because they fire per tool call and a ten-edit turn would otherwise cost ten prompts,
// which trains clicking through. The Stop gates want more than one, because honoring
// stop_hook_active unconditionally meant only the FIRST stop attempt was ever judged: a
// turn could be blocked, change nothing, and stop again to get through.
//
// An unwritable stamp returns false, which is deliberate. It makes "cannot record" resolve
// to "do not act", so the failure mode is the pre-existing behavior (a gate that lets the
// retry through) rather than a gate that blocks forever because it cannot count.
function turnBudget(session, turnId, key, max) {
  const dir = path.join(os.tmpdir(), 'craftkit-gate');
  const stamp = path.join(dir, session + '.' + key);
  let used = 0;
  try {
    const parts = fs.readFileSync(stamp, 'utf8').trim().split(/\s+/);
    if (parts[0] === turnId) used = Number(parts[1]) || 0;
  } catch (e) { /* no stamp yet, so nothing spent on this turn */ }
  if (used >= max) return false;
  try {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(stamp, turnId + ' ' + (used + 1));
  } catch (e) {
    return false;
  }
  return true;
}

// Consequence worth knowing for the PreToolUse callers: DENY the first prompt and the rest
// of that turn passes silently, on the assumption the denial itself redirected the agent.
function onceInTurn(session, turnId, key) {
  return turnBudget(session, turnId, key, 1);
}

module.exports = { currentTurn, onceInTurn, turnBudget };
