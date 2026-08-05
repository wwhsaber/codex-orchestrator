# Broker Launcher Lanes

Use one lightweight Codex broker sub-agent to launch each external CLI lane. The broker starts the bundled non-model supervisor and exits as soon as the supervisor returns `STARTED` or `ALREADY_RUNNING`. It never waits for the external CLI process.

## Runtime Profile

The launcher and the external producer are separate layers:

```text
Broker launcher: gpt-5.6-terra, low reasoning, default service, fork_turns=none
Lane supervisor: shell process, no model and no Codex tokens
Luna producer: gpt-5.6-luna, max reasoning, priority service (Fast)
```

Do not let a broker inherit the parent's conversation history. Terra Low is the lightest native sub-agent profile accepted by the current runtime; do not enable Fast for a broker.

## Broker Input

Pass only:

- Lane name.
- Working directory.
- Spec path.
- Exact supervisor start command.
- Read-only or write-producing mode.

Do not copy parent history or the spec body into the broker prompt.

## Broker Contract

Use this contract:

```text
You are a one-shot launcher for exactly one external CLI lane.
Run the supplied lane-supervisor.sh start command once.
Do not run the external CLI directly.
Do not analyze the task, rewrite the spec, inspect the diff, or narrate progress.
Do not read the lane log, result, state, or done marker after launch.
Never wait for the external CLI and never start a duplicate process.
Return the single STARTED, ALREADY_RUNNING, or launch-error receipt, then finish immediately.
```

## State Directory

Before spawning the broker, the main session computes the stable task key and state directory:

```bash
SUPERVISOR="$SKILL_DIR/scripts/lane-supervisor.sh"
TASK_KEY=$("$SUPERVISOR" key --lane "$LANE" --cwd "$CWD" --spec "$SPEC")
STATE_DIR="${TMPDIR:-/tmp}/codex-orchestrator/$TASK_KEY"
```

The task key combines lane, working directory, and spec content. Starting the same live task again returns `ALREADY_RUNNING` instead of creating another external process.

## Start Commands

Grok:

```bash
"$SUPERVISOR" start \
  --lane grok --cwd "$CWD" --spec "$SPEC" --state-dir "$STATE_DIR" -- \
  env GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false \
  grok --no-subagents --prompt-file "$SPEC" --output-format plain --cwd "$CWD"
```

Claude:

```bash
"$SUPERVISOR" start \
  --lane claude --cwd "$CWD" --spec "$SPEC" --stdin "$SPEC" --state-dir "$STATE_DIR" -- \
  claude -p --model sonnet --effort high
```

Antigravity:

```bash
"$SUPERVISOR" start \
  --lane gemini --cwd "$CWD" --spec "$SPEC" --state-dir "$STATE_DIR" -- \
  agy --print "$(cat "$SPEC")" --mode plan --dangerously-skip-permissions \
  --print-timeout 15m --model gemini-3.6-flash-high
```

Luna:

```bash
EVENT_LOG="$SKILL_DIR/scripts/codex-event-log.sh"
FINAL="$STATE_DIR/luna-final.txt"
RAW="$STATE_DIR/luna-events.jsonl"

"$SUPERVISOR" start \
  --lane luna --cwd "$CWD" --spec "$SPEC" --stdin "$SPEC" --state-dir "$STATE_DIR" \
  --result-source "$FINAL" -- \
  "$EVENT_LOG" --raw "$RAW" -- \
  codex exec --json --output-last-message "$FINAL" \
  --model gpt-5.6-luna -c 'model_reasoning_effort="max"' \
  -c 'service_tier="priority"' --sandbox read-only --cd "$CWD" -
```

For write-producing Luna work, replace `--sandbox read-only` with `--dangerously-bypass-approvals-and-sandbox`. Do not change Luna's model, `max` reasoning, Fast service, permissions, or tool access for log-size control. `lane.log` retains command lifecycle, errors, agent messages, and usage without successful command output. While running, the complete JSONL stream is at `luna-events.jsonl`; after exit it is compressed to `luna-events.jsonl.gz`. The exact final message is copied through `luna-final.txt` into `result.txt`.

Add each other CLI's broad edit approval flags for write-producing work. Gemini requests always use Antigravity `agy`; do not select an Antigravity Claude model.

## After Launch

Wait once for the launcher brokers to return their receipts. After every receipt:

1. Report `state`, `log`, `result`, and `done` paths to the user.
2. Start one silent, blocking supervisor wait in the main session:

```bash
"$SUPERVISOR" await --state-dir "$STATE_DIR"
```

3. Do not poll `status`, agent transcripts, logs, diffs, or the `done` marker.
4. Do not narrate waiting progress or summarize routine activity.
5. If the command tool yields a live shell session, continue only that same session with the longest supported wait. Never start another wait or read another artifact.
6. The user may watch `lane.log` directly without routing it through a model.
7. When `await` returns, use its single terminal state and bounded result to inspect the diff and verify.

For multiple lanes, run all required `await` commands inside one blocking shell invocation so the main model does not wake between lane completions.

The completed Broker card proves only that the background lane was launched. It does not claim that the external task finished.

## Await, Status And Result

`await` emits nothing while the process runs. After `done` appears, it returns `AWAIT_COMPLETE`, the state snapshot, and `result.txt` exactly once. This keeps automatic continuation without model-side status turns.

Use `status` separately only when the user explicitly asks for status:

```bash
"$SUPERVISOR" status --state-dir "$STATE_DIR"
```

Use `result` separately only when state is already terminal and `await` was not used:

```bash
"$SUPERVISOR" result --state-dir "$STATE_DIR"
```

`result.txt` contains at most the final 16 KiB of output. Grok, Claude, and Antigravity keep their normal full `lane.log`. Luna keeps a compact `lane.log`, its exact final message in `result.txt`, and its compressed raw event stream beside them for targeted diagnosis. After completion, inspect the actual diff and run verification in the main session.
