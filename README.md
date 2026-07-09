# Codex Orchestrator

Architect-style orchestration plugin for Codex.

Use it when you want Codex to plan, delegate implementation, compare worker output, call external model CLIs, and verify evidence before reporting completion.

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

This mirrors the plugin shape used by Claude Code plugins: a root plugin manifest plus one or more skills under `skills/`.

## Install As A Skill

The simplest install path is to copy the nested skill into your Codex skills directory:

```bash
git clone <your-repo-url> /tmp/codex-orchestrator
cp -R /tmp/codex-orchestrator/skills/codex-orchestrator ~/.codex/skills/codex-orchestrator
```

Restart Codex, then invoke:

```text
Use $codex-orchestrator to plan, delegate, and verify this coding task.
```

## Install As A Plugin

This repo also includes `.codex-plugin/plugin.json` for Codex plugin distribution. Install it through your normal Codex plugin marketplace or local plugin flow.

## What It Does

- Keeps the main Codex session as architect.
- Uses five-part specs for delegated work: objective, files, interfaces, constraints, verification.
- Supports worker and explorer sub-agents.
- Supports optional external CLI lanes such as `grok`, `claude`, and `codex`.
- Requires final verification from the main session before calling work done.

## Model Selection

If you specify a model, the skill should pass the model flag to that CLI.

```bash
grok -m grok-4.5 --prompt-file "$SPEC" --output-format plain --cwd "$(pwd)"
claude -p --model sonnet < "$SPEC"
codex exec --model gpt-5.5 --cd "$(pwd)" - < "$SPEC"
```

If you do not specify a model, the CLI default is used.

For Grok:

```bash
grok models
```

For Claude Code:

```bash
claude --help
```

## License

MIT
