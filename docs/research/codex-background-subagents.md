# Codex CLI: background subagents, mid-run messages, stop

**Date:** 2026-10-06 · **Task:** T1 in `docs/planning/director-mode.md` · **CLI checked:** `codex-cli 0.160.0` (`codex --version`), source at tag `rust-v0.160.0`

## Question

Does Codex CLI let the main session (a) spawn a subagent that runs in the background while the
main session keeps accepting user prompts, (b) send a message or refinement to a subagent that is
still running, and (c) stop a running subagent? What are the primitive names, and what config
turns them on?

## Method

Read the official subagents and config-reference docs (the `developers.openai.com/codex/*` URLs
now 308-redirect to `learn.chatgpt.com/docs/...`), the tool specs and agent control code in
`github.com/openai/codex` at tag `rust-v0.160.0`, and the local CLI (`codex --help`,
`codex features list`, `codex queue --help`, `codex agents --help`, and `strings` on the installed
binary to confirm the same tool names ship in 0.160.0). No prompt was sent to a model.

## Answer

| | Verdict | Evidence |
|---|---|---|
| (a) background spawn, main session keeps taking prompts | **PARTIAL** | `spawn_agent` returns at once and the model is told "While the subagent is running in the background, do meaningful non-overlapping work immediately" (`multi_agents_spec.rs:729`); the user can steer the active turn, and v2 `wait_agent` "also ends early when new user input is steered into the active turn" (`multi_agents_spec.rs:287`). But a child's completion is delivered to the parent with `trigger_turn: false` / `inject_fragment_without_turn` (`agent/control.rs:496`, `:514`), so an idle main session is not woken; it sees the result only on its next turn. |
| (b) message a running subagent | **YES** | v1 `send_input`: "Send a message to an existing agent. Use interrupt=true to redirect work immediately" (`multi_agents_spec.rs:175`), `interrupt` false "queues it" (`:164`). v2 adds `send_message` (`:204`) and `followup_task`, which delivers to a running target "at message boundaries while sampling, or after the pending tool call completes" (`:237`). Docs: "Ask Codex directly to steer a running subagent" (subagents page). |
| (c) stop a running subagent | **YES** | v1 `close_agent`: "Close an agent and any open descendants ... return the target agent's previous status before shutdown was requested" (`multi_agents_spec.rs:328`). v2 `interrupt_agent`: "Interrupt an agent's current turn ... The agent remains available for messages" (`:352`). Docs: ask Codex to "stop it", or in the background-agent panel "stop active subagents" (subagents page). |

## Primitives

All are model-invoked tools, not user slash commands; the user reaches them by asking the main
session in natural language (subagents page: "use direct instructions such as 'spawn two agents'").

| Name | Set | What it does | Citation |
|---|---|---|---|
| `spawn_agent` | v1 and v2 | Start a child thread; v1 takes `agent_type`, `fork_context`, `model`, `reasoning_effort`; v2 takes `task_name` and `fork_turns` (`"none"` passes no surrounding context) | `multi_agents_spec.rs:65`, `:100`, `:600-646`, `:768` |
| `send_input` | v1 | Message an existing agent; `interrupt=true` redirects now, otherwise queued | `multi_agents_spec.rs:147-175`, `:164` |
| `resume_agent` | v1 | Reopen a closed agent so it can receive `send_input` and `wait_agent` | `multi_agents_spec.rs:246` |
| `wait_agent` | v1 | Block until agents reach a final status; returns empty on timeout | `multi_agents_spec.rs:274` |
| `wait_agent` | v2 | Wait for any mailbox update; ends early on steered user input; returns a summary, not content | `multi_agents_spec.rs:287` |
| `close_agent` | v1 | Shut down an agent and its descendants; completed agents hold a concurrency slot until closed | `multi_agents_spec.rs:328` |
| `send_message` | v2 | Message an existing agent, delivered promptly, does not trigger a new turn | `multi_agents_spec.rs:204` |
| `followup_task` | v2 | Give an existing agent a new task; starts a turn if idle, else delivers at the next boundary | `multi_agents_spec.rs:237` |
| `interrupt_agent` | v2 | Interrupt the agent's current turn; it stays available | `multi_agents_spec.rs:352` |
| `list_agents` | v2 | List live agents in the root thread tree | `multi_agents_spec.rs:296` |
| `/agent` | TUI | User switches to and inspects running agent threads | subagents page |
| `codex queue --thread <id> --message <text>` | CLI | Queue a message for an existing session from outside the TUI | `codex queue --help` |

Config, from the config reference and `codex features list` on this machine:

- `features.multi_agent`: "Enable multi-agent collaboration tools (spawn_agent, send_input, resume_agent, wait_agent, and close_agent) (stable; on by default)". Local: `multi_agent stable true`.
- `features.multi_agent_v2`: gates the v2 set (`send_message`, `followup_task`, `interrupt_agent`, `list_agents`). Local: `multi_agent_v2 stable false`, so it is off unless enabled.
- `agents.enabled` (default true), `agents.max_concurrent_threads_per_session` (legacy alias `agents.max_threads`), `agents.default_subagent_model`, `agents.default_subagent_reasoning_effort`, `agents.interrupt_message`, and `agents.<name>.config_file` / `.description` for custom roles.

## Implications for director mode

Codex covers the steer and stop halves: `send_input` (or v2 `send_message` / `followup_task`)
plays the part of Claude's `SendMessage`, and `close_agent` (or v2 `interrupt_agent`) plays the
part of `TaskStop`. What it lacks is the wake-up. A child's completion is injected into the
parent without starting a turn (`agent/control.rs:496`, `:514`), and the documented workflow is
"Codex waits until all requested results are available, then returns a consolidated response"
(subagents page). So director mode on Codex should not promise "chat stays open and results
arrive on their own". It should degrade to delegate, keep working (or steer) inside the active
turn, `wait_agent`, then integrate; any result that lands after the turn ends is picked up on the
user's next prompt. Whether children survive the end of the parent turn untouched was not traced
in source here `[UNVERIFIED]`, so the safe contract is to collect every result before the turn
ends, which matches what `partials/parallel-classifier.md:24-26` already prescribes.

## Sources

- Subagents docs: https://learn.chatgpt.com/docs/agent-configuration/subagents (redirected from https://developers.openai.com/codex/subagents), fetched 2026-10-06
- Config reference: https://learn.chatgpt.com/docs/config-file/config-reference (redirected from https://developers.openai.com/codex/config-reference), entries `features.multi_agent`, `agents.*`
- CLI docs: https://learn.chatgpt.com/docs/codex/cli ("Steer the active turn")
- Tool specs: https://github.com/openai/codex/blob/rust-v0.160.0/codex-rs/core/src/tools/handlers/multi_agents_spec.rs
- Handlers: https://github.com/openai/codex/tree/rust-v0.160.0/codex-rs/core/src/tools/handlers/multi_agents (`close_agent.rs`, `resume_agent.rs`, `send_input.rs`, `spawn.rs`, `wait.rs`) and `.../multi_agents_v2` (`followup_task.rs`, `interrupt_agent.rs`, `list_agents.rs`, `send_message.rs`, `spawn.rs`, `wait.rs`)
- Completion delivery: https://github.com/openai/codex/blob/rust-v0.160.0/codex-rs/core/src/agent/control.rs (`maybe_start_completion_watcher`, lines 426-520)
- Local CLI 0.160.0: `codex --help`, `codex features list`, `codex queue --help`, `codex agents --help`; `strings` on the binary lists `spawn_agent send_input resume_agent wait_agent close_agent send_message followup_task interrupt_agent list_agents`
- This repo: `rules/using-agent-skills.md:12-42` (CRAFTKIT-CODEX block), `adapters/codex.sh:25`, `partials/parallel-classifier.md:19-31`
