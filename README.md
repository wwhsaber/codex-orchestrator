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
- In orchestrator mode, delegated agents use the skill priority: Grok first, Claude second, Antigravity third. Say "Codex worker/explorer" when you specifically want Codex runtime sub-agents.
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
- Requires final verification from the main session before calling work done.

## Model Selection

If you specify a model, the skill should pass the model flag to that CLI.

```bash
# User specified a model
grok -m grok-4.5 --permission-mode acceptEdits --tools read_file,grep,todo_write,search_replace --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet < "$SPEC"
agy --print --model "Gemini 3.5 Flash (High)" < "$SPEC"
codex exec --model gpt-5.5 --cd "$(pwd)" - < "$SPEC"

# User did not specify a model; use each lane default
grok --permission-mode acceptEdits --tools read_file,grep,todo_write,search_replace --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p < "$SPEC"
agy --print --model "Gemini 3.5 Flash (High)" < "$SPEC"
codex exec --cd "$(pwd)" - < "$SPEC"
```

For Grok implementation lanes, use the tool whitelist shown above instead of broad shell access. Do not combine `--check` with `--no-subagents`.

If you do not specify a model, the CLI default is used, except Antigravity: the `agy` lane default is `Gemini 3.5 Flash (High)`.

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

## License

MIT
