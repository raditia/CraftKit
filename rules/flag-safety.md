---
name: flag-safety
description: Backward-compatibility laws for flag-gated code. Always active, so any change behind a feature flag, remote config, toggle, or experiment stays safe to turn off.
---

A flag exists to be turned off, and it gets turned off at the worst moment: mid-incident, on a stale client, by someone who never read the diff. So flag-gated work carries one law.

## The bar

**Flag OFF produces behavior observably identical to before the change.** Flag state is then the only variable, and flipping it is a complete fix: no revert, no hotfix, no data repair.

This applies to every gating mechanism, whatever the local name: feature flag, feature control, remote config, kill switch, A/B experiment, env var, build variant.

## Four surfaces that must stay compatible

| Surface | OFF-path requirement |
|---|---|
| **Code paths and shared helpers** | New behavior lives inside the branch. A shared util, hook, presenter, or ViewModel that both paths call keeps its old output for old inputs. Changing the shared thing is what actually breaks rollback; the branch itself rarely does |
| **Persisted and cached state** | State written while ON is readable, or safely ignorable, once the flag flips back OFF mid-session. New shape goes under a new key rather than redefining the old one, so the OFF path still finds what it wrote |
| **API request/response contracts** | The OFF path tolerates the new response shape, since the backend may already ship it. The ON path degrades to OFF behavior when the field is absent, since a client flip is instant and a deploy is not. Both directions hold at once |
| **Analytics and tracking** | The OFF path emits its original events with original names and parameters, so dashboards stay readable through rollout and rollback. New events are additive |

## Patterns that hold the bar

- **Default to old behavior.** A flag read that fails, times out, or returns undefined resolves to the pre-change path. Write the fallback explicitly at the read site.
- **Gate once, at the boundary.** One flag read near the entry point, passed down. A flag consulted in eight leaves has eight chances to be inverted and eight paths to test.
- **Keep the old code reachable.** The OFF branch calls the same function it called before, not a re-implementation that happens to agree today.
- **Test both states.** Tests assert OFF behavior matches the pre-change contract and ON behavior matches the new one. A flag-gated feature tested only ON is untested where it matters.

## The `flag:` marker

Every flag branch carries one comment naming the flag key, the OFF behavior, and the condition for removing the flag. It mirrors `ponytail:` in `karpathy-guidelines` rule 2, and it is what stops a later audit from deleting a live flag as dead config:

```ts
// flag: booking-seat-map-v2. off: legacy seat grid via getSeatRows(). remove: 100% rollout + 2 weeks stable.
```

## Verification, before reporting done

Any turn that adds or edits a flag branch reports one line naming what it checked: `flag self-pass: <key> OFF path verified <how>` (a test, a local flip, or the traced call path). Unverified is worse than absent, since an OFF path nobody exercised is a rollback that fails under load.
