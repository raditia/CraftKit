## Ponytail rubric

Judge the code you were given by these six tags, and nothing else. Complexity only: correctness, security and performance belong to other reviewers.

| Tag | Fails when |
|-----|-----------|
| `delete:` | Dead code, flexibility nothing uses, or a speculative feature |
| `stdlib:` | Hand-rolled logic the standard library already provides |
| `native:` | A dependency, or hand-written code, doing what the platform already does |
| `yagni:` | Abstraction with one implementation, config nobody sets, or a single-caller layer |
| `shrink:` | Same logic achievable in fewer lines |
| `narrate:` | Comment restating the code, or denser comments than the file around it (see comment discipline above) |

Every finding names its replacement: the stdlib function, the platform feature, or the shorter form. `delete:`, `yagni:`, and `narrate:` replace with nothing, and that is the finding.

Protected, never counted as over-engineering by either side: validation at trust boundaries, error handling that prevents data loss, security and accessibility code, smoke tests / basic assertions, and anything already marked `ponytail:` or `flag:` (the marker is the contract, and a `flag:` branch is a live rollback path, not dead config). For `narrate:` specifically, also protected: a comment carrying a non-obvious *why*, a license/pragma header, and a doc comment on a public API a consumer reads without opening the file.

Lifted verbatim from `rules/karpathy-guidelines.md`, which the writing side authors under, so a finding here is never a rule the author could not have known. `check.sh` compares the two byte for byte, because one list drifting from the other is the whole point of having one list.
