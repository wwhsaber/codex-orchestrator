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
4. Use worker sub-agents for bounded code changes; use explorer sub-agents for narrow read-only questions.
5. Continue useful local work while sub-agents run.
6. Review returned changes before integrating them.
7. Run the verification command yourself.
8. Report only what the diff and verification evidence support.

## Five-Part Spec

Every delegated task must include all five parts. The worker should not need prior conversation context.

1. Objective: one short paragraph describing the exact change.
2. Files: exact files or modules the worker may edit or inspect.
3. Interfaces: signatures, schemas, API shapes, CLI flags, UI behavior, or data contracts that must remain stable.
4. Constraints: project conventions, ownership boundaries, instructions not to revert unrelated work, and anything explicitly out of scope.
5. Verification: command or manual check that proves the task works.

If the spec cannot be written clearly, keep the decision in the main session until the ambiguity is settled.

## Lane Selection

Use the cheapest adequate lane:

- Local edit: small or tightly coupled changes where delegation would add overhead.
- Grok external lane: default delegated producer when this skill is active and implementation or read-only review should leave the main session.
- Claude external lane: second independent producer or advisor lane when a separate judgment is useful.
- Antigravity external lane: third independent producer through `agy`, defaulting to `Gemini 3.5 Flash (High)`.
- Explorer sub-agent: Codex runtime lane for narrow read-only questions only when the user asks for Codex sub-agents, or chooses Codex sub-agents after a preferred external lane is unavailable.
- Worker sub-agent: Codex runtime lane for well-scoped implementation only when the user asks for Codex sub-agents, or chooses Codex sub-agents after a preferred external lane is unavailable.
- Parallel workers: use preferred external lanes first; use Codex runtime workers only for explicitly requested Codex sub-agent parallelism.
- Independent comparison: high-risk work where two implementations are useful to compare before choosing one.
- External CLI lane: when the user asks for a specific external model or wants a non-Codex producer.
- Advisor pass: commitment-boundary judgment, not implementation.

When this skill is active, "agent" means the skill's preferred delegated agents unless the user says "Codex sub-agent", `worker`, or `explorer`. The preferred order is Grok first, Claude second, Antigravity third. Use Codex `worker` / `explorer` only when the user explicitly asks for Codex sub-agents, or after a requested preferred lane is unavailable and the user chooses Codex sub-agents instead.

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

Before using an external CLI, run a preflight for the requested lane:

```bash
command -v grok && grok --version
command -v claude && claude --version
command -v agy && agy --version
command -v codex && codex --version
```

Use only the CLI that is installed, authenticated, and requested or appropriate for the lane. If a CLI is missing or not authenticated, report `STATUS: unavailable` with the exact reason.

If preflight fails, or lifecycle evidence proves that a requested external CLI is terminally unavailable, stop before doing equivalent work another way. Ask whether to install/configure that CLI or use Codex `worker` / `explorer` sub-agents instead. Missing stdout is not enough to make that determination.

### Execution Isolation

For write-producing external CLI work:

- Run in the current working directory by default. Create or select a separate worktree only when the user explicitly asks for one.
- Do not add a CLI sandbox merely because the task edits files. Use one only when the user explicitly requests it and it is compatible with that CLI's background and tool execution settings.
- A sandbox startup/configuration error is a lane setup failure; it is not evidence that a live agent should be stopped.
- Give the agent precise target files and `rg` patterns. Do not invite broad recursive repository inspection, especially through generated directories such as `node_modules`, `dist`, or build artifacts.

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

Do not hide an external lane behind output redirection alone. The main session needs live evidence of progress, plus a saved log for review.

For external CLI invocations:

- Save stdout/stderr to a unique log file and show it to the main session at the same time, normally with `tee`.
- Keep the log path, prompt path, process ID, and exit status in the final lane report.
- For long-running lanes, read the latest log lines during each lifecycle poll and summarize what changed.
- Do not claim access to private model reasoning. Visible evidence means process state, tool output, logs, file diffs, todo/task status, and final text.

Example:

```bash
SPEC=$(mktemp -t codex-orchestrator-spec.XXXXXX)
LOG=$(mktemp -t codex-orchestrator-lane.XXXXXX)

grok --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)" 2>&1 | tee "$LOG"
```

### Model Selection

If the user names a model, pass the model flag for that CLI. If the user does not name a model, omit the model flag and use the CLI default.

Examples:

```bash
# User specified a model.
grok -m grok-4.5 --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet < "$SPEC"
agy --print --model "Gemini 3.5 Flash (High)" < "$SPEC"
codex exec --model gpt-5.5 --cd "$(pwd)" - < "$SPEC"

# User did not specify a model; use each lane default.
grok --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p < "$SPEC"
agy --print --model "Gemini 3.5 Flash (High)" < "$SPEC"
codex exec --cd "$(pwd)" - < "$SPEC"
```

Antigravity is the exception to the generic default-model rule: for the `agy` lane, use `Gemini 3.5 Flash (High)` unless the user names another Antigravity model.

Check available Grok models with `grok models`. Check Claude model aliases with `claude --help`. Check available Antigravity models with `agy models`.

Use `codex exec` only when the user explicitly asks for an independent Codex CLI producer. Run it in the current working directory by default; use a separate working directory or worktree only when the user explicitly requests it. Keep permissions conservative and verify the diff before copying or accepting changes.

For external CLI work:

1. Write the five-part spec to a unique temporary prompt file.
2. Record the current working directory. Use a separate path only when the user explicitly requested it.
3. Invoke the CLI with visible logging: stream output to the main session and save the same output to a unique log file.
4. Retain its process/session identifiers, prompt path, log path, and exit status.
5. Monitor lifecycle state until a terminal condition is confirmed; do not use quiet output as a proxy for completion.
6. Capture its final message/log and the last active-task evidence.
7. Inspect the actual diff.
8. Run verification yourself.
9. Report status, changed files, verification output, log path, and any gaps.

Do not let an external CLI run with broad permissions unless the user explicitly asked for that risk.

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
