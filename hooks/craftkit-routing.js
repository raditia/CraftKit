#!/usr/bin/env node
// CraftKit — UserPromptSubmit hook: enforce skill-first routing gate every turn.
// Installed by sync.sh via adapters/claude.sh. Fires unconditionally on every prompt.

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext:
        "REPO: CraftKit — rules/ (always-active) → skills/ (on-demand) → commands/ (orchestrators) → agents/ (cold sub-agents).\n\n" +
        "SKILL-FIRST GATE — HARD REQUIREMENT, no exceptions, no silent bypasses:\n" +
        "1. Classify prompt against available skills BEFORE generating any response.\n" +
        "2. Match an orchestrator:\n" +
        "   build/create/implement feature → /parallel-build\n" +
        "   review/feedback/check changes  → /parallel-review\n" +
        "   ship/merge/ready to merge      → /parallel-ship\n" +
        "   broken/bug/crash/fix           → /fix\n" +
        "   tests/coverage/write tests     → /fe-test\n" +
        "   PR message/description         → /pr-message\n" +
        "   scaffold only                  → /build\n" +
        "   Or a skill: /fe-context /fe-scaffold /fe-review /fe-patterns /fe-a11y /fe-performance /code-quality /debug /ponytail-review /ponytail-audit /ponytail-debt\n" +
        "   iOS (Traveloka bus/train, native Swift/ObjC only): /ios-patterns /ios-scaffold /ios-review /ios-test\n" +
        "3A match:    output 'Running /skill-name [tier] — reason.' then invoke. Do NOT respond before invoking.\n" +
        "3B no match: output 'No skill matched for this request. Responding directly.' then respond.\n" +
        "Skipping steps 1-3 = rule violation. Silent bypass = rule violation."
    }
  }));
});
