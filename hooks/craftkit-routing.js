#!/usr/bin/env node
// CraftKit — UserPromptSubmit hook: enforce skill-first routing gate every turn.
// Installed by sync.sh via adapters/claude.sh. Fires unconditionally on every prompt.
// Kept terse on purpose — full routing table + descriptions live always-on in
// rules/using-agent-skills.md; this is the per-turn nudge, not a second copy of the table.
// NOTE: every skill in skills/ must appear here as /<name> or sync.sh's routing drift guard aborts.

let input = '';
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext:
        "CraftKit skill-first gate. Classify every prompt against skills BEFORE responding; on match output 'Running /skill [tier] — reason.' then invoke, else output exactly 'No skill matched for this request. Responding directly.' Do NOT respond before invoking. Silent bypass = violation. Full routing table + tiebreakers: rules/using-agent-skills.md.\n\n" +
        "Orchestrators: build/implement feature→/parallel-build · review/check changes→/parallel-review · ship/merge→/parallel-ship · broken/bug/crash→/fix · tests/coverage→/fe-test · PR message→/pr-message · scaffold only→/build\n" +
        "Skills (RN/web EVPMR): /fe-context /fe-scaffold /fe-review /fe-patterns /fe-a11y /fe-performance /fe-test /code-quality /debug /ideate /think /ponytail-review /ponytail-audit /ponytail-debt\n" +
        "Android (*.kt/*.java, MVP): /android-patterns /android-scaffold /android-review /android-test /android-a11y /android-performance /android-context\n" +
        "iOS (*.swift/*.m, MVVM-C): /ios-patterns /ios-scaffold /ios-review /ios-test /ios-a11y /ios-performance /ios-context\n" +
        "Native build/fix/ship/pr-message platform-route via the shared orchestrators (no EVPMR, no docs/context.md for single native screens)."
    }
  }));
});
