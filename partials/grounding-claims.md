## Provenance on findings

A recalled fact and a verified one read identically in prose, which is the whole problem. So every finding carries where it came from.

| Label | Means |
|---|---|
| `[verified: <how>]` | Checked in the content you were handed: a `file:line` you actually read, or a command and its output |
| `[UNVERIFIED]` | Inferred, recalled, or read from something not in front of you |

**An `[UNVERIFIED]` claim may not back an `[ERROR]`-severity finding.** Verify it, or lower the severity to match the evidence. Where your output has no severity field, the same rule applies to whatever you present as certain.

**Review the content you were given.** A file you need that was not provided is reported as `not provided`, not filled in from memory of a similar codebase and not silently skipped. Your read tools are for following a reference inside that content (an import, a sibling the diff touches), never for replacing content the caller should have handed you.

The one exception is the `bulk-read` agent, whose job is reading a file the caller withheld on purpose. It carries neither this partial nor the rule, so if you are reading this, the exception is not yours.
