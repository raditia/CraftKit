# Glossary

Canonical meanings for terms this repo uses precisely. Language only, no implementation detail.

- **Derived context**: facts about a branch that git already holds (changed files, diff summary, branch, base, commit, patterns visible in the code). Recomputable at read time, so storing it is what creates staleness.
- **Intent**: what a human decided and why (objective, scope, constraints, key decisions, task plan, acceptance criteria). Git cannot derive it. It goes stale only when the human changes their mind.
- **Feature**: one unit of intent, tracked by one planning file. Not a branch and not a PR, though under a one-checkout workflow it usually maps to one branch.
- **Active** (of a feature): its intent is still being worked toward. Human-owned state, since no git fact distinguishes an abandoned feature from a paused one.
- **Stale** (of a context doc): the doc asserts a derived fact that no longer holds. Distinct from `drifted`, which names files that moved since a baseline, and from `cannot-verify`, where the baseline is unreachable.
