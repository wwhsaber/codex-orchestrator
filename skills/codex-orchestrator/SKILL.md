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
4. For external CLI work, start the named external CLI lane from the main session with `tee` and a broker status line. Use a Codex runtime broker sub-agent only when the user explicitly asks for a visible Codex sub-agent and the current multi-agent surface supports that UI.
5. Use worker sub-agents for bounded code changes; use explorer sub-agents for narrow read-only questions.
6. Continue useful local work while sub-agents run.
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

## Broker Lanes

Use a lightweight broker role for external CLI lanes. "Broker" means lifecycle control for one lane; it does not always mean a Codex runtime sub-agent. The default broker path is the `b66b746` style: the main session starts the external CLI command, streams logs with `tee`, and reports structured status lines.

The broker is one-to-one with a single external lane: one Grok broker controls only Grok, one Claude broker controls only Claude, and one Antigravity broker controls only `agy`.

The broker exists to reduce main-session token use and make long-running CLI work easier to watch. It is an I/O controller, not a reviewer or implementer.

Default broker path:

- The main session writes the spec and log path.
- The main session starts the external CLI command with `tee`.
- The main session prints `STARTED`, `RUNNING`, `NEEDS_ATTENTION`, `EXITED`, or `FAILED_TO_START`.
- The main session monitors process state, log path, and working-tree diff.
- Do not spawn a Codex runtime sub-agent just to call Grok, Claude, or `agy`.

Codex runtime broker path:

- Use this only when the user explicitly asks for a visible Codex sub-agent broker, or asks for multiple visible broker agents in the active sub-agent UI.
- Use this only when the current multi-agent surface supports visible labels or exposes stdout well enough for the user to watch logs.
- When visible task labels are supported, spawn runtime broker agents with these exact labels:

- `Grok broker` controls only the Grok CLI lane.
- `Claude broker` controls only the Claude CLI lane.
- `Gemini broker` controls only the Antigravity `agy` Gemini lane.

If the current runtime sub-agent API only returns an assigned nickname and has no visible label field, do not create a runtime broker solely for display. Run the default broker path instead. Do not imply that repository `agents/*.md`, `agents/openai.yaml`, or published Workspace Agents can control runtime nicknames.

Visibility rule: the user must be able to watch raw external CLI output. In Codex, a normal sub-agent may show only "thinking" or a compact status instead of its terminal stdout. If broker stdout is not directly visible to the user, do not let a runtime broker own the external CLI process. Use the default broker path from the main session.

Broker duties:

- Receive lane name, command, cwd, spec path, log path, and expected mode.
- Start exactly one external CLI process from the main session by default.
- Let a runtime broker start the process only when the user explicitly asked for a visible Codex sub-agent broker and its stdout is user-visible.
- Keep pid, prompt path, log path, exit code, and last status.
- Stream output with `tee` so the user can watch logs directly.
- Report only state changes, terminal states, and attention-needed states.
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

Use the cheapest adequate sub-agent model if model selection is available, such as `5.4-mini` or the smallest low-latency model exposed by the runtime. The broker prompt must explicitly say: do not analyze the task, do not rewrite the spec, do not summarize normal output, and do not stop a lane because stdout is quiet for a short period.

The main Codex session remains the architect. It writes specs, chooses lanes, reads final artifacts, inspects diffs, and runs verification. Broker reports are lifecycle evidence only.

## Lane Selection

Use the cheapest adequate lane:

- Local edit: small or tightly coupled changes where delegation would add overhead.
- Grok external lane: default delegated producer when this skill is active and implementation or read-only review should leave the main session.
- Claude external lane: second independent producer or advisor lane when a separate judgment is useful.
- Antigravity external lane: third independent producer through `agy`, defaulting to `Gemini 3.5 Flash (High)`. If the user says `Gemini` or names a Gemini model, use the Antigravity `agy` lane.
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

When an external lane is expected to run longer than a quick single response, use the default broker path: the main session writes the spec, starts the command with visible `tee`, and follows the broker status vocabulary. Use a runtime broker sub-agent only when the user explicitly asks for a visible Codex sub-agent broker and the current surface can show the lane clearly.

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

### Execution Isolation

For write-producing external CLI work:

- Run in the current working directory by default. Create or select a separate worktree only when the user explicitly asks for one.
- Give the lane broad write-lane permissions when the spec asks it to modify files. A write-producing lane without edit and tool permission is a setup error, not an implementation attempt.
- Do not add a CLI sandbox merely because the task edits files. Use one only when the user explicitly requests it and it is compatible with that CLI's background and tool execution settings.
- A sandbox startup/configuration error is a lane setup failure; it is not evidence that a live agent should be stopped.
- Give the agent precise target files and `rg` patterns. Do not invite broad recursive repository inspection, especially through generated directories such as `node_modules`, `dist`, or build artifacts.

### Execution Mode

Match permissions to the lane contract:

- Read-only review or advisor lane: keep default or plan/read-only behavior.
- Write-producing implementation lane: pass that CLI's broad edit and tool approval mode to avoid permission stalls.
- If the lane reports it cannot edit, stop and rerun the same spec with edit permission instead of asking it to describe the patch.
- For Grok write-producing lanes, use `--permission-mode bypassPermissions`. Do not combine `--check` with `--no-subagents`; those flags are mutually exclusive.

Edit-capable examples:

```bash
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)" 2>&1 | tee "$LOG"
claude -p --effort high --permission-mode bypassPermissions < "$SPEC" 2>&1 | tee "$LOG"
agy --print --mode accept-edits --dangerously-skip-permissions --model "Gemini 3.5 Flash (High)" < "$SPEC" 2>&1 | tee "$LOG"
```

Read-only examples:

```bash
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)" 2>&1 | tee "$LOG"
claude -p --effort high < "$SPEC" 2>&1 | tee "$LOG"
agy --print --mode plan --model "Gemini 3.5 Flash (High)" < "$SPEC" 2>&1 | tee "$LOG"
```

### External Agent Lifecycle

A quiet terminal is not proof that an external agent has stopped. Headless wrappers can return an early text chunk while the remote session or a tool call remains active.

When an external lane is running:

1. Retain the process and session identifiers, the latest agent update, active tool call IDs, and its declared todo/task state where the CLI exposes them.
2. Monitor actual lifecycle evidence: process state, session updates, tool-call status, todo/task progress, and the target working-directory diff. Lack of stdout alone is not a failure signal.
3. Poll long-running work at a measured cadence, normally every 30-60 seconds. Record what changed between polls so a later handoff can continue from evidence instead of guessing.
4. Do not cancel or kill a lane while it has an in-progress tool call, an active remote session, or pending declared work solely because it appears quiet or exceeds a short local timeout.
5. A lane may be terminated only when the user asks to stop, the CLI reports a terminal failure/cancellation, the process and session are both terminal, or repeated polling shows no active work and no progress for a documented threshold. Before termination, report the evidence and preserve the session details.
6. Do not change a CLI's permission mode or enable bypass-style approval settings as a reaction to an unclear stall. Diagnose lifecycle state first.

If the user assigned implementation to a named external agent, that agent remains the implementation owner until its terminal state is confirmed. Do not silently replace it with local implementation while its session is active.

### Visible Logs

Do not hide an external lane behind output redirection alone. The user should be able to watch the live output, and the main session should keep a saved log path for later checks.

For external CLI invocations:

- Save stdout/stderr to a unique log file and show it in user-visible terminal output at the same time, normally with `tee`.
- Keep the log path, prompt path, process ID, and exit status in the final lane report.
- Do not read, restate, or summarize routine log output. The user can watch it directly.
- Inspect the saved log only when the lane appears stuck, exits, fails, or the user asks for status.
- Do not claim access to private model reasoning. Visible evidence means process state, tool output, logs, file diffs, todo/task status, and final text.

Example:

```bash
SPEC=$(mktemp -t codex-orchestrator-spec.XXXXXX)
LOG=$(mktemp -t codex-orchestrator-lane.XXXXXX)

GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)" 2>&1 | tee "$LOG"
```

Grok note: inherited MCP startup warnings are not terminal evidence if the lane prints task progress or a final response. Prefer disabling inherited Cursor/Claude MCP discovery for code tasks. Do not report `STATUS: unavailable` from MCP warnings alone. If a Grok lane is quiet after an initial plan, inspect process/session state and the saved log; a short period without stdout is not enough to stop it.

Claude Code note: `claude -p` with text output is often quiet until final output. That is normal and not a completion signal. Use `--effort high` for the Claude lane unless the user asks for a different Claude effort such as `max`. If a Claude lane appears stuck or the user asks for status, rerun or inspect with filtered stream JSON rather than raw stream output, because raw stream output can include thinking content:

```bash
claude -p --effort high --verbose --output-format stream-json --permission-mode bypassPermissions < "$SPEC" 2>&1 \
  | tee "$LOG" \
  | jq -r 'if .type=="system" then "[system] " + (.subtype // .status // "event") elif .type=="result" then "[result] done" elif .type=="assistant" then (.message.content[]? | select(.type=="text") | .text) else empty end'
```

### Model Selection

If the user names a model, pass the model flag for that CLI. If the user names a Claude effort, pass that effort. If the user does not name a model, omit the model flag and use the CLI default.

Examples:

```bash
# User specified a model for write-producing work.
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok -m grok-4.5 --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high --permission-mode bypassPermissions < "$SPEC"
agy --print --mode accept-edits --dangerously-skip-permissions --model "Gemini 3.5 Flash (High)" < "$SPEC"
codex exec --model gpt-5.5 --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"

# User did not specify a model; use each lane default for write-producing work.
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --effort high --permission-mode bypassPermissions < "$SPEC"
agy --print --mode accept-edits --dangerously-skip-permissions --model "Gemini 3.5 Flash (High)" < "$SPEC"
codex exec --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"
```

Claude uses `--effort high` by default for this skill's Claude lane unless the user asks for another Claude effort such as `max`. Antigravity is the exception to the generic default-model rule: for the `agy` lane, use `Gemini 3.5 Flash (High)` unless the user names another Antigravity model.

Gemini is an Antigravity `agy` request. Use `agy --model "<Gemini model>"` for Gemini requests. Never select an Antigravity Claude model; route Claude requests to the Claude CLI lane instead.

Check available Grok models with `grok models`. Check Claude model aliases with `claude --help`. Check available Antigravity models with `agy models`.

Use `codex exec` only when the user explicitly asks for an independent Codex CLI producer. Run it in the current working directory by default; use a separate working directory or worktree only when the user explicitly requests it. For write-producing work, pass `--dangerously-bypass-approvals-and-sandbox`; always verify the diff before accepting changes.

For external CLI work:

1. Write the five-part spec to a unique temporary prompt file.
2. Record the current working directory. Use a separate path only when the user explicitly requested it.
3. Write a unique log path.
4. Start the external CLI from the main session with `tee`.
5. Print `STARTED lane=<name> pid=<pid> log=<path> prompt=<path>`.
6. Use a runtime broker sub-agent only when the user explicitly asks for a visible Codex sub-agent broker and the current multi-agent surface supports visible labels or visible stdout.
7. Retain process/session identifiers, prompt path, log path, and exit status.
8. Monitor lifecycle state until a terminal condition is confirmed; do not use quiet output as a proxy for completion.
9. Capture final text/log and the last active-task evidence.
10. Inspect the actual diff.
11. Run verification yourself.
12. Report status, changed files, verification output, log path, and any gaps.

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
