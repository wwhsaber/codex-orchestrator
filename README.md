# Codex Orchestrator

Architect-style orchestration plugin for Codex.

Use it for multi-agent orchestration on high-stakes work: architect-led decomposition, delegated implementation, worker comparison, optional external model CLIs, and evidence-backed verification. Prefer explicit `$codex-orchestrator` for that path.

## Dependencies

The skill works with Codex runtime sub-agents (`worker`, `explorer`) alone. External lane output separation requires Node.js 18 or newer for the bundled event adapter. Herdr is an optional PTY runtime. On macOS, install it with `brew install herdr`, then start its server with `herdr server` or `brew services start herdr`.

The Herdr server must have macOS permission for every workspace directory. If a Homebrew service can create panes but commands hang when entering `Documents`, stop that service and start `herdr server` from a Terminal or desktop App shell that already has access, or grant the service the required Files and Folders permission.

The optional terminal dashboard is a Rust binary. Build it with a current Rust toolchain or install a prebuilt release when one is available.

External CLIs (`grok`, `claude`, `agy`, `opencode`, `codex`) are optional. Use them only when you want a distinct model producer or explicitly ask for that lane.

If you request an external lane that is not installed or authenticated, the skill should stop and ask whether to install/configure that CLI or continue with Codex `worker` / `explorer` sub-agents.

## Structure

```text
codex-orchestrator/
├── .codex-plugin/plugin.json
├── Cargo.toml
├── src/
│   ├── app.rs
│   ├── main.rs
│   ├── model.rs
│   └── ui.rs
├── skills/
│   └── codex-orchestrator/
│       ├── SKILL.md
│       ├── agents/openai.yaml
│       ├── references/broker-lanes.md
│       └── scripts/
│           ├── agent-output.mjs
│           ├── codex-event-log.sh
│           ├── herdr-lane.mjs
│           ├── lane-runtime.sh
│           └── lane-supervisor.sh
├── tests/
│   └── agent-output.test.mjs
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

## Install The Terminal Dashboard

From the cloned repository:

```bash
cargo install --path . --locked
```

Open the dashboard from any terminal:

```bash
codex-orchestrator
codex-orchestrator agents
```

The dashboard reads local runtime state and logs directly. It does not call a model and does not add content to the main Codex session.

`codex-orchestrator agents` opens a live multi-pane view containing only running Agents. New Agents join automatically, and each pane disappears when its Agent reaches a terminal state. Panes are arranged horizontally first and continue on additional rows when the terminal cannot keep every pane readable on one row. The command remains open while no Agents are running so it can pick up future work; press `q` or `Esc` to exit.

Live activity is rendered by meaning rather than as raw log prefixes: consecutive thinking updates form one muted block, tool calls use a compact command row, and responses, failures, and completion have distinct status styling. Herdr panes receive the same semantic presentation through ANSI output while the saved log remains plain text.

If a saved task says `running` but its recorded supervisor process no longer exists or belongs to another process, the dashboard presents it as `INTERRUPTED` and excludes it from the Running filter. The supervisor also writes this terminal state when `status` or `await` observes a missing process, so crashes, forced exits, and machine restarts do not leave a task permanently active.

```text
Up/Down        select a task or scroll output
Enter / l      open the live log
r              open the final result
f / Tab        cycle all, running, and finished filters
Space          pause or resume log following
s              stop a running task after confirmation
Esc            return to the dashboard
q              quit
```

For multiple terminal windows, use the task ID shown by `list`:

```bash
codex-orchestrator agents
codex-orchestrator list --all
codex-orchestrator watch <task-id>
codex-orchestrator result <task-id>
codex-orchestrator stop <task-id> --yes
```

Each `watch` process is an independent read-only observer until you explicitly confirm `stop`. Override task discovery with `--state-root PATH` or `CODEX_ORCHESTRATOR_STATE_ROOT`.

## What It Does

- Keeps the main Codex session as architect.
- Uses five-part specs for delegated work: objective, files, interfaces, constraints, verification.
- Supports worker and explorer sub-agents.
- Supports optional external CLI lanes such as `grok`, `claude`, `agy`, `opencode`, `luna`, and `codex` when those tools are installed and authenticated.
- Starts each external CLI lane through a non-model runtime selector.
- Uses Herdr for persistent PTYs, workspaces, native windows, and event waits when its server is ready.
- Keeps the shell supervisor available when Herdr is not in use.
- Keeps Broker sub-agents optional for users who explicitly want visible launcher cards.
- Moves process waiting and logging to the supervisor so idle lanes consume no Codex tokens.
- Provides a Rust terminal dashboard for all Lane states, auto-updating multi-Agent logs, results, and explicit stopping.
- Caps every delegated spec at 16 KiB and prevents Codex sub-agents from inheriting the parent conversation.
- Limits tests and format checks to the changed scope unless the user explicitly approves a broader run.
- Requires final verification from the main session before calling work done.

## Scoped Test And Format Checks

The orchestrator defaults to the narrowest useful verification for the current change: an exact test, test file, affected module or package, and changed source paths for formatting. Main-session checks, Codex sub-agents, and external CLI lanes may not run all tests or a full-repository format check unless the user explicitly approves that broader command. When project tooling has no scoped command, the orchestrator asks before proceeding.

This execution rule does not silently rewrite existing repository CI policy. CI workflow scope changes remain an explicit project decision.

Run the focused output-contract tests with:

```bash
node --test tests/agent-output.test.mjs
```

## External CLI Mode

The main Codex session writes the spec and starts each external CLI lane directly:

```text
Main Agent -> Orchestrator route/spec/result -> Herdr Runtime -> grok
Main Agent -> Orchestrator route/spec/result -> Herdr Runtime -> claude
Main Agent -> Orchestrator route/spec/result -> Herdr Runtime -> agy / Gemini
Main Agent -> Orchestrator route/spec/result -> Herdr Runtime -> opencode
Main Agent -> Orchestrator route/spec/result -> Herdr Runtime -> codex / GPT-5.6 Luna Max / Fast
```

`skills/codex-orchestrator/scripts/lane-runtime.sh` selects the backend. Its default `auto` mode uses Herdr only when the CLI and server are ready. Set `CODEX_ORCHESTRATOR_RUNTIME=herdr` to require Herdr or `CODEX_ORCHESTRATOR_RUNTIME=supervisor` to use the original shell runtime. An explicit Herdr request fails clearly rather than installing or starting software without permission.

Normal launches leave `CODEX_ORCHESTRATOR_RUNTIME` unset, which keeps Herdr first. Explicit `supervisor` mode is reserved for a user request or a confirmed Herdr launch failure. When Herdr is ready, the selector also requires `CODEX_ORCHESTRATOR_SUPERVISOR_REASON=user_requested` or `herdr_launch_failed`, which prevents stale sessions from silently overriding `auto`. State directories are computed by `lane-runtime.sh state-dir`; the command uses `CODEX_ORCHESTRATOR_STATE_ROOT` or the platform temporary directory and prevents a lane from disappearing into a separately hardcoded `/tmp` tree.

The main session uses one shell invocation to run runtime `start` and continue directly into `await`. A successful `STARTED` or `ALREADY_RUNNING` receipt stays inside the shell, so it does not create another model step. With Herdr, the external Agent runs in a real Herdr PTY and a no-model watcher blocks on one anchored completion event. The runtime stores at most the final 16 KiB in `result.txt`; the event adapter writes a separate live view and final response. These runtime processes use no model tokens. The main Codex session still judges completed results and runs verification.

Runtime and producer settings are intentionally separate:

```text
Lane runtime: Herdr or shell process, no model
Luna producer: GPT-5.6 Luna Max, Fast service
```

The runtime waits for `done` without model output and returns terminal state plus the bounded result once. A producer exit code of `0` counts as success only when the adapter also observed a usable final response. The main Agent then continues review and verification automatically. It never wakes for a successful launch receipt, polls status, or reads routine logs.

Grok lanes create a new conversation by default. An explicit continuation request can use `--continue` for the latest conversation in the working directory or `lane-runtime.sh producer-session --task-id ID` plus `grok --resume SESSION_ID` for an exact prior Orchestrator task. Successful lane cleanup keeps this small session field in task state while removing transient logs.

In another terminal, `codex-orchestrator` can display every Lane and follow its output. This user-side observer reads local files only and does not alter the main Agent's silent wait.

A Terra Low Broker is available only as an explicit UI mode. When requested, it runs the same `start` command once and exits after the receipt so a launcher card appears in Codex. It is not required for external execution and is not used by default.

## Delegated Context Budget

Delegated specs should normally be 4-8 KiB and cannot exceed 16 KiB. The runtime rejects oversized specs in `check-spec`, `key`, and `start`. Specs contain the objective, exact workspace paths, interfaces, constraints, and verification command; they do not contain full conversation history, logs, diffs, or large source blocks.

Codex worker and explorer sub-agents always use `fork_turns="none"` with only the validated spec. External CLI lanes also receive only that spec and inspect referenced workspace files as needed.

## Model Selection

If you specify a model, the skill passes the model flag to that CLI. The exact read-only and write-producing event-stream commands are in `skills/codex-orchestrator/references/broker-lanes.md`.

For write-producing implementation lanes, use broad edit and tool approval modes to avoid permission stalls. Keep read-only reviews and advisor passes on read-only or default modes. Use Grok `--no-subagents` by default so Grok remains one external producer under one runtime lane. Do not combine Grok `--check` with `--no-subagents`.

For Antigravity `agy`, put the prompt immediately after `--print` or `-p`, then pass `--mode`, `--model`, and permission flags. Headless read-only reviews should use `--mode plan --dangerously-skip-permissions --print-timeout 15m`: plan mode keeps review posture, while automatic approval permits file reads and inspection commands when no permission prompt can be shown. Confirm afterward that Gemini did not change the working-directory diff. Before retrying, confirm the same Antigravity process or session is not still active. If Gemini reports an auto-denied tool permission, or explains `--mode`, `--print-timeout`, or CLI usage instead of the task, the lane was invoked incorrectly and should be rerun once with the corrected prompt-first command form.

If you do not specify a model, the CLI default is used, except Claude and Antigravity: the Claude lane uses `--model sonnet --effort high` unless you ask for another Claude model or effort such as `max`, and the `agy` lane default is `gemini-3.6-flash-high`. OpenCode uses its current configured model unless you name one.

Gemini requests always use Antigravity `agy`. Do not use an Antigravity Claude model; Claude requests use the Claude CLI lane.

`luna` always means an independent Codex CLI lane using `gpt-5.6-luna` with reasoning effort `max` and Fast service. Fast maps to the `priority` service tier:

```bash
codex exec --model gpt-5.6-luna -c 'model_reasoning_effort="max"' -c 'service_tier="priority"' --sandbox read-only --cd "$(pwd)" - < "$SPEC"
```

For write-producing Luna work, use `--dangerously-bypass-approvals-and-sandbox` instead of `--sandbox read-only`.

Luna keeps its full model behavior: GPT-5.6 Luna, `max` reasoning, Fast service, requested permissions, and unrestricted tool calls. Only output capture changes.

## Optional Broker Configuration

No sub-agent configuration is required for the default direct-launch path. To request visible Broker launcher cards, configure `multi_agent_v2` as follows:

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

The 30-second value remains the general default. In optional Broker mode, Codex Orchestrator may call `agents.wait(timeout_ms=900000)` once for launcher receipts. External execution continues under `skills/codex-orchestrator/scripts/lane-runtime.sh`. See `skills/codex-orchestrator/references/broker-lanes.md` for direct launch commands and the optional Broker contract.

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

For external lanes, use the runtime's `lane.log`. The user may watch that file outside the main model context. It shows lifecycle, concise tool activity, errors, and thinking text explicitly emitted by the CLI. Codex does not read or summarize routine output; after completion it receives the bounded `result.txt` once.

The output adapter caps `lane.log` at 2 MiB and keeps the exact final response in a separate temporary file. It also records the producer exit code and final availability in a small status file. After success or cancellation, temporary output is deleted. A failed or interrupted lane retains capped live and raw diagnostic evidence; diagnostics older than seven days are removed. This applies to Grok, Claude, Gemini/Antigravity, OpenCode, and Luna/Codex CLI.

For Grok lanes, disable inherited Cursor and Claude MCP discovery by setting `GROK_CURSOR_MCPS_ENABLED=false GROK_CLAUDE_MCPS_ENABLED=false`. Use `--no-subagents` unless the user explicitly asks Grok to coordinate its own subagents. Do not mark Grok unavailable from MCP startup warnings alone if the lane prints task progress or a final response.

Claude uses streaming JSON with partial messages, so emitted thinking and tool activity can appear while it runs. A quiet period is still not a failure signal.

## License

MIT
