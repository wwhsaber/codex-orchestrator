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

function runAdapter(events) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "codex-agent-output-"));
  const watch = path.join(directory, "lane.log");
  const final = path.join(directory, "final.txt");
  const diagnostic = path.join(directory, "diagnostic.log");
  const childScript = `for (const event of ${JSON.stringify(events)}) console.log(JSON.stringify(event));`;
  const run = spawnSync(
    process.execPath,
    [
      adapter,
      "--format",
      "opencode",
      "--watch",
      watch,
      "--final",
      final,
      "--diagnostic",
      diagnostic,
      "--",
      process.execPath,
      "-e",
      childScript,
    ],
    { encoding: "utf8" },
  );
  return {
    run,
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
