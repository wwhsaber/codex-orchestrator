import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");

test("manual ChatGPT Web mode ships no automatic callback artifacts", () => {
  for (const file of [
    "skills/codex-orchestrator/scripts/chatgpt-web.mjs",
    "skills/codex-orchestrator/scripts/c2c-advice.patch",
  ]) {
    assert.equal(fs.existsSync(path.join(root, file)), false, file);
  }
});

test("Gemini defaults to the 3.8 Flash High model", () => {
  for (const file of [
    "README.md",
    "skills/codex-orchestrator/SKILL.md",
    "skills/codex-orchestrator/references/broker-lanes.md",
  ]) {
    const content = fs.readFileSync(path.join(root, file), "utf8");
    assert.match(content, /gemini-3\.8-flash-high/, file);
    assert.doesNotMatch(content, /gemini-3\.6-flash-high/, file);
  }
});
