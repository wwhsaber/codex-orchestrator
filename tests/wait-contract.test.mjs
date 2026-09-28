import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");

test("external lane waiting stays inside one programmatic tool call", () => {
  for (const file of [
    "skills/codex-orchestrator/SKILL.md",
    "skills/codex-orchestrator/references/broker-lanes.md",
  ]) {
    const content = fs.readFileSync(path.join(root, file), "utf8");
    assert.match(content, /functions\.exec/, file);
    assert.match(content, /tools\.exec_command/, file);
    assert.match(content, /tools\.write_stdin/, file);
    assert.match(content, /must not return the intermediate session ID to the main model/, file);
    assert.doesNotMatch(content, /If the shell tool yields/, file);
    assert.doesNotMatch(content, /If the command tool yields/, file);
  }

  const readme = fs.readFileSync(path.join(root, "README.md"), "utf8");
  assert.match(readme, /one programmatic tool call/);
  assert.match(readme, /does not receive intermediate session IDs/);
});
