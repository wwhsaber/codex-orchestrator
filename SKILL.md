---
name: codex-orchestrator
description: Architect-style orchestration for Codex coding work. Use when the user asks Codex to act as an architect, delegate implementation, use sub-agents, run parallel workers, compare independent implementations, keep the main session focused on planning and review, use external model CLIs such as grok or claude, or verify worker changes before reporting completion.
---

# Codex Orchestrator

Use this skill to keep the main Codex session in the architect role: decide the shape of the work, write precise specs, delegate bounded implementation when useful, and accept only evidence-backed results.

## Operating Rule

The main session owns requirements, decomposition, interface design, routing, and final verification. Implementation may be delegated when the user has explicitly asked for this skill, delegation, sub-agents, parallel work, or external model lanes.

Do not delegate by habit. Keep work local when the task is small, tightly coupled, blocked on immediate context, or faster to edit directly. Delegate only concrete, bounded tasks that can run without sharing a write set with ongoing local work.

## Workflow

1. Inspect the repo enough to understand the target files, conventions, tests, and current git state.
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

When a lane is unavailable, say so plainly. Use another lane only after making the change in route explicit.

## Sub-Agent Rules

When spawning a worker, include:

- The five-part spec.
- A clear ownership boundary for files or modules.
- A reminder that other edits may exist and must not be reverted.
- A request to edit files directly in the worker workspace and list changed paths.
- The exact verification command to run, or a precise reason if no automated command exists.

When spawning an explorer, ask one or more specific questions. Do not ask for broad discovery unless the user requested broad parallel investigation.

Avoid sending multiple agents to edit the same files. If two independent implementations are requested for comparison, isolate them in separate worker branches or workspaces and judge the diffs before applying one.

## External CLI Lanes

Use external CLIs only when the user asks for them, when the skill invocation explicitly includes them, or when the task benefits from a distinct model producer.

Before using an external CLI, run a preflight:

```bash
command -v grok && grok --version
command -v claude && claude --version
command -v codex && codex --version
```

Use only the CLI that is installed, authenticated, and requested or appropriate for the lane. If a CLI is missing or not authenticated, report `STATUS: unavailable` with the exact reason.

### Model Selection

If the user names a model, pass the model flag for that CLI. If the user does not name a model, omit the model flag and use the CLI default.

Examples:

```bash
grok -m grok-4.5 --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet < "$SPEC"
codex exec --model gpt-5.5 --cd "$(pwd)" - < "$SPEC"
```

Check available Grok models with `grok models`. Check Claude model aliases with `claude --help`.

For external CLI work:

1. Write the five-part spec to a unique temporary prompt file.
2. Invoke the CLI from the repo root.
3. Capture the final message or log.
4. Inspect the actual diff.
5. Run verification yourself.
6. Report status, changed files, verification output, and any gaps.

Do not let an external CLI run with broad permissions unless the user explicitly asked for that risk.

## Advisor Pass

Use an advisor pass before:

- Architecture choices.
- Data migrations.
- Public API or schema design.
- Refactors touching several modules.
- A bug that has resisted two distinct attempts.
- Declaring a large multi-step deliverable complete.

The advisor is read-only. Ask for a verdict under 300 words: do X, not Y, because Z; include the one risk that decides it. If the plan is sound, the advisor should say so briefly.

## Verification

Worker reports are claims, not evidence.

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
