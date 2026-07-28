---
name: codex-orchestrator
description: Multi-agent orchestration for high-stakes Codex work. Use only when the user invokes $codex-orchestrator, or explicitly asks to orchestrate, act as architect and delegate implementation, spawn sub-agents or parallel workers, compare independent implementations, or run an external model CLI lane such as grok, claude, or agy. Do not use for ordinary single-session coding such as fixing a bug, implementing a feature, refactoring, reviewing code, or planning alone.
---

# Codex Orchestrator

Use this skill to keep the main Codex session in the architect role: decide the shape of the work, write precise specs, delegate bounded implementation when useful, and accept only evidence-backed results.

## Operating Rule

The main session owns requirements, decomposition, interface design, routing, and final verification. Implementation may be delegated when the user has explicitly asked for this skill, delegation, sub-agents, parallel work, or external model lanes.

Do not delegate by habit. Keep work local when the task is small, tightly coupled, blocked on immediate context, or faster to edit directly. Delegate only concrete, bounded tasks that can run without sharing a write set with ongoing local work.

Before choosing a route, reduce the task to first principles: user goal, hard constraints, repo facts, unknowns, and the smallest action that follows.

## Workflow

1. Inspect the repo enough to understand the target files, conventions, tests, current git state, and facts that control lane choice.
2. Decide what stays local and what, if anything, can be delegated.
3. For each delegated task, write the full five-part spec below.
4. For every external CLI lane, use the bundled supervisor.
5. Use worker sub-agents for bounded code changes; use explorer sub-agents for narrow read-only questions.
6. Continue useful local work while delegated lanes run.
7. Review returned changes before integrating them.
8. Run the verification command yourself.
9. Report only what the diff and verification evidence support.

## Five-Part Spec

Every delegated task must include all five parts. The worker should not need prior conversation context.

1. Objective: one short paragraph describing the exact change.
2. Files: exact files or modules the worker may edit or inspect.
3. Interfaces: signatures, schemas, API shapes, CLI flags, UI behavior, or data contracts that must remain stable.
4. Constraints: project conventions, ownership boundaries, instructions not to revert unrelated work, and anything explicitly out of scope.
5. Verification: command or manual check that proves the task works.

If the spec cannot be written clearly, keep the decision in the main session until the ambiguity is settled.

## Zero-Poll CLI Mode

Read [references/zero-poll-lanes.md](references/zero-poll-lanes.md) and launch every Grok, Claude, Antigravity, and Codex CLI lane with `scripts/lane-supervisor.sh`. Do not estimate task duration and do not run an external lane in the foreground.

The supervisor is a non-model process. It waits for the external CLI, writes a small state snapshot, keeps the full log outside model context, limits the result snapshot, creates a completion marker, and rejects duplicate starts for the same lane, working directory, and spec.

After a supervised lane returns `STARTED`:

- Do not poll it on a timer.
- Do not read its log or session files while it runs.
- Use a runtime completion callback for the supervisor's `done` marker when available.
- When no completion callback exists, report the start receipt and end the current turn. Resume only after the user returns or an external completion notification arrives.
- Read the small state and result snapshots once after a terminal event, then inspect the diff and verify.

## Optional Broker Mode

Use a lightweight broker sub-agent for external CLI lanes only when the user explicitly asks to see broker sub-agents in the Codex UI, asks for broker mode, or wants structured status cards for long-running lanes. "Broker" is a role assigned to a Codex sub-agent, not a separate system. The broker is one-to-one with a single external lane: one Grok broker sub-agent controls only Grok, one Claude broker sub-agent controls only Claude, and one Antigravity broker sub-agent controls only `agy`.

Broker mode is easier to watch in the Codex UI, but it consumes Codex tokens because the broker itself is a Codex sub-agent. Use supervisor mode without a broker when saving Codex tokens is more important than UI status cards.

Broker duties:

- Receive lane name, command, cwd, spec path, log path, and expected mode.
- Start exactly one external CLI process.
- Keep pid, prompt path, log path, exit code, and last status.
- Start the bundled supervisor and retain its state directory.
- Report only the start receipt, terminal state, or attention-needed state.
- Avoid reading, restating, or summarizing routine logs.
- Avoid judging code quality, architecture, findings, or completion correctness.

Broker status vocabulary:

```text
STARTED lane=<name> pid=<pid> log=<path> prompt=<path>
RUNNING lane=<name> evidence=<process|session|tool|diff>
NEEDS_ATTENTION lane=<name> reason=<short reason> evidence=<short evidence>
EXITED lane=<name> status=<code> log=<path>
FAILED_TO_START lane=<name> reason=<short reason> log=<path>
```

Use the cheapest adequate sub-agent model if model selection is available, such as `5.4-mini` or the smallest low-latency model exposed by the runtime. Give the broker only lane metadata and file paths, not parent history or the spec contents. The broker prompt must explicitly say: do not analyze the task, do not rewrite the spec, do not read routine logs, and do not stop a lane because stdout is quiet for a short period.

The main Codex session remains the architect. It writes specs, chooses lanes, reads final artifacts, inspects diffs, and runs verification. Broker reports are lifecycle evidence only.

## Lane Selection

Use the cheapest adequate lane:

- Local edit: small or tightly coupled changes where delegation would add overhead.
- Grok external lane: default delegated producer when this skill is active and implementation or read-only review should leave the main session.
- Claude external lane: second independent producer or advisor lane when a separate judgment is useful.
- Antigravity external lane: third independent producer through `agy`, defaulting to `gemini-3.6-flash-high`. If the user says `Gemini` or names a Gemini model, use the Antigravity `agy` lane.
- Explorer sub-agent: Codex runtime lane for narrow read-only questions only when the user asks for Codex sub-agents, or chooses Codex sub-agents after a preferred external lane is unavailable.
- Worker sub-agent: Codex runtime lane for well-scoped implementation only when the user asks for Codex sub-agents, or chooses Codex sub-agents after a preferred external lane is unavailable.
- Parallel workers: use preferred external lanes first; use Codex runtime workers only for explicitly requested Codex sub-agent parallelism.
- Independent comparison: high-risk work where two implementations are useful to compare before choosing one.
- External CLI lane: when the user asks for a specific external model or wants a non-Codex producer.
- Advisor pass: commitment-boundary judgment, not implementation.

When this skill is active, "agent" means the skill's preferred delegated agents unless the user says "Codex sub-agent", `worker`, or `explorer`. The preferred order is Grok first, Claude second, Antigravity third. Use Codex `worker` / `explorer` only when the user explicitly asks for Codex sub-agents, or after a requested preferred lane is unavailable and the user chooses Codex sub-agents instead.

Do not use an Antigravity Claude model. If the user asks for Claude, use the Claude CLI lane. If the user asks for Gemini, use the Antigravity `agy` lane with a Gemini model.

Lane choice is a cost and context decision. Use the cheapest lane that can preserve correctness.

When a lane is unavailable, say so plainly. Use another lane only after making the change in route explicit.

## Sub-Agent Rules

In Codex, `worker` and `explorer` are runtime sub-agent types. They are not loaded from repository `agents/*.md` files. The bundled `agents/openai.yaml` file is only UI metadata for the skill card.

Do not treat a generic request for "agents" as Codex `worker` / `explorer` by default when this skill is active. If the user did not specify Codex sub-agents, route delegated work to the preferred external lanes first.

When spawning a worker, include:

- The five-part spec.
- A clear ownership boundary for files or modules.
- A reminder that other edits may exist and must not be reverted.
- A request to edit files directly in the worker workspace and list changed paths.
- The exact verification command to run, or a precise reason if no automated command exists.

When spawning an explorer, ask one or more specific questions. Do not ask for broad discovery unless the user requested broad parallel investigation.

Avoid sending multiple agents to edit the same files. If two independent implementations are requested for comparison, isolate them in separate worker branches or workspaces and judge the diffs before applying one.

## External CLI Lanes

External CLIs are optional. The skill is fully functional with local Codex work and Codex `worker` / `explorer` sub-agents alone.

When this skill is active and delegation is needed, external CLI lanes are the preferred delegated-agent producers. Use Grok first, Claude second, and Antigravity third unless the user names a different lane, explicitly asks for Codex sub-agents, or the work should stay local.

Use supervised Zero-Poll mode for every external lane, regardless of expected duration. Use broker mode only when the user explicitly asks for broker sub-agents, visible sub-agent cards, or structured broker status.

Before using an external CLI, run a preflight for the requested lane:

```bash
command -v grok && grok --version
command -v claude && claude --version
command -v agy && agy --version
command -v codex && codex --version
```

Use only the CLI that is installed, authenticated, and requested or appropriate for the lane. If a CLI is missing or not authenticated, report `STATUS: unavailable` with the exact reason.

If preflight fails, or lifecycle evidence proves that a requested external CLI is terminally unavailable, stop before doing equivalent work another way. Ask whether to install/configure that CLI or use Codex `worker` / `explorer` sub-agents instead. Missing stdout is not enough to make that determination.

For Grok lanes, disable inherited Cursor and Claude MCP discovery unless the task explicitly needs those MCP servers. This prevents unrelated local MCP startup failures, such as an unavailable Figma SSE port or invalid third-party tool names, from polluting code-review and implementation runs:

```bash
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok ...
```

Use `--no-subagents` for Grok lanes by default. A Grok lane is already a delegated producer from the main Codex session; letting Grok spawn more agents inside that lane makes ownership, logs, permissions, and terminal-state checks harder to trust. Allow Grok subagents only when the user explicitly asks Grok to coordinate its own subagents for that task. Do not combine `--check` with `--no-subagents`; those flags are mutually exclusive.

### Execution Isolation

For write-producing external CLI work:

- Run in the current working directory by default. Create or select a separate worktree only when the user explicitly asks for one.
- Give the lane broad write-lane permissions when the spec asks it to modify files. A write-producing lane without edit and tool permission is a setup error, not an implementation attempt.
- Do not add a CLI sandbox merely because the task edits files. Use one only when the user explicitly requests it and it is compatible with that CLI's background and tool execution settings.
- A sandbox startup/configuration error is a lane setup failure; it is not evidence that a live agent should be stopped.
- Give the agent precise target files and `rg` patterns. Do not invite broad recursive repository inspection, especially through generated directories such as `node_modules`, `dist`, or build artifacts.

### Execution Mode

Match permissions to the lane contract:

- Read-only review or advisor lane: keep plan/read-only behavior, but auto-approve headless read and command requests when the CLI cannot prompt.
- Write-producing implementation lane: pass that CLI's broad edit and tool approval mode to avoid permission stalls.
- If the lane reports it cannot edit, stop and rerun the same spec with edit permission instead of asking it to describe the patch.
- For Grok write-producing lanes, use `--permission-mode bypassPermissions` and `--no-subagents` unless the user explicitly asks Grok to run its own subagents. Do not combine `--check` with `--no-subagents`; those flags are mutually exclusive.

Edit-capable command payloads to pass after the supervisor's `--` separator:

```bash
env GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --no-subagents --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high --permission-mode bypassPermissions
agy --print "$(cat "$SPEC")" --mode accept-edits --dangerously-skip-permissions --model gemini-3.6-flash-high
```

Read-only command payloads to pass after the supervisor's `--` separator:

```bash
env GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --no-subagents --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high
agy --print "$(cat "$SPEC")" --mode plan --dangerously-skip-permissions --print-timeout 15m --model gemini-3.6-flash-high
```

### External Agent Lifecycle

A quiet terminal is not proof that an external agent has stopped. Headless wrappers can return an early text chunk while the remote session or a tool call remains active.

When an external lane is running:

1. Retain the supervisor state directory and the one-line start receipt.
2. Do not schedule heartbeat, status, session, log, diff, or tool-history checks.
3. Treat only a completion callback, a supervisor terminal marker, an explicit CLI terminal event, or a user status request as permission to inspect state.
4. For a user status request, read only the supervisor state snapshot. Do not add a log read unless the snapshot is terminal and indicates failure.
5. On a terminal event, read state once and result once. Read a bounded log tail only when failure diagnosis requires it.
6. Do not cancel or kill a lane solely because it is quiet. Do not change permission mode as a reaction to an unclear stall.
7. Never start the same task again when the supervisor reports `ALREADY_RUNNING`.

If the user assigned implementation to a named external agent, that agent remains the implementation owner until its terminal state is confirmed. Do not silently replace it with local implementation while its session is active.

### Visible Logs

Keep full external output outside the model context. Return the supervisor's log path to the user so they can watch it in a terminal or dashboard without making the main model read it.

For external CLI invocations:

- Let the supervisor write `lane.log`; do not stream external output through the model tool response.
- Do not invoke an external lane through a foreground shell pipeline or `tee`.
- Keep the log path, prompt path, process ID, and exit status in the final lane report.
- Do not read, restate, or summarize routine log output.
- Inspect the saved log only after a terminal failure when the bounded result does not explain it.
- Do not claim access to private model reasoning. Visible evidence means process state, tool output, logs, file diffs, todo/task status, and final text.

Grok note: inherited MCP startup warnings are not terminal evidence if the lane prints task progress or a final response. Prefer disabling inherited Cursor/Claude MCP discovery for code tasks. Prefer `--no-subagents` so Grok remains a single external producer under one supervised CLI lane. Do not report `STATUS: unavailable` from MCP warnings alone. Quiet output is not enough to stop it.

Claude Code note: `claude -p` with text output is often quiet until final output. That is normal and not a completion signal. Use `--model sonnet --effort high` for the Claude lane unless the user asks for a different Claude model or effort such as `max`. Do not rerun a quiet Claude lane or inspect its stream while it is active.

Antigravity note: `agy --print` consumes the token immediately after `--print` as the prompt. Put the prompt immediately after `--print` or `-p`, then pass `--mode`, `--model`, and permission flags. Do not pipe the spec through stdin for `agy` print mode unless the installed CLI explicitly documents stdin support. For headless read-only work, always combine `--mode plan` with `--dangerously-skip-permissions`; plan mode keeps the lane in review posture while automatic approval lets it read files and run inspection commands without an unavailable prompt. Add `--print-timeout 15m` so repository reviews are not cut off by the five-minute default. State the no-edit contract in the spec and inspect the working-directory diff after the lane exits. Before starting or retrying, check whether the same Antigravity task still has a live process or session; do not stack a duplicate lane on top of active work. If the output says a tool required permission and was auto-denied, classify the attempt as invocation setup failure rather than a review result. If an `agy` response explains `--mode`, `--print-timeout`, or CLI usage instead of reading the repo/task, treat that lane attempt as an invocation setup failure and rerun once with the prompt-first form.

### Model Selection

If the user names a model, pass the model flag for that CLI. If the user names a Claude effort, pass that effort. If the user does not name a model, use the CLI default except for Claude and Antigravity: use `sonnet` for Claude and `gemini-3.6-flash-high` for Antigravity.

The following examples are command payloads to pass after the supervisor's `--` separator:

```bash
# User specified a model for write-producing work.
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok -m grok-4.5 --no-subagents --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high --permission-mode bypassPermissions < "$SPEC"
agy --print "$(cat "$SPEC")" --mode accept-edits --dangerously-skip-permissions --model gemini-3.6-flash-high
codex exec --model gpt-5.5 --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"

# User did not specify a model; use each lane default for write-producing work.
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --no-subagents --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high --permission-mode bypassPermissions < "$SPEC"
agy --print "$(cat "$SPEC")" --mode accept-edits --dangerously-skip-permissions --model gemini-3.6-flash-high
codex exec --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"
```

Claude uses `--model sonnet --effort high` by default for this skill's Claude lane unless the user asks for another Claude model or effort such as `max`. For the `agy` lane, use `gemini-3.6-flash-high` unless the user names another Antigravity model.

Gemini is an Antigravity `agy` request. Use `agy --model "<Gemini model>"` for Gemini requests. Never select an Antigravity Claude model; route Claude requests to the Claude CLI lane instead.

Check available Grok models with `grok models`. Check Claude model aliases with `claude --help`. Check available Antigravity models with `agy models`.

Use `codex exec` only when the user explicitly asks for an independent Codex CLI producer. Run it in the current working directory by default; use a separate working directory or worktree only when the user explicitly requests it. For write-producing work, pass `--dangerously-bypass-approvals-and-sandbox`; always verify the diff before accepting changes.

For external CLI work:

1. Write the five-part spec to a unique temporary prompt file.
2. Record the current working directory. Use a separate path only when the user explicitly requested it.
3. Compute its task key and start the bundled supervisor.
4. Retain only the start receipt and state directory in the main context.
5. Register a completion callback when available; otherwise end the current turn after reporting `STARTED`.
6. Do not poll or read routine logs while the lane runs.
7. On a terminal event, read the state and bounded result once.
8. Read a bounded log tail only for an unexplained failure.
9. Inspect the actual diff.
10. Run verification yourself.
11. Report status, changed files, verification output, log path, and any gaps.

Use broad permissions only for write-producing lanes. Keep read-only reviews, advisor passes, and preflight checks on read-only or default modes.

Write external prompts from the same first-principles outline: goal, facts, unknowns, constraints, and success criteria. Treat the output as a proposal to verify, not authority.

## Advisor Pass

Use an advisor pass before:

- Architecture choices.
- Data migrations.
- Public API or schema design.
- Refactors touching several modules.
- A bug that has resisted two distinct attempts.
- Declaring a large multi-step deliverable complete.

The advisor is read-only. Use a local self-review or a read-only explorer pass. Ask for a verdict under 300 words: do X, not Y, because Z; include the one risk that decides it. If the plan is sound, the advisor should say so briefly.

## Verification

Worker reports are claims, not evidence.

The producer of a change cannot be its only verifier. The architect must run or inspect the proof.

Before reporting completion:

- Read `git status` and the relevant diff.
- Check that changed files match the assigned ownership boundary.
- Run the verification command yourself.
- If verification fails, either fix locally if the issue is small and within scope, or send a corrected spec back to the worker.
- If verification cannot be run, state exactly why and what manual inspection was performed.
- For an external agent, confirm that the process, session, and active tool state are terminal before treating its final text as completion evidence.

Never report completion from a worker or CLI message alone.

## Final Report

Keep the final user-facing report short:

```text
Implemented [objective].
Changed: [paths and short purpose].
Verified: [command and result].
Notes: [gaps, skipped checks, or none].
```

For reviews, lead with findings and file/line references instead of this completion format.
