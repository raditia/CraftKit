#!/usr/bin/env node
// CraftKit — UserPromptSubmit hook: enforce skill-first routing gate every turn.
// Installed by sync.sh via adapters/claude.sh. Fires unconditionally on every prompt.
// Kept terse on purpose — full routing table + descriptions live always-on in
// rules/using-agent-skills.md; this is the per-turn nudge, not a second copy of the table.
// NOTE: every skill in skills/ must appear here as /<name> or sync.sh's routing drift guard aborts.

const fs = require('fs');
const os = require('os');
const path = require('path');

// Model tier detection — reads the logged-in account from ~/.claude.json.
// Domain check first (gmail.com = personal), organizationType as fallback for
// non-Gmail personal accounts, personal as the safe default on any read/parse failure.
// See rules/using-agent-skills.md → "Model routing" for the full tier table.
function detectModelTier() {
  const PERSONAL = { label: 'personal', everyday: 'claude-sonnet-5', escalate: 'claude-opus-4-8' };
  const ENTERPRISE = { label: 'enterprise', everyday: 'claude-opus-4-8', escalate: 'claude-fable-5' };
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude.json'), 'utf8'));
    const oa = cfg.oauthAccount || {};
    const domain = String(oa.emailAddress || '').toLowerCase().split('@')[1] || '';
    if (domain === 'gmail.com' || domain === 'googlemail.com') return PERSONAL;
    const orgType = String(oa.organizationType || '').toLowerCase();
    if (orgType.includes('enterprise')) return ENTERPRISE;
    return PERSONAL;
  } catch (e) {
    return PERSONAL;
  }
}

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  const tier = detectModelTier();
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext:
        "CraftKit skill-first gate. Classify every prompt against skills BEFORE responding; on match output 'Running /skill [tier] — reason.' then invoke, else output exactly 'No skill matched for this request. Responding directly.' Do NOT respond before invoking. Silent bypass = violation. Full routing table + tiebreakers: rules/using-agent-skills.md.\n\n" +
        "Orchestrators: build/implement feature→/parallel-build · review/check changes→/parallel-review · ship/merge→/parallel-ship · broken/bug/crash→/fix · tests/coverage→/fe-test · PR message→/pr-message · scaffold only→/build\n" +
        "Skills (RN/web EVPMR): /fe-context /fe-scaffold /fe-review /fe-patterns /fe-a11y /fe-performance /fe-test /code-quality /debug /ideate /think /ponytail-review /ponytail-audit /ponytail-debt\n" +
        "Planning (opt-in): /define chains interview→spec→plan (checkpoint-gated) — use for 'plan this feature' / 'spec before building'. Or invoke a phase alone: /interview (de-fuzz) · /spec (PRD) · /plan (tasks) · /adr (decision record) · /docs (dual-audience humanized docs). adr+docs also offered as tail of /parallel-ship. Never auto-run from /parallel-build.\n" +
        "Android (*.kt/*.java, MVP): /android-patterns /android-scaffold /android-review /android-test /android-a11y /android-performance /android-context\n" +
        "iOS (*.swift/*.m, MVVM-C): /ios-patterns /ios-scaffold /ios-review /ios-test /ios-a11y /ios-performance /ios-context\n" +
        "Native build/fix/ship/pr-message platform-route via the shared orchestrators (no EVPMR, no docs/context.md for single native screens).\n\n" +
        `Model tier (detected from ~/.claude.json): ${tier.label} — everyday=${tier.everyday}, escalate=${tier.escalate}. Use these for Claude Code rows in the Model routing table in rules/using-agent-skills.md.`
    }
  }));
});
