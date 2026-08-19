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
  if (mirrorWatch) delete env.NO_COLOR;
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
  assert.match(result.run.stdout, /\x1b\[2mthinking\x1b\[0m/);
  assert.equal((result.run.stdout.match(/\x1b\[2mthinking\x1b\[0m/g) ?? []).length, 1);
  assert.match(result.run.stdout, /\x1b\[36;1mread_file\x1b\[0m/);
  assert.doesNotMatch(result.watch, /\x1b\[/);
  assert.match(result.watch, /THINKING Inspecting the timeline\./);
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
