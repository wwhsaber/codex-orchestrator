# External CLI Lanes

By default, launch each external CLI lane by running the bundled non-model supervisor directly from the main session. The `start` command returns `STARTED` or `ALREADY_RUNNING` immediately; the supervisor then owns the detached external process.

## Runtime Profile

The main session, supervisor, and external producer are separate layers:

```text
Main session: writes the spec, starts the supervisor, waits once, and verifies
Lane supervisor: shell process, no model and no Codex tokens
Luna producer: gpt-5.6-luna, max reasoning, priority service (Fast)
```

Direct launch is the default because a deterministic shell command does not require another model inference.

## Launch Input

The main session computes and passes:

- Lane name.
- Working directory.
- Spec path.
- Exact supervisor start command.
- Read-only or write-producing mode.
- A concise task title and accurate model label for the terminal dashboard.

The spec should normally be 4-8 KiB and must not exceed 16 KiB. Validate it before computing the task key:

```bash
"$SUPERVISOR" check-spec --spec "$SPEC"
```

The `key` and `start` commands repeat this check. Replace copied conversation, logs, diffs, and source blocks with precise workspace paths and search anchors.

## State Directory

Before starting the lane, the main session computes the stable task key and state directory:

```bash
SUPERVISOR="$SKILL_DIR/scripts/lane-supervisor.sh"
TASK_KEY=$("$SUPERVISOR" key --lane "$LANE" --cwd "$CWD" --spec "$SPEC")
STATE_DIR="${TMPDIR:-/tmp}/codex-orchestrator/$TASK_KEY"
```

The task key combines lane, working directory, and spec content. Starting the same live task again returns `ALREADY_RUNNING` instead of creating another external process.

## Start Commands

Always pass `--title`, `--model-label`, and `--mode` to `start`. Use the actual selected model in the label, and set mode to `read` or `write`. The examples below are read-only:

Grok:

```bash
"$SUPERVISOR" start \
  --lane grok --cwd "$CWD" --spec "$SPEC" --state-dir "$STATE_DIR" \
  --title "$TITLE" --model-label "grok default" --mode read -- \
  env GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false \
  grok --no-subagents --prompt-file "$SPEC" --output-format plain --cwd "$CWD"
```

Claude:

```bash
"$SUPERVISOR" start \
  --lane claude --cwd "$CWD" --spec "$SPEC" --stdin "$SPEC" --state-dir "$STATE_DIR" \
  --title "$TITLE" --model-label "sonnet / high" --mode read -- \
  claude -p --model sonnet --effort high
```

Antigravity:

```bash
"$SUPERVISOR" start \
  --lane gemini --cwd "$CWD" --spec "$SPEC" --state-dir "$STATE_DIR" \
  --title "$TITLE" --model-label "gemini-3.6-flash-high" --mode read -- \
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
  --result-source "$FINAL" --title "$TITLE" \
  --model-label "gpt-5.6-luna / max / fast" --mode read -- \
  "$EVENT_LOG" --raw "$RAW" -- \
  codex exec --json --output-last-message "$FINAL" \
  --model gpt-5.6-luna -c 'model_reasoning_effort="max"' \
  -c 'service_tier="priority"' --sandbox read-only --cd "$CWD" -
```

For write-producing Luna work, replace `--sandbox read-only` with `--dangerously-bypass-approvals-and-sandbox`. Do not change Luna's model, `max` reasoning, Fast service, permissions, or tool access for log-size control. `lane.log` retains command lifecycle, errors, agent messages, and usage without successful command output. While running, the complete JSONL stream is at `luna-events.jsonl`; after exit it is compressed to `luna-events.jsonl.gz`. The exact final message is copied through `luna-final.txt` into `result.txt`.

Add each other CLI's broad edit approval flags for write-producing work. Gemini requests always use Antigravity `agy`; do not select an Antigravity Claude model.

## Direct Launch And Await

Run `start` and `await` in one shell invocation so a successful launch receipt does not create a model turn:

```bash
launch_receipt=$("$SUPERVISOR" start \
  --lane "$LANE" --cwd "$CWD" --spec "$SPEC" --state-dir "$STATE_DIR" \
  --title "$TITLE" --model-label "$MODEL_LABEL" --mode "$MODE" -- \
  COMMAND ARGUMENTS) || exit $?
"$SUPERVISOR" await --state-dir "$STATE_DIR"
```

Replace `COMMAND ARGUMENTS` with the lane command from the preceding section and include any required `--stdin` or `--result-source` supervisor options. If `start` fails, return its error immediately. On success:

1. Keep `launch_receipt` inside the shell; do not return it to the main model before completion.
2. Do not poll `status`, agent transcripts, logs, diffs, or the `done` marker.
3. Do not narrate waiting progress or summarize routine activity.
4. If the command tool yields a live shell session, continue only that same session with the longest supported wait. Never start another wait or read another artifact.
5. The user may watch `lane.log` directly without routing it through a model.
6. When `await` returns, use its single terminal state and bounded result to inspect the diff and verify.

For multiple lanes, start every lane before the first `await`, then run all required `await` commands inside that same blocking shell invocation so the main model does not wake between lane completions.

The captured `STARTED` receipt proves only that the background lane was launched. It does not claim that the external task finished.

## User Terminal Dashboard

The optional Rust binary discovers every state directory under `${TMPDIR:-/tmp}/codex-orchestrator` and shows all running and finished Lanes without sending logs through a model:

```bash
codex-orchestrator
codex-orchestrator list --all
codex-orchestrator watch <task-id>
```

Multiple terminals may watch different task IDs concurrently. The TUI reads `state`, `lane.log`, and `result.txt`; it never changes the main session's silent `await`. Its stop action calls the recorded supervisor controller and requires confirmation.

## Optional Broker Mode

Use a Broker only when the user explicitly asks for a visible Broker sub-agent card or isolated launcher. Spawn one Terra Low Broker per external lane with `fork_turns="none"`, low reasoning, and default service. Give it only the lane metadata, working directory, spec path, state directory, exact supervisor start command, and expected mode.

The optional Broker runs the supplied `start` command exactly once, returns `STARTED`, `ALREADY_RUNNING`, or a short launch error, and exits. It must not analyze the task, copy the spec body, inspect artifacts, wait for the external process, or narrate progress. Wait once for all Broker launch receipts, then use the same silent supervisor `await` flow. A completed Broker card remains launch evidence only.

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

Stop a Lane only on explicit user action:

```bash
"$SUPERVISOR" stop --state-dir "$STATE_DIR"
```

`result.txt` contains at most the final 16 KiB of output. Grok, Claude, and Antigravity keep their normal full `lane.log`. Luna keeps a compact `lane.log`, its exact final message in `result.txt`, and its compressed raw event stream beside them for targeted diagnosis. After completion, inspect the actual diff and run verification in the main session.
