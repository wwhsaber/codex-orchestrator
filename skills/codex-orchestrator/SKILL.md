---
name: codex-orchestrator
description: Multi-agent orchestration for high-stakes Codex work. Use only when the user invokes $codex-orchestrator, or explicitly asks to orchestrate, act as architect and delegate implementation, spawn sub-agents or parallel workers, compare independent implementations, or run an external model CLI lane such as grok or claude. Do not use for ordinary single-session coding such as fixing a bug, implementing a feature, refactoring, reviewing code, or planning alone.
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
- Explorer sub-agent: narrow codebase questions that can be answered read-only.
- Worker sub-agent: well-scoped implementation with a clear write set and verification command.
- Parallel workers: independent tasks with disjoint files and no ordering dependency.
- Independent comparison: high-risk work where two implementations are useful to compare before choosing one.
- External CLI lane: when the user asks for a specific external model or wants a non-Codex producer.
- Advisor pass: commitment-boundary judgment, not implementation.

When the user asks for "two agents", "two independent reviews", "two implementations", "compare two approaches", or similar wording under this skill, treat that as a request for independent model producers first: use Grok and Claude external CLI lanes when available. Use Codex `worker` / `explorer` sub-agents for that request only when the user explicitly asks for Codex sub-agents, or after a requested external lane is unavailable and the user chooses Codex sub-agents instead.

Lane choice is a cost and context decision. Use the cheapest lane that can preserve correctness.

When a lane is unavailable, say so plainly. Use another lane only after making the change in route explicit.

## Sub-Agent Rules

In Codex, `worker` and `explorer` are runtime sub-agent types. They are not loaded from repository `agents/*.md` files. The bundled `agents/openai.yaml` file is only UI metadata for the skill card.

Do not treat a generic request for "agents" as Codex `worker` / `explorer` by default when this skill is active. If the user did not specify Codex sub-agents, check whether the wording implies independent model producers and route to external CLI lanes first.

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

Use external CLIs only when the user asks for them, when the skill invocation explicitly includes them, or when a distinct model producer is worth the extra setup and verification cost.

Before using an external CLI, run a preflight for the requested lane:

```bash
command -v grok && grok --version
command -v claude && claude --version
command -v codex && codex --version
```

Use only the CLI that is installed, authenticated, and requested or appropriate for the lane. If a CLI is missing or not authenticated, report `STATUS: unavailable` with the exact reason.

If a requested external CLI is unavailable, stop before doing equivalent work another way. Ask whether to install/configure that CLI or use Codex `worker` / `explorer` sub-agents instead.

### Model Selection

If the user names a model, pass the model flag for that CLI. If the user does not name a model, omit the model flag and use the CLI default.

Examples:

```bash
# User specified a model.
grok -m grok-4.5 --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet < "$SPEC"
codex exec --model gpt-5.5 --cd "$(pwd)" - < "$SPEC"

# User did not specify a model; use the CLI default.
grok --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p < "$SPEC"
codex exec --cd "$(pwd)" - < "$SPEC"
```

Check available Grok models with `grok models`. Check Claude model aliases with `claude --help`.

Use `codex exec` only when the user explicitly asks for an independent Codex CLI producer. Run it in a separate working directory or worktree, keep permissions conservative, and verify the diff before copying or accepting changes.

For external CLI work:

1. Write the five-part spec to a unique temporary prompt file.
2. Invoke the CLI from the repo root.
3. Capture the final message or log.
4. Inspect the actual diff.
5. Run verification yourself.
6. Report status, changed files, verification output, and any gaps.

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
