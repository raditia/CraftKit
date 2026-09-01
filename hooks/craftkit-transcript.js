#!/usr/bin/env node
// Shared transcript scanner for the CraftKit enforcement gates. Both gates decide
// against "what happened in the CURRENT turn", so the definition of a turn lives here
// once: a disagreement between the two would make one of them fire on the wrong turn,
// which is indistinguishable from a broken gate.
// Installed alongside the gates by adapters/claude.sh; required by relative path.

const crypto = require('crypto');
const fs = require('fs');

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
    return lines;
  } catch (e) {
    return [];
  } finally {
    if (fd !== undefined) { try { fs.closeSync(fd); } catch (e) { /* nothing to do */ } }
  }
}

// A real user turn, as opposed to a tool_result, which the transcript also records
// with role user and which would otherwise reset the turn after every tool call.
function isUserTurn(entry) {
  if (!entry || entry.type !== 'user') return false;
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
// (the names the user typed, so a gate can match an announcement against them), and
// assistantText (everything the agent said this turn, which is where an announcement of a
// skill lives when no Skill call followed it).
function currentTurn(transcriptPath) {
  const out = { edits: [], commands: [], skills: [], slashCommand: false, readable: false,
                turnId: '', sidechain: false, delegated: false, slashCommands: [],
                assistantText: '' };
  const lines = readTailLines(transcriptPath);
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

  if (entries[start] && isUserTurn(entries[start])) {
    const text = userText(entries[start]);
    out.slashCommand = /<command-name>/.test(text);
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
  return out;
}

module.exports = { currentTurn };
