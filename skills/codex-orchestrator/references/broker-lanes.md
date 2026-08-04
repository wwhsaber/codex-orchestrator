# Broker Lanes

Use one lightweight Codex broker sub-agent for each external CLI lane. The broker runs one process, saves its output, and returns only terminal evidence.

## Runtime Profile

The broker and the external producer are separate layers:

```text
Broker: gpt-5.6-luna, low reasoning, default service, fork_turns=none
Luna producer: gpt-5.6-luna, max reasoning, priority service (Fast)
```

Do not let a broker inherit the parent's model, reasoning effort, service tier, or conversation history.

## Broker Input

Pass only:

- Lane name.
- Working directory.
- Spec path.
- Log path.
- Exact CLI command.
- Read-only or write-producing mode.

Do not copy parent history or the spec body into the broker prompt.

## Broker Contract

Use this contract:

```text
You are a lightweight process broker for exactly one external CLI lane.
Start the supplied command once in the supplied working directory.
Save full stdout and stderr to the supplied log path.
Do not analyze the task, rewrite the spec, inspect the diff, or narrate progress.
Do not read routine logs while the command runs.
If the shell tool yields, wait on the same session using its longest supported timeout.
Quiet output and a parent wait timeout are not failures.
Never start a duplicate process.
When the command exits, return its exit status, log path, and at most the final 16 KiB of output.
```

## CLI Commands

Grok:

```bash
env GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false \
  grok --no-subagents --prompt-file "$SPEC" --output-format plain --cwd "$CWD"
```

Claude:

```bash
claude -p --model sonnet --effort high < "$SPEC"
```

Antigravity:

```bash
agy --print "$(cat "$SPEC")" --mode plan --dangerously-skip-permissions \
  --print-timeout 15m --model gemini-3.6-flash-high
```

Luna:

```bash
codex exec --model gpt-5.6-luna -c 'model_reasoning_effort="max"' \
  -c 'service_tier="priority"' \
  --sandbox read-only --cd "$CWD" - < "$SPEC"
```

For write-producing Luna work, replace `--sandbox read-only` with `--dangerously-bypass-approvals-and-sandbox`.

Add each CLI's broad edit approval flags for write-producing work. Gemini requests always use Antigravity `agy`; do not select an Antigravity Claude model.

## Parent Wait

After spawning all requested brokers:

1. Call `agents.wait` once for all active broker IDs with `timeout_ms=900000`.
2. If the wait returns terminal results, review each bounded report.
3. If it times out, keep the same agent IDs and call one more 15-minute wait.
4. Do not read transcripts, logs, diffs, or session files between waits.
5. Do not send status prompts or create replacement brokers.
6. A wait timeout never cancels the broker or its CLI process.

After a broker exits, inspect the working-tree diff and run verification in the main session.
