import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");

test("Gemini print lanes have no elapsed-time deadline", () => {
  for (const file of [
    "README.md",
    "skills/codex-orchestrator/SKILL.md",
    "skills/codex-orchestrator/references/broker-lanes.md",
  ]) {
    const content = fs.readFileSync(path.join(root, file), "utf8");
    assert.match(content, /--print-timeout 0s/, file);
    assert.doesNotMatch(content, /--print-timeout (?:5|15|20|30|60)m/, file);
  }
});
