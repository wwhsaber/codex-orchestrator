# Codex Orchestrator

Architect-style orchestration plugin for Codex.

Use it for multi-agent orchestration on high-stakes work: architect-led decomposition, delegated implementation, worker comparison, optional external model CLIs, and evidence-backed verification. Prefer explicit `$codex-orchestrator` for that path.

## Dependencies

None. The skill works with Codex runtime sub-agents (`worker`, `explorer`) alone.

External CLIs (`grok`, `claude`, `agy`, `codex`) are optional. Use them only when you want a distinct model producer or explicitly ask for that lane.

If you request an external lane that is not installed or authenticated, the skill should stop and ask whether to install/configure that CLI or continue with Codex `worker` / `explorer` sub-agents.

## Structure

```text
codex-orchestrator/
├── .codex-plugin/plugin.json
├── skills/
│   └── codex-orchestrator/
│       ├── SKILL.md
│       └── agents/openai.yaml
├── README.md
└── LICENSE
```

This is a Codex plugin repository: the root manifest advertises the package, and the skill lives under `skills/`.

`skills/codex-orchestrator/agents/openai.yaml` is Codex skill UI metadata. It is not a runnable Claude-style agent definition.

## Install As A Skill

The simplest install path is to copy the nested skill into your Codex skills directory:

```bash
git clone <your-repo-url> /tmp/codex-orchestrator
mkdir -p ~/.codex/skills
rm -rf ~/.codex/skills/codex-orchestrator
cp -R /tmp/codex-orchestrator/skills/codex-orchestrator ~/.codex/skills/codex-orchestrator
```

Restart Codex, then invoke:

```text
Use $codex-orchestrator to plan, delegate, and verify this coding task.
```

### When to use

- High-stakes or multi-agent work: orchestrate, delegate to sub-agents, run parallel workers, compare implementations, or use an external CLI lane.
- Recommended: `Use $codex-orchestrator ...` so the skill is selected intentionally.
- In orchestrator mode, delegated agents use the skill priority: Grok first, Claude second, Antigravity third. Say "Codex worker/explorer" when you specifically want Codex runtime sub-agents. Say "Gemini" to route through Antigravity `agy`.
- Skip for ordinary single-session tasks: fix, implement, refactor, review, or plan alone.

## Install As A Plugin

Clone the plugin to the default local plugin location:

```bash
mkdir -p ~/plugins
git clone <your-repo-url> ~/plugins/codex-orchestrator
```

Then add a local marketplace entry at `~/.agents/plugins/marketplace.json`:

```json
{
  "name": "personal",
  "interface": {
    "displayName": "Personal"
  },
  "plugins": [
    {
      "name": "codex-orchestrator",
      "source": {
        "source": "local",
        "path": "./plugins/codex-orchestrator"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
      },
      "category": "Productivity"
    }
  ]
}
```

Restart Codex after installing or updating the plugin.

## What It Does

- Keeps the main Codex session as architect.
- Uses five-part specs for delegated work: objective, files, interfaces, constraints, verification.
- Supports worker and explorer sub-agents.
- Supports optional external CLI lanes such as `grok`, `claude`, `agy`, `luna`, and `codex` when those tools are installed and authenticated.
- Uses a lightweight one-to-one broker sub-agent only to launch each external CLI lane.
- Moves process waiting and logging to a non-model supervisor so idle lanes consume no Broker tokens.
- Requires final verification from the main session before calling work done.

## External CLI Mode

The main Codex session writes the spec and creates one broker launcher sub-agent per external CLI lane:

```text
Grok broker launcher -> shell supervisor -> grok
Claude broker launcher -> shell supervisor -> claude
Antigravity broker launcher -> shell supervisor -> agy / Gemini
Luna broker launcher -> shell supervisor -> codex / GPT-5.6 Luna Max / Fast
```

The Broker runs one supervisor start command, reports `STARTED`, and exits immediately. The shell supervisor waits for the external process, writes a small state snapshot and completion marker, and stores at most the final 16 KiB in `result.txt`. It uses no model and consumes no Codex tokens. The main Codex session still writes the spec, judges completed results, and runs verification.

Broker and producer settings are intentionally separate:

```text
Broker launcher: GPT-5.6 Terra Low, default service, no parent context
Lane supervisor: shell process, no model
Luna producer: GPT-5.6 Luna Max, Fast service
```

The main session waits once only for Broker launch receipts. It does not wait for external CLI completion, poll status, read logs, or keep the Broker alive. The completed Broker card means “background lane launched,” not “external work completed.”

## Model Selection

If you specify a model, the skill passes the model flag to that CLI. The following examples are external commands passed by the broker launcher to the supervisor.

```bash
# User specified a model
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok -m grok-4.5 --no-subagents --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high --permission-mode bypassPermissions < "$SPEC"
agy --print "$(cat "$SPEC")" --mode accept-edits --dangerously-skip-permissions --model gemini-3.6-flash-high
codex exec --model gpt-5.5 --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"

# User did not specify a model; use each lane default
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --no-subagents --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high --permission-mode bypassPermissions < "$SPEC"
agy --print "$(cat "$SPEC")" --mode accept-edits --dangerously-skip-permissions --model gemini-3.6-flash-high
codex exec --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"
```

For write-producing implementation lanes, use broad edit and tool approval modes to avoid permission stalls. Keep read-only reviews and advisor passes on read-only or default modes. Use Grok `--no-subagents` by default so Grok remains one external producer under one broker lane. Do not combine Grok `--check` with `--no-subagents`.

For Antigravity `agy`, put the prompt immediately after `--print` or `-p`, then pass `--mode`, `--model`, and permission flags. Headless read-only reviews should use `--mode plan --dangerously-skip-permissions --print-timeout 15m`: plan mode keeps review posture, while automatic approval permits file reads and inspection commands when no permission prompt can be shown. Confirm afterward that Gemini did not change the working-directory diff. Before retrying, confirm the same Antigravity process or session is not still active. If Gemini reports an auto-denied tool permission, or explains `--mode`, `--print-timeout`, or CLI usage instead of the task, the lane was invoked incorrectly and should be rerun once with the corrected prompt-first command form.

```bash
agy --print "$(cat "$SPEC")" --mode plan --dangerously-skip-permissions --print-timeout 15m --model gemini-3.6-flash-high
```

If you do not specify a model, the CLI default is used, except Claude and Antigravity: the Claude lane uses `--model sonnet --effort high` unless you ask for another Claude model or effort such as `max`, and the `agy` lane default is `gemini-3.6-flash-high`.

Gemini requests always use Antigravity `agy`. Do not use an Antigravity Claude model; Claude requests use the Claude CLI lane.

`luna` always means an independent Codex CLI lane using `gpt-5.6-luna` with reasoning effort `max` and Fast service. Fast maps to the `priority` service tier:

```bash
codex exec --model gpt-5.6-luna -c 'model_reasoning_effort="max"' -c 'service_tier="priority"' --sandbox read-only --cd "$(pwd)" - < "$SPEC"
```

For write-producing Luna work, use `--dangerously-bypass-approvals-and-sandbox` instead of `--sandbox read-only`.

Luna keeps its full model behavior: GPT-5.6 Luna, `max` reasoning, Fast service, requested permissions, and unrestricted tool calls. Only output capture changes. Codex runs with JSON events and `--output-last-message`; `lane.log` records command lifecycle, errors, agent messages, and usage without successful command output. The full JSONL event stream is available while running and compressed after completion. Claude output behavior is unchanged.

## Broker Launcher Configuration

Every external lane gets a short-lived Terra Low broker launcher. Configure `multi_agent_v2` so broker cards remain visible and launch waiting can use one native tool call:

```toml
[agents]
default_subagent_model = "gpt-5.6-terra"
default_subagent_reasoning_effort = "low"

[features.multi_agent_v2]
enabled = true
hide_spawn_agent_metadata = false
tool_namespace = "agents"
max_concurrent_threads_per_session = 7
min_wait_timeout_ms = 10000
default_wait_timeout_ms = 30000
max_wait_timeout_ms = 900000
```

The 30-second value remains the general default. Codex Orchestrator may call `agents.wait(timeout_ms=900000)` once for launcher receipts, then lets each Broker finish. External execution continues under `skills/codex-orchestrator/scripts/lane-supervisor.sh`. See `skills/codex-orchestrator/references/broker-lanes.md` for the launcher contract and commands.

For Grok:

```bash
grok models
```

For Claude Code:

```bash
claude --help
```

For Antigravity:

```bash
agy models
```

For external lanes, use the supervisor's `lane.log`. The user may watch that file outside the main model context. Codex should not read or summarize routine output; after completion it reads the bounded `result.txt` once. Luna's compact log is paired with `luna-events.jsonl` while running and `luna-events.jsonl.gz` after exit for complete diagnosis.

For Grok lanes, disable inherited Cursor and Claude MCP discovery by setting `GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false`. Use `--no-subagents` unless the user explicitly asks Grok to coordinate its own subagents. Do not mark Grok unavailable from MCP startup warnings alone if the lane prints task progress or a final response.

Claude Code `-p` text output can stay quiet until final output. Quiet output is not a failure signal.

## License

MIT
