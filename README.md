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
- Supports optional external CLI lanes such as `grok`, `claude`, `agy`, and `codex` when those tools are installed and authenticated.
- Uses one lightweight broker per external CLI lane when available, so long-running Grok/Claude/agy work is managed through structured lifecycle status instead of main-session log watching.
- Requires final verification from the main session before calling work done.

## Broker Mode

External CLI lanes can run through one broker per lane:

```text
Grok broker -> grok
Claude broker -> claude
Antigravity broker -> agy / Gemini
```

The broker only starts the command, streams logs with `tee`, tracks pid/log/exit status, and reports `STARTED`, `RUNNING`, `NEEDS_ATTENTION`, `EXITED`, or `FAILED_TO_START`. It should not review code, summarize routine logs, or decide whether the final diff is correct. The main Codex session still writes the spec, judges results, and runs verification.

## Model Selection

If you specify a model, the skill should pass the model flag to that CLI.

```bash
# User specified a model
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok -m grok-4.5 --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet --effort high --permission-mode bypassPermissions < "$SPEC"
agy --print --mode accept-edits --dangerously-skip-permissions --model "Gemini 3.5 Flash (High)" < "$SPEC"
codex exec --model gpt-5.5 --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"

# User did not specify a model; use each lane default
GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false grok --permission-mode bypassPermissions --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --effort high --permission-mode bypassPermissions < "$SPEC"
agy --print --mode accept-edits --dangerously-skip-permissions --model "Gemini 3.5 Flash (High)" < "$SPEC"
codex exec --dangerously-bypass-approvals-and-sandbox --cd "$(pwd)" - < "$SPEC"
```

For write-producing implementation lanes, use broad edit and tool approval modes to avoid permission stalls. Keep read-only reviews and advisor passes on read-only or default modes. Do not combine Grok `--check` with `--no-subagents`.

If you do not specify a model, the CLI default is used, except Claude and Antigravity: the Claude lane uses `--effort high` unless you ask for another Claude effort such as `max`, and the `agy` lane default is `Gemini 3.5 Flash (High)`.

Gemini requests always use Antigravity `agy`. Do not use an Antigravity Claude model; Claude requests use the Claude CLI lane.

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

For external lanes, prefer visible logs: stream output where the user can watch it while saving the same output with `tee`. Codex should not summarize routine log output; inspect the saved log only when the lane exits, fails, appears stuck, or the user asks for status.

For Grok lanes, disable inherited Cursor and Claude MCP discovery by setting `GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false`. Do not mark Grok unavailable from MCP startup warnings alone if the lane prints task progress or a final response.

Claude Code `-p` text output can stay quiet until final output. If a Claude lane appears stuck, inspect it with filtered stream JSON instead of raw stream output:

```bash
claude -p --effort high --verbose --output-format stream-json --permission-mode bypassPermissions < "$SPEC" 2>&1 \
  | tee "$LOG" \
  | jq -r 'if .type=="system" then "[system] " + (.subtype // .status // "event") elif .type=="result" then "[result] done" elif .type=="assistant" then (.message.content[]? | select(.type=="text") | .text) else empty end'
```

## License

MIT
