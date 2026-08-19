import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const testDir = path.dirname(fileURLToPath(import.meta.url));
const adapter = path.join(
  testDir,
  "..",
  "skills",
  "codex-orchestrator",
  "scripts",
  "agent-output.mjs",
);

function runAdapter(events, format = "opencode", mirrorWatch = false) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "codex-agent-output-"));
  const watch = path.join(directory, "lane.log");
  const final = path.join(directory, "final.txt");
  const diagnostic = path.join(directory, "diagnostic.log");
  const childScript = `for (const event of ${JSON.stringify(events)}) console.log(JSON.stringify(event));`;
  const adapterArgs = [
    adapter,
    "--format",
    format,
    "--watch",
    watch,
    "--final",
    final,
    "--diagnostic",
    diagnostic,
  ];
  if (mirrorWatch) adapterArgs.push("--mirror-watch");
  adapterArgs.push("--", process.execPath, "-e", childScript);
  const env = { ...process.env };
  if (mirrorWatch) {
    env.HERDR_ENV = "1";
    env.NO_COLOR = "1";
  }
  const run = spawnSync(
    process.execPath,
    adapterArgs,
    { encoding: "utf8", env },
  );
  return {
    run,
    watch: fs.readFileSync(watch, "utf8"),
    final: fs.readFileSync(final, "utf8"),
    status: fs.readFileSync(`${final}.status`, "utf8"),
    diagnosticExists: fs.existsSync(diagnostic),
  };
}

test("accepts text from a normally completed OpenCode step", () => {
  const result = runAdapter([
    {
      type: "text",
      part: { id: "part-1", messageID: "message-1", type: "text", text: "Usable review" },
    },
    {
      type: "step_finish",
      part: { messageID: "message-1", type: "step-finish", reason: "stop" },
    },
  ]);

  assert.equal(result.run.status, 0);
  assert.equal(result.final, "Usable review");
  assert.match(result.status, /producer_exit_code=0/);
  assert.match(result.status, /final_available=true/);
  assert.equal(result.diagnosticExists, false);
});

test("groups Grok thinking deltas into readable lines", () => {
  const result = runAdapter(
    [
      { type: "thinking", text: "This" },
      { type: "thinking", text: " is" },
      { type: "thinking", text: " a" },
      { type: "thinking", text: " large" },
      { type: "thinking", text: " task." },
      { type: "tool_use", name: "read_file", input: { path: "src/app.ts" } },
      { type: "result", result: "Done" },
    ],
    "grok",
  );

  assert.equal(result.run.status, 0);
  assert.match(result.watch, /THINKING This is a large task\.\n/);
  assert.doesNotMatch(result.watch, /THINKING This\nTHINKING is/);
  assert.match(result.watch, /TOOL read_file src\/app\.ts/);
  assert.equal(result.final, "Done");
});

test("styles mirrored Grok activity without coloring the saved log", () => {
  const result = runAdapter(
    [
      { type: "thinking", text: "Inspecting the timeline." },
      { type: "thinking", text: "Reading the mapper." },
      { type: "tool_use", name: "read_file", input: { path: "src/app.ts" } },
      { type: "result", result: "Done" },
    ],
    "grok",
    true,
  );

  assert.equal(result.run.status, 0);
  assert.match(result.run.stdout, /\x1b\[1;38;2;74;222;128magent\x1b\[0m/);
  assert.match(result.run.stdout, /\x1b\[38;2;148;163;184mthinking\x1b\[0m/);
  assert.equal(
    (result.run.stdout.match(/\x1b\[38;2;148;163;184mthinking\x1b\[0m/g) ?? []).length,
    1,
  );
  assert.match(result.run.stdout, /\n\n  \x1b\[1;38;2;34;211;238m>\x1b\[0m/);
  assert.match(result.run.stdout, /\x1b\[1;38;2;34;211;238mread_file\x1b\[0m/);
  assert.doesNotMatch(result.watch, /\x1b\[/);
  assert.match(result.watch, /THINKING Inspecting the timeline\./);
});

test("does not repeat a Grok thinking snapshot after streamed deltas", () => {
  const result = runAdapter(
    [
      {
        type: "stream_event",
        event: {
          type: "content_block_delta",
          delta: { type: "thinking_delta", thinking: "Inspecting the timeline." },
        },
      },
      {
        type: "assistant",
        message: {
          content: [{ type: "thinking", thinking: "Inspecting the timeline." }],
        },
      },
      { type: "result", result: "Done" },
    ],
    "grok",
  );

  assert.equal(result.run.status, 0);
  assert.equal((result.watch.match(/Inspecting the timeline\./g) ?? []).length, 1);
});

test("wraps long Herdr thinking blocks to a readable width", () => {
  const thought = Array.from({ length: 30 }, () => "implementation").join(" ");
  const result = runAdapter(
    [
      { type: "thinking", text: `${thought}.` },
      { type: "result", result: "Done" },
    ],
    "grok",
    true,
  );

  const thinkingLines = result.run.stdout
    .split("\n")
    .filter((line) => line.includes("implementation"));
  assert.ok(thinkingLines.length > 1);
  assert.ok(thinkingLines.every((line) => line.replace(/\x1b\[[0-9;]+m/g, "").length <= 116));
});

test("preserves thinking structure and renders fenced code without italics", () => {
  const result = runAdapter(
    [
      {
        type: "thinking",
        text: [
          "## Review",
          "",
          "- Keep `agent-output.mjs` readable",
          "1. Preserve source lines",
          "",
          "```js",
          "const answer = 42;",
          "  return answer;",
          "```",
        ].join("\n"),
      },
      { type: "result", result: "Done" },
    ],
    "grok",
    true,
  );

  assert.match(result.watch, /THINKING_HEADING Review/);
  assert.match(result.watch, /THINKING_BULLET Keep agent-output\.mjs readable/);
  assert.match(result.watch, /THINKING_NUMBER 1\. Preserve source lines/);
  assert.match(result.watch, /CODE_START js/);
  assert.match(result.watch, /CODE const answer = 42;/);
  assert.match(result.watch, /CODE   return answer;/);
  assert.match(result.run.stdout, /\x1b\[38;2;125;211;252mconst answer = 42;/);
  assert.match(result.run.stdout, /\s+1\x1b\[0m \x1b\[38;2;148;163;184m│/);
  assert.match(result.run.stdout, /╰─/);
  assert.doesNotMatch(result.run.stdout, /\*\*|```/);
});

test("does not split a filename when a thinking chunk ends with a period", () => {
  const result = runAdapter(
    [
      { type: "thinking", text: "Reading agent-output." },
      { type: "thinking", text: "mjs before editing." },
      { type: "tool_use", name: "read_file", input: { path: "agent-output.mjs" } },
      { type: "result", result: "Done" },
    ],
    "grok",
  );

  assert.match(result.watch, /THINKING Reading agent-output\.mjs before editing\./);
});

test("keeps fragmented fences and code lines in the correct section", () => {
  const result = runAdapter(
    [
      { type: "thinking", text: "Inspect the harness.  ```typescript\n// useCreativeCanvasAgentHarness." },
      { type: "thinking", text: "ts\nfunction inspect() {\n  return true;\n}\n```\n\nContinue with the review." },
      { type: "tool_use", name: "read_file", input: { path: "src/app.ts" } },
      { type: "result", result: "Done" },
    ],
    "grok",
  );

  assert.match(result.watch, /THINKING Inspect the harness\./);
  assert.match(result.watch, /CODE_START typescript/);
  assert.match(result.watch, /CODE \/\/ useCreativeCanvasAgentHarness\.ts/);
  assert.match(result.watch, /CODE   return true;/);
  assert.match(result.watch, /CODE_END\nTHINKING_BLANK\nTHINKING Continue with the review\./);
  assert.doesNotMatch(result.watch, /CODE Continue with the review/);
});

test("rejects a successful producer exit without final text", () => {
  const result = runAdapter([
    {
      type: "reasoning",
      part: { id: "part-1", messageID: "message-1", type: "reasoning", text: "Inspecting" },
    },
  ]);

  assert.equal(result.run.status, 65);
  assert.match(result.final, /^STATUS: unavailable/);
  assert.match(result.status, /producer_exit_code=0/);
  assert.match(result.status, /final_available=false/);
  assert.equal(result.diagnosticExists, true);
});

test("does not promote intermediate OpenCode narration to final text", () => {
  const result = runAdapter([
    {
      type: "text",
      part: {
        id: "part-1",
        messageID: "message-1",
        type: "text",
        text: "Now let me inspect another file.",
      },
    },
    {
      type: "step_finish",
      part: { messageID: "message-1", type: "step-finish", reason: "tool-calls" },
    },
    {
      type: "tool_use",
      part: { messageID: "message-1", type: "tool", tool: "read" },
    },
  ]);

  assert.equal(result.run.status, 65);
  assert.match(result.final, /^STATUS: unavailable/);
  assert.doesNotMatch(result.final, /Now let me inspect/);
  assert.equal(result.diagnosticExists, true);
});
