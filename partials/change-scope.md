---
name: change-scope
description: Complete local change collection for build, review, ship, and context workflows.
---

## Change scope

Collect the working tree as well as committed changes, even when the branch has no new commits:

```bash
rtk git status --short --branch
rtk git diff --cached --name-status
rtk git diff --cached
rtk git diff --name-status
rtk git diff
rtk git ls-files --others --exclude-standard
rtk git symbolic-ref --quiet --short refs/remotes/origin/HEAD
```

Use the cached remote HEAD as the base. If absent, use an existing local `main` or `master` ref
(check with `git show-ref --verify`). If none resolves, report `cannot-verify` for the committed
comparison and still review working-tree changes. Do not guess a missing base or fetch solely
to discover it. When a base resolves, collect `rtk git diff <base>...HEAD --name-status` and
`rtk git diff <base>...HEAD` too.

Union and deduplicate those file sets before choosing agents or tests. Read relevant untracked
source and test files; the diff does not contain their contents. Exclude credentials, generated
output, and unrelated files, naming any relevant omission. Derive context once into the turn;
write no context cache and perform no freshness check.
