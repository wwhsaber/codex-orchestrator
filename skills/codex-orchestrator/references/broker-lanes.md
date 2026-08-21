# External CLI Lanes

Launch external CLI lanes through the bundled runtime selector. The main session writes one bounded spec, starts the lane, blocks once in `await`, and verifies the final diff. Herdr owns the PTY when its server is available; the existing shell supervisor remains available when it is not. Neither runtime uses model tokens.

## Shared Setup

```bash
RUNTIME="$SKILL_DIR/scripts/lane-runtime.sh"
ADAPTER="$SKILL_DIR/scripts/agent-output.mjs"
STATE_DIR=$("$RUNTIME" state-dir --lane "$LANE" --cwd "$CWD" --spec "$SPEC")
WATCH="$STATE_DIR/lane.log"
FINAL="$STATE_DIR/final.txt"
DIAGNOSTIC="$STATE_DIR/diagnostic.log"
```

Runtime selection uses `CODEX_ORCHESTRATOR_RUNTIME`:

- `auto` (default): use Herdr when its CLI and server are ready, otherwise use the shell supervisor.
- `herdr`: require Herdr and fail at launch when its server is unavailable.
- `supervisor`: always use the bundled shell process runtime.

Do not set `CODEX_ORCHESTRATOR_RUNTIME` for a normal launch. The unset value is `auto`, so a ready Herdr server is preferred. Set `supervisor` only when the user explicitly requests it or a recorded Herdr launch failure makes `auto` unusable. When Herdr is ready, explicit supervisor mode also requires `CODEX_ORCHESTRATOR_SUPERVISOR_REASON=user_requested` or `herdr_launch_failed`; do not invent either reason. A retry keeps the runtime used by the original task unless the user approves a change.

`state-dir` is the only supported way to compute `STATE_DIR`. It uses `CODEX_ORCHESTRATOR_STATE_ROOT` when set and otherwise uses `${TMPDIR:-/tmp}/codex-orchestrator`. Task keys stay stable when the selected runtime changes. Do not assemble this path manually or hardcode `/tmp/codex-orchestrator`; `start` rejects a directory that differs from the runtime calculation.

`lane-runtime.sh` is the only supported launch entry point. Do not call `lane-supervisor.sh start` directly; that backend rejects direct starts.

Herdr must be installed and started outside the skill. On macOS with Homebrew, use `brew install herdr`, then run `herdr server` or `brew services start herdr`. If the background service lacks access to a workspace under `Documents`, start the server from a Terminal or desktop App shell that has that permission. The selector never installs software or starts an interactive TUI.

Validate every spec first:

```bash
"$RUNTIME" check-spec --spec "$SPEC"
```

The spec should normally be 4-8 KiB and cannot exceed 16 KiB. Pass workspace paths and search anchors instead of conversation history, logs, diffs, or large source blocks.

Every start command must include these runtime arguments:

```bash
--lane "$LANE" --cwd "$CWD" --spec "$SPEC" --state-dir "$STATE_DIR" \
--result-source "$FINAL" --ephemeral-watch \
--title "$TITLE" --model-label "$MODEL_LABEL" --mode "$MODE"
```

`MODE` is `read` or `write`. The examples below are read-only unless stated otherwise.

## Lane Commands

### Grok

```bash
"$RUNTIME" start \
  --lane grok --cwd "$CWD" --spec "$SPEC" --state-dir "$STATE_DIR" \
  --result-source "$FINAL" --ephemeral-watch \
  --title "$TITLE" --model-label "grok-4.5" --mode read -- \
  env GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false \
  node "$ADAPTER" --format grok --watch "$WATCH" --final "$FINAL" \
  --diagnostic "$DIAGNOSTIC" -- \
  grok --no-subagents --model grok-4.5 --prompt-file "$SPEC" \
  --output-format streaming-messages-json --include-partial-messages --cwd "$CWD"
```

For write work add `--permission-mode bypassPermissions`. If the user names another model, replace both `--model grok-4.5` and the model label with that model. Keep `--no-subagents` unless the user explicitly asks Grok to coordinate its own subagents. Do not combine `--check` with `--no-subagents`.

Grok sessions are fresh unless the user explicitly requests continuation. For the latest Grok conversation in the lane working directory, add `--continue`. For an exact prior Orchestrator task, obtain the persisted ID with `"$RUNTIME" producer-session --task-id "$TASK_ID"` and add `--resume "$SESSION_ID"`. Keep the new spec and runtime state separate even though Grok reuses its conversation.

### Claude

```bash
"$RUNTIME" start \
  --lane claude --cwd "$CWD" --spec "$SPEC" \
  --state-dir "$STATE_DIR" --result-source "$FINAL" --ephemeral-watch \
  --title "$TITLE" --model-label "sonnet / high" --mode read -- \
  node "$ADAPTER" --format claude --watch "$WATCH" --final "$FINAL" \
  --diagnostic "$DIAGNOSTIC" --stdin-file "$SPEC" -- \
  claude -p --model sonnet --effort high --verbose \
  --output-format stream-json --include-partial-messages
```

For write work add `--permission-mode bypassPermissions`.

### Gemini Through Antigravity

```bash
"$RUNTIME" start \
  --lane gemini --cwd "$CWD" --spec "$SPEC" --state-dir "$STATE_DIR" \
  --result-source "$FINAL" --ephemeral-watch \
  --title "$TITLE" --model-label "gemini-3.6-flash-high" --mode read -- \
  node "$ADAPTER" --format agy --watch "$WATCH" --final "$FINAL" \
  --diagnostic "$DIAGNOSTIC" -- \
  agy --print "$(cat "$SPEC")" --mode plan --dangerously-skip-permissions \
  --print-timeout 15m --model gemini-3.6-flash-high --output-format stream-json
```

The prompt must immediately follow `--print`. For write work replace `--mode plan` with `--mode accept-edits`; retain `--dangerously-skip-permissions` so a headless permission prompt cannot stall the lane. Never use an Antigravity Claude model.

### OpenCode

```bash
"$RUNTIME" start \
  --lane opencode --cwd "$CWD" --spec "$SPEC" --state-dir "$STATE_DIR" \
  --result-source "$FINAL" --ephemeral-watch \
  --title "$TITLE" --model-label "opencode default" --mode read -- \
  node "$ADAPTER" --format opencode --watch "$WATCH" --final "$FINAL" \
  --diagnostic "$DIAGNOSTIC" -- \
  opencode run --format json --thinking --agent plan --dir "$CWD" "$(cat "$SPEC")"
```

For write work use `--agent build --auto`. If the user names an OpenCode model, add `--model PROVIDER/MODEL` and report that exact value in `--model-label`.

### Luna

```bash
"$RUNTIME" start \
  --lane luna --cwd "$CWD" --spec "$SPEC" \
  --state-dir "$STATE_DIR" --result-source "$FINAL" --ephemeral-watch \
  --title "$TITLE" --model-label "gpt-5.6-luna / max / fast" --mode read -- \
  node "$ADAPTER" --format codex --watch "$WATCH" --final "$FINAL" \
  --diagnostic "$DIAGNOSTIC" --stdin-file "$SPEC" -- \
  codex exec --json --output-last-message "$FINAL" \
  --model gpt-5.6-luna -c 'model_reasoning_effort="max"' \
  -c 'service_tier="priority"' --sandbox read-only --cd "$CWD" -
```

For write work replace `--sandbox read-only` with `--dangerously-bypass-approvals-and-sandbox`. Luna always means `gpt-5.6-luna`, `max`, and priority service (Fast). Do not restrict its tools for output-size control.

## Output Files

The adapter separates three audiences. Inside a Herdr pane it also mirrors the same bounded live lines to the PTY, so the native Herdr TUI is useful without changing what reaches the main Agent:

- `lane.log`: live user-facing output, capped at 2 MiB. It contains lifecycle, tool summaries, errors, response availability, and thinking text explicitly emitted by the CLI. It never claims access to hidden reasoning.
- `final.txt`: exact best final response from the event stream. The selected runtime copies at most 16 KiB into `result.txt`, which is the only agent output returned by `await` to the main session.
- `final.txt.status`: producer exit code, adapter exit code, and whether a usable final response was observed. Producer exit code `0` with `final_available=false` becomes `failed/missing_final`, not a successful review.
- `diagnostic.log.tmp`: capped raw event stream while running. It is deleted after success, moved to `diagnostic.log` after failure or interruption, and old diagnostics are removed after seven days.

With `--ephemeral-watch`, `lane.log`, `final.txt`, and its status file are deleted after success or cancellation. The terminal dashboard can display live output while the lane is active. A failed or interrupted lane retains the bounded live log, final source, status file, and diagnostic needed for investigation.

For OpenCode, a `text` event is live output until its message reaches a non-tool-calls `step_finish`. Intermediate narration before another tool call must never become the final review.

This protocol applies to Grok, Claude, Gemini/Antigravity, OpenCode, and Luna/Codex CLI. Codex runtime worker and explorer transcripts remain owned by the Codex runtime rather than these files.

## Direct Launch And Await

Run `start` and `await` in one shell invocation:

```bash
launch_receipt=$("$RUNTIME" start START_ARGUMENTS -- COMMAND ARGUMENTS) || exit $?
"$RUNTIME" await --state-dir "$STATE_DIR"
```

Keep the successful launch receipt inside the shell. Do not poll state, read logs, inspect diffs, or narrate routine progress while the lane runs. If the command tool yields a live shell session, continue only that session at the longest supported wait. The user can watch `lane.log` through `codex-orchestrator agents` without consuming Codex tokens.

For multiple lanes, start all lanes before the first `await`, then await all of them in the same blocking shell invocation.

The stable task key combines lane, working directory, and spec content. Starting the same live task again returns `ALREADY_RUNNING` rather than creating a duplicate process.

## Terminal Dashboard

```bash
codex-orchestrator
codex-orchestrator agents
codex-orchestrator list --all
codex-orchestrator watch <task-id>
```

`codex-orchestrator agents` discovers new lanes automatically, lays panes out horizontally before adding rows, and removes a pane when its lane finishes. The TUI reads local files only and does not change the main session's silent wait.

Use `status` only when the user explicitly requests status. Stop a lane only on explicit user action:

```bash
"$RUNTIME" status --state-dir "$STATE_DIR"
"$RUNTIME" stop --state-dir "$STATE_DIR"
"$RUNTIME" result --state-dir "$STATE_DIR"
```

## Optional Broker

Use a Broker only when the user explicitly asks for a visible launcher card. One Terra Low Broker starts one supplied runtime-selector command and exits immediately after `STARTED`, `ALREADY_RUNNING`, or a short launch error. It must not inspect the spec, wait, read lane files, or judge the result.

## Scoped Verification

Every spec must name the narrowest relevant test and format commands. External producers must not run all tests or a repository-wide format check without explicit user permission. If no path-, module-, package-, test-file-, or test-case-level command exists, return that limitation and wait for permission before a broader run.
