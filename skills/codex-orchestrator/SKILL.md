---
name: codex-orchestrator
description: Multi-agent orchestration for high-stakes Codex work. Use only when the user invokes $codex-orchestrator, or explicitly asks to orchestrate, act as architect and delegate implementation, spawn sub-agents or parallel workers, compare independent implementations, or run an external model CLI lane such as grok, claude, agy, or luna. Do not use for ordinary single-session coding such as fixing a bug, implementing a feature, refactoring, reviewing code, or planning alone.
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
4. For every external CLI lane, use one main-session shell invocation that runs the bundled supervisor `start` command and then enters `await`.
5. Use worker sub-agents for bounded code changes; use explorer sub-agents for narrow read-only questions.
6. Keep the launch receipt inside that shell invocation so the main model resumes only after `await` returns.
7. When `await` returns terminal state and result, review changes before integrating them.
8. Run the scoped verification command yourself.
9. Report only what the diff and verification evidence support.

## Five-Part Spec

Every delegated task must include all five parts. The worker should not need prior conversation context.

1. Objective: one short paragraph describing the exact change.
2. Files: exact files or modules the worker may edit or inspect.
3. Interfaces: signatures, schemas, API shapes, CLI flags, UI behavior, or data contracts that must remain stable.
4. Constraints: project conventions, ownership boundaries, instructions not to revert unrelated work, and anything explicitly out of scope.
5. Verification: the narrowest command or manual check that proves the task works within the changed scope.

If the spec cannot be written clearly, keep the decision in the main session until the ambiguity is settled.

## Context Budget

Keep each delegated spec between 4 KiB and 8 KiB when practical. The hard limit is 16 KiB measured as UTF-8 bytes. Never paste parent conversation history, full logs, complete diffs, generated files, or large source blocks into a delegated prompt. Pass exact file paths, symbols, line anchors, and `rg` patterns so the producer reads only what it needs from the workspace.

Write every external or Codex sub-agent spec to a temporary file and validate it before launch:

```bash
"$SKILL_DIR/scripts/lane-supervisor.sh" check-spec --spec "$SPEC"
```

If the file exceeds 16 KiB, split the task or replace copied material with workspace paths. Do not raise the limit. The supervisor also enforces the limit in `key` and `start`, so oversized external prompts cannot launch.

## Scoped Test And Format Policy

Unless the user explicitly approves broader verification for the current task, do not run a repository-wide test suite, all unit tests, or a repository-wide formatter or format check.

- Determine the verification scope from the task ownership boundary and changed paths.
- Prefer an exact test, test file, affected module, package, or workspace member over a broader test command.
- Pass only changed source paths to a formatter or format checker when the tool supports path-level checks.
- Put the exact scoped commands in every delegated spec. A producer must not broaden them on its own.
- Apply this policy to the main session, Codex workers, and every external CLI lane.
- If the project tooling cannot test or format only the affected scope, stop and ask the user for permission before running the broader command.
- Full tests or full-repository format checks require explicit user permission for that run.

This policy governs interactive and delegated task verification. Existing repository CI remains an independent project policy unless the user explicitly asks to change it.

## External Lane Launch Mode

Read [references/broker-lanes.md](references/broker-lanes.md) before starting an external CLI. By default, the main session runs `scripts/lane-supervisor.sh start` directly. The supervisor detaches the Grok, Claude, Antigravity, Luna, or Codex CLI process and immediately returns `STARTED` or `ALREADY_RUNNING`. It then owns process I/O, state, logs, result capture, and the completion marker without using a model.

Pass `--title`, `--model-label`, and `--mode read|write` on every supervisor start. These fields power the user-side `codex-orchestrator` Rust dashboard. Keep titles concise and report the actual model and effort in the model label.

Do not spawn a Broker merely to run the supervisor command. Direct launch avoids an extra Codex inference, sub-agent scheduling, and receipt handoff. The main session still owns the spec, routing, silent wait, diff review, and verification.

Use an optional Broker only when the user explicitly asks for a visible Broker sub-agent card or isolated launcher. "Broker" is a one-shot launcher role, not the process supervisor. Keep it one-to-one and spawn it with `fork_turns="none"`, `model="gpt-5.6-terra"`, `reasoning_effort="low"`, and the default service tier. Do not enable Fast for the Broker.

Optional Broker configuration:

```toml
[agents]
default_subagent_model = "gpt-5.6-terra"
default_subagent_reasoning_effort = "low"

[features.multi_agent_v2]
enabled = true
hide_spawn_agent_metadata = false
tool_namespace = "agents"
max_concurrent_threads_per_session = 7
min_wait_timeout_ms = 10000
default_wait_timeout_ms = 30000
max_wait_timeout_ms = 900000
```

The 30-second value is the general default only. When optional Brokers are used, call `agents.wait` once with `timeout_ms=900000` for their launch receipts.

Optional Broker duties:

- Receive only lane metadata, cwd, spec path, state directory, exact supervisor start command, and expected mode.
- Run the supplied supervisor start command exactly once.
- Return the launch receipt and finish immediately.
- Never run the external CLI directly.
- Never wait for the external CLI, inspect state, or read routine output after launch.
- Avoid reading, restating, or summarizing routine logs.
- Avoid judging code quality, architecture, findings, or completion correctness.

Broker status vocabulary:

```text
STARTED lane=<name> pid=<pid> state=<path> log=<path> result=<path> done=<path>
ALREADY_RUNNING lane=<name> pid=<pid> state=<path> log=<path> result=<path>
FAILED_TO_START lane=<name> reason=<short reason>
```

Give an optional Broker file paths, not parent history or copied spec contents. Its prompt must explicitly say: do not analyze the task, do not rewrite the spec, do not narrate progress, do not read any lane artifacts after launch, do not wait for completion, and finish immediately after the launch receipt.

The main Codex session remains the architect. It writes specs, chooses lanes, reads final artifacts after supervisor `await` returns, inspects diffs, and runs verification. When optional Broker mode is active, a completed Broker card is launch evidence only; it is not external-task completion evidence.

Run direct `start` and `await` inside one shell invocation. Capture the successful launch receipt inside the shell instead of returning it to the main model; if launch fails, return the error immediately. The `await` command blocks without model output and returns terminal state plus bounded result. Do not poll supervisor state, `done`, logs, diffs, or session files. Do not say that you are continuously monitoring. If the shell tool yields, continue only the same shell session with the longest supported wait and no commentary. For multiple lanes, start every lane and await all of them inside one blocking shell invocation. If optional Brokers were requested, wait once for their launch receipts before the same `await` step.

## Lane Selection

Use the cheapest adequate lane:

- Local edit: small or tightly coupled changes where delegation would add overhead.
- Grok external lane: default delegated producer when this skill is active and implementation or read-only review should leave the main session.
- Claude external lane: second independent producer or advisor lane when a separate judgment is useful.
- Antigravity external lane: third independent producer through `agy`, defaulting to `gemini-3.6-flash-high`. If the user says `Gemini` or names a Gemini model, use the Antigravity `agy` lane.
- Luna external lane: when the user says `luna`, use an independent Codex CLI producer fixed to `gpt-5.6-luna` with `max` reasoning and Fast service.
- Explorer sub-agent: Codex runtime lane for narrow read-only questions only when the user asks for Codex sub-agents, or chooses Codex sub-agents after a preferred external lane is unavailable.
- Worker sub-agent: Codex runtime lane for well-scoped implementation only when the user asks for Codex sub-agents, or chooses Codex sub-agents after a preferred external lane is unavailable.
- Parallel workers: use preferred external lanes first; use Codex runtime workers only for explicitly requested Codex sub-agent parallelism.
- Independent comparison: high-risk work where two implementations are useful to compare before choosing one.
- External CLI lane: when the user asks for a specific external model or wants a non-Codex producer.
- Advisor pass: commitment-boundary judgment, not implementation.

When this skill is active, "agent" means the skill's preferred delegated agents unless the user says "Codex sub-agent", `worker`, or `explorer`. The preferred order is Grok first, Claude second, Antigravity third. Use Codex `worker` / `explorer` only when the user explicitly asks for Codex sub-agents, or after a requested preferred lane is unavailable and the user chooses Codex sub-agents instead.

Do not use an Antigravity Claude model. If the user asks for Claude, use the Claude CLI lane. If the user asks for Gemini, use the Antigravity `agy` lane with a Gemini model.

Treat `luna` as an exact lane alias for Codex CLI model `gpt-5.6-luna` with reasoning effort `max` and service tier `priority`, which the Codex model catalog labels Fast. Do not route a `luna` request to a generic Codex `worker`, `explorer`, or the main session.

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
- The exact scoped verification command to run, or a precise reason if no scoped automated command exists.

Spawn every worker and explorer with `fork_turns="none"`. Send only the validated five-part spec as the sub-agent message. Never use the default full-history fork for this skill; a self-contained spec and workspace paths replace inherited conversation context.

When spawning an explorer, ask one or more specific questions. Do not ask for broad discovery unless the user requested broad parallel investigation.

Avoid sending multiple agents to edit the same files. If two independent implementations are requested for comparison, isolate them in separate worker branches or workspaces and judge the diffs before applying one.

## External CLI Lanes

External CLIs are optional. The skill is fully functional with local Codex work and Codex `worker` / `explorer` sub-agents alone.

When this skill is active and delegation is needed, external CLI lanes are the preferred delegated-agent producers. Use Grok first, Claude second, and Antigravity third unless the user names a different lane, explicitly asks for Codex sub-agents, or the work should stay local.

Use direct supervisor launch for every external lane, regardless of expected duration. Use optional Broker mode only when the user explicitly asks for it.

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

Edit-capable external commands passed to the supervisor:

```bash
env GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --no-subagents --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high --permission-mode bypassPermissions
agy --print "$(cat "$SPEC")" --mode accept-edits --dangerously-skip-permissions --model gemini-3.6-flash-high
codex exec --model gpt-5.6-luna -c 'model_reasoning_effort="max"' -c 'service_tier="priority"' --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"
```

Read-only external commands passed to the supervisor:

```bash
env GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --no-subagents --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high
agy --print "$(cat "$SPEC")" --mode plan --dangerously-skip-permissions --print-timeout 15m --model gemini-3.6-flash-high
codex exec --model gpt-5.6-luna -c 'model_reasoning_effort="max"' -c 'service_tier="priority"' --sandbox read-only --cd "$(pwd)" - < "$SPEC"
```

### External Agent Lifecycle

A quiet log is not proof that an external agent has stopped. Headless wrappers can stay quiet while the remote session or a tool call remains active.

When an external lane is launched:

1. Retain the prompt path, state directory, log path, result path, and done path.
2. In one shell invocation, run supervisor `start`, retain `STARTED` or `ALREADY_RUNNING` inside the shell, and continue directly into `await`.
3. Let only a launch error or the final `await` result return to the main model.
4. Do not read agent transcripts, supervisor state, CLI logs, diffs, `done`, or tool history while the lane runs.
5. Do not start a duplicate lane or issue routine status commands.
6. Do not cancel or kill a lane solely because it is quiet. Do not change permission mode as a reaction to an unclear stall.
7. The shell wait emits nothing while running. When it returns terminal state and result, inspect the actual diff.

Waiting must remain a non-model operation. Never produce updates such as "I am continuously monitoring", never read routine progress, and never start periodic status commands. If the command tool exposes a live session after yielding, wait on that same session at the maximum interval without any intervening analysis or user-facing narration.

If the user assigned implementation to a named external agent, that agent remains the implementation owner until its terminal state is confirmed. Do not silently replace it with local implementation while its session is active.

### Visible Logs

Keep external output outside the main model context. Return the supervisor's log path to the user so they can watch it in a terminal without making the main session read it.

When the Rust dashboard is installed, the user may run `codex-orchestrator` to see all Lanes, `codex-orchestrator agents` for an auto-updating horizontal-first grid of every running Agent, or `codex-orchestrator watch <task-id>` in separate terminal windows. Finished panes leave the Agents view automatically and newly started lanes enter it automatically. These commands are local file observers and do not consume Codex tokens. Do not run the interactive TUI through a model tool call, scrape its screen, or summarize its routine output.

For external CLI invocations:

- Let the supervisor write a task-keyed log file; Luna uses the compact event form described below.
- Read at most the final 16 KiB result snapshot after the CLI exits.
- Keep the state directory, log path, prompt path, process ID, and exit status in the final lane report.
- Do not read, restate, or summarize routine log output.
- Inspect the saved log only after a terminal failure when the bounded result does not explain it.
- Do not claim access to private model reasoning. Visible evidence means process state, tool output, logs, file diffs, todo/task status, and final text.

Luna log handling is different only at the output layer. Always run Luna through `scripts/codex-event-log.sh`, pass Codex `--json --output-last-message "$FINAL"`, and pass supervisor `--result-source "$FINAL"` exactly as shown in [references/broker-lanes.md](references/broker-lanes.md). Keep Luna on `gpt-5.6-luna`, `max`, Fast, and the requested permission mode with unrestricted tool count. The compact `lane.log` keeps command names, lifecycle, errors, agent messages, and usage. The complete JSONL stream is compressed after exit for diagnosis. Do not apply this wrapper to Claude.

Grok note: inherited MCP startup warnings are not terminal evidence if the lane prints task progress or a final response. Prefer disabling inherited Cursor/Claude MCP discovery for code tasks. Prefer `--no-subagents` so Grok remains a single external producer under one broker lane. Do not report `STATUS: unavailable` from MCP warnings alone. Quiet output is not enough to stop it.

Claude Code note: `claude -p` with text output is often quiet until final output. That is normal and not a completion signal. Use `--model sonnet --effort high` for the Claude lane unless the user asks for a different Claude model or effort such as `max`. Do not rerun a quiet Claude lane or inspect its stream while it is active.

Antigravity note: `agy --print` consumes the token immediately after `--print` as the prompt. Put the prompt immediately after `--print` or `-p`, then pass `--mode`, `--model`, and permission flags. Do not pipe the spec through stdin for `agy` print mode unless the installed CLI explicitly documents stdin support. For headless read-only work, always combine `--mode plan` with `--dangerously-skip-permissions`; plan mode keeps the lane in review posture while automatic approval lets it read files and run inspection commands without an unavailable prompt. Add `--print-timeout 15m` so repository reviews are not cut off by the five-minute default. State the no-edit contract in the spec and inspect the working-directory diff after the lane exits. Before starting or retrying, check whether the same Antigravity task still has a live process or session; do not stack a duplicate lane on top of active work. If the output says a tool required permission and was auto-denied, classify the attempt as invocation setup failure rather than a review result. If an `agy` response explains `--mode`, `--print-timeout`, or CLI usage instead of reading the repo/task, treat that lane attempt as an invocation setup failure and rerun once with the prompt-first form.

### Model Selection

If the user names a model, pass the model flag for that CLI. If the user names a Claude effort, pass that effort. If the user does not name a model, use the CLI default except for Claude and Antigravity: use `sonnet` for Claude and `gemini-3.6-flash-high` for Antigravity.

`luna` is a fixed alias, not an unspecified model request. Always pass `--model gpt-5.6-luna`, `-c 'model_reasoning_effort="max"'`, and `-c 'service_tier="priority"'`.

The Luna command examples below show producer arguments. The supervisor command must still add the JSON event wrapper, final-message path, raw-event path, and result source from [references/broker-lanes.md](references/broker-lanes.md).

The following examples are external commands passed directly to the supervisor:

```bash
# User specified a model for write-producing work.
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok -m grok-4.5 --no-subagents --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high --permission-mode bypassPermissions < "$SPEC"
agy --print "$(cat "$SPEC")" --mode accept-edits --dangerously-skip-permissions --model gemini-3.6-flash-high
codex exec --model gpt-5.5 --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"
codex exec --model gpt-5.6-luna -c 'model_reasoning_effort="max"' -c 'service_tier="priority"' --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"

# User did not specify a model; use each lane default for write-producing work.
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --no-subagents --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high --permission-mode bypassPermissions < "$SPEC"
agy --print "$(cat "$SPEC")" --mode accept-edits --dangerously-skip-permissions --model gemini-3.6-flash-high
codex exec --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"
```

Claude uses `--model sonnet --effort high` by default for this skill's Claude lane unless the user asks for another Claude model or effort such as `max`. For the `agy` lane, use `gemini-3.6-flash-high` unless the user names another Antigravity model.

Gemini is an Antigravity `agy` request. Use `agy --model "<Gemini model>"` for Gemini requests. Never select an Antigravity Claude model; route Claude requests to the Claude CLI lane instead.

Check available Grok models with `grok models`. Check Claude model aliases with `claude --help`. Check available Antigravity models with `agy models`.

Use `codex exec` only when the user explicitly asks for an independent Codex CLI producer or says `luna`. Run it in the current working directory by default; use a separate working directory or worktree only when the user explicitly requests it. For write-producing work, pass `--dangerously-bypass-approvals-and-sandbox`; always verify the diff before accepting changes.

For external CLI work:

1. Write the five-part spec to a unique temporary prompt file and run `check-spec`.
2. Record the current working directory. Use a separate path only when the user explicitly requested it.
3. Compute the supervisor task key and state directory, plus a concise title, accurate model label, and read/write mode.
4. Run the exact supervisor start command and `await` in one main-session shell invocation.
5. Keep `STARTED` or `ALREADY_RUNNING` inside the shell; return a launch error immediately.
6. For multiple lanes, start all of them before awaiting them in that same shell invocation.
7. If the shell yields, continue only its existing session at the longest supported wait without reading any other state.
8. When `await` returns, inspect the returned terminal state, bounded result, actual diff, and retained artifact paths.
9. Run the scoped verification yourself without broadening it unless the user approved that broader command.
10. Report status, changed files, verification output, log path, and any gaps.

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
- Run the narrowest relevant tests and format checks yourself, limited to the changed scope.
- Do not run all tests or a full-repository format check without explicit user permission.
- If no scoped command exists, ask before using a broader command and report the unverified gap until permission is granted.
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
