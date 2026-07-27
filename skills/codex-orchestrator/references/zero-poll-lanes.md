# Zero-Poll Lanes

Read this reference when an external CLI lane is expected to run longer than 90 seconds or when conserving Codex tokens is a priority.

## Start

Use the bundled supervisor:

```bash
SUPERVISOR="$SKILL_DIR/scripts/lane-supervisor.sh"
TASK_KEY=$("$SUPERVISOR" key --lane "$LANE" --cwd "$(pwd)" --spec "$SPEC")
STATE_DIR="${TMPDIR:-/tmp}/codex-orchestrator/$TASK_KEY"
```

The task key combines lane, working directory, and spec content. Starting the same live task again returns `ALREADY_RUNNING` instead of creating another process.

Grok:

```bash
"$SUPERVISOR" start \
  --lane grok \
  --cwd "$(pwd)" \
  --spec "$SPEC" \
  --state-dir "$STATE_DIR" \
  -- env GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false \
    grok --no-subagents --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
```

Claude:

```bash
"$SUPERVISOR" start \
  --lane claude \
  --cwd "$(pwd)" \
  --spec "$SPEC" \
  --stdin "$SPEC" \
  --state-dir "$STATE_DIR" \
  -- claude -p --model sonnet --effort high
```

Antigravity:

```bash
"$SUPERVISOR" start \
  --lane gemini \
  --cwd "$(pwd)" \
  --spec "$SPEC" \
  --state-dir "$STATE_DIR" \
  -- agy --print "$(cat "$SPEC")" --mode plan --dangerously-skip-permissions \
    --print-timeout 15m --model gemini-3.6-flash-high
```

Add each CLI's broad edit approval flags for write-producing work.

## Wait

After `STARTED`:

- Do not call `status` on a timer.
- Do not read the lane log, session JSONL, thinking, or tool history.
- Register the `done` marker with a completion callback when the runtime provides one.
- When no completion callback exists, report the start receipt and end the current turn. Resume after the user returns or an external notification arrives.
- Do not continue local writes against the same assigned files while a delegated producer owns them.

The user may watch the log path in a terminal or dashboard without routing it through the model context.

## Status

Only when the user explicitly asks:

```bash
"$SUPERVISOR" status --state-dir "$STATE_DIR"
```

The snapshot is a fixed small record containing lifecycle state, PID, paths, exit code, byte count, and truncation state. Do not supplement it with routine log reads.

## Complete

On a completion event:

```bash
"$SUPERVISOR" status --state-dir "$STATE_DIR"
"$SUPERVISOR" result --state-dir "$STATE_DIR"
```

Read each once. `result.txt` contains at most the final 32 KiB of lane output; `lane.log` retains the full output for targeted failure diagnosis. Then inspect the actual diff and run verification in the main session.

For a failed lane, read only the result first. Read a bounded log tail only when the result does not explain the failure.
