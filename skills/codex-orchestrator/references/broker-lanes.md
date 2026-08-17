# External CLI Lanes

Launch external CLI lanes through the bundled non-model supervisor. The main session writes one bounded spec, starts the lane, blocks once in `await`, and verifies the final diff. The supervisor and output adapter use no model tokens.

## Shared Setup

```bash
SUPERVISOR="$SKILL_DIR/scripts/lane-supervisor.sh"
ADAPTER="$SKILL_DIR/scripts/agent-output.mjs"
TASK_KEY=$("$SUPERVISOR" key --lane "$LANE" --cwd "$CWD" --spec "$SPEC")
STATE_DIR="${TMPDIR:-/tmp}/codex-orchestrator/$TASK_KEY"
WATCH="$STATE_DIR/lane.log"
FINAL="$STATE_DIR/final.txt"
DIAGNOSTIC="$STATE_DIR/diagnostic.log"
```

Validate every spec first:

```bash
"$SUPERVISOR" check-spec --spec "$SPEC"
```

The spec should normally be 4-8 KiB and cannot exceed 16 KiB. Pass workspace paths and search anchors instead of conversation history, logs, diffs, or large source blocks.

Every start command must include these supervisor arguments:

```bash
--lane "$LANE" --cwd "$CWD" --spec "$SPEC" --state-dir "$STATE_DIR" \
--result-source "$FINAL" --ephemeral-watch \
--title "$TITLE" --model-label "$MODEL_LABEL" --mode "$MODE"
```

`MODE` is `read` or `write`. The examples below are read-only unless stated otherwise.

## Lane Commands

### Grok

```bash
"$SUPERVISOR" start \
  --lane grok --cwd "$CWD" --spec "$SPEC" --state-dir "$STATE_DIR" \
  --result-source "$FINAL" --ephemeral-watch \
  --title "$TITLE" --model-label "grok default" --mode read -- \
  env GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false \
  node "$ADAPTER" --format grok --watch "$WATCH" --final "$FINAL" \
  --diagnostic "$DIAGNOSTIC" -- \
  grok --no-subagents --prompt-file "$SPEC" \
  --output-format streaming-messages-json --include-partial-messages --cwd "$CWD"
```

For write work add `--permission-mode bypassPermissions`. If the user names a model, add `-m MODEL`. Keep `--no-subagents` unless the user explicitly asks Grok to coordinate its own subagents. Do not combine `--check` with `--no-subagents`.

### Claude

```bash
"$SUPERVISOR" start \
  --lane claude --cwd "$CWD" --spec "$SPEC" --stdin "$SPEC" \
  --state-dir "$STATE_DIR" --result-source "$FINAL" --ephemeral-watch \
  --title "$TITLE" --model-label "sonnet / high" --mode read -- \
  node "$ADAPTER" --format claude --watch "$WATCH" --final "$FINAL" \
  --diagnostic "$DIAGNOSTIC" --forward-stdin -- \
  claude -p --model sonnet --effort high --verbose \
  --output-format stream-json --include-partial-messages
```

For write work add `--permission-mode bypassPermissions`.

### Gemini Through Antigravity

```bash
"$SUPERVISOR" start \
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
"$SUPERVISOR" start \
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
"$SUPERVISOR" start \
  --lane luna --cwd "$CWD" --spec "$SPEC" --stdin "$SPEC" \
  --state-dir "$STATE_DIR" --result-source "$FINAL" --ephemeral-watch \
  --title "$TITLE" --model-label "gpt-5.6-luna / max / fast" --mode read -- \
  node "$ADAPTER" --format codex --watch "$WATCH" --final "$FINAL" \
  --diagnostic "$DIAGNOSTIC" --forward-stdin -- \
  codex exec --json --output-last-message "$FINAL" \
  --model gpt-5.6-luna -c 'model_reasoning_effort="max"' \
  -c 'service_tier="priority"' --sandbox read-only --cd "$CWD" -
```

For write work replace `--sandbox read-only` with `--dangerously-bypass-approvals-and-sandbox`. Luna always means `gpt-5.6-luna`, `max`, and priority service (Fast). Do not restrict its tools for output-size control.

## Output Files

The adapter separates three audiences:

- `lane.log`: live user-facing output, capped at 2 MiB. It contains lifecycle, tool summaries, errors, response availability, and thinking text explicitly emitted by the CLI. It never claims access to hidden reasoning.
- `final.txt`: exact best final response from the event stream. The supervisor copies at most 16 KiB into `result.txt`, which is the only agent output returned by `await` to the main session.
- `diagnostic.log.tmp`: capped raw event stream while running. It is deleted after success, moved to `diagnostic.log` after failure or interruption, and old diagnostics are removed after seven days.

With `--ephemeral-watch`, `lane.log` and `final.txt` are deleted after terminal state. The terminal dashboard can display them while the lane is active. A failed or interrupted lane retains only the bounded diagnostic needed for investigation.

This protocol applies to Grok, Claude, Gemini/Antigravity, OpenCode, and Luna/Codex CLI. Codex runtime worker and explorer transcripts remain owned by the Codex runtime rather than these files.

## Direct Launch And Await

Run `start` and `await` in one shell invocation:

```bash
launch_receipt=$("$SUPERVISOR" start START_ARGUMENTS -- COMMAND ARGUMENTS) || exit $?
"$SUPERVISOR" await --state-dir "$STATE_DIR"
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
"$SUPERVISOR" status --state-dir "$STATE_DIR"
"$SUPERVISOR" stop --state-dir "$STATE_DIR"
"$SUPERVISOR" result --state-dir "$STATE_DIR"
```

## Optional Broker

Use a Broker only when the user explicitly asks for a visible launcher card. One Terra Low Broker starts one supplied supervisor command and exits immediately after `STARTED`, `ALREADY_RUNNING`, or a short launch error. It must not inspect the spec, wait, read lane files, or judge the result.

## Scoped Verification

Every spec must name the narrowest relevant test and format commands. External producers must not run all tests or a repository-wide format check without explicit user permission. If no path-, module-, package-, test-file-, or test-case-level command exists, return that limitation and wait for permission before a broader run.
