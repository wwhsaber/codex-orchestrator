import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

async function read(path) {
  return readFile(new URL(path, root), "utf8");
}

test("Sol and Luna aliases use the requested GPT-6 Codex lanes", async () => {
  const [readme, skill, lanes] = await Promise.all([
    read("README.md"),
    read("skills/codex-orchestrator/SKILL.md"),
    read("skills/codex-orchestrator/references/broker-lanes.md")
  ]);
  const text = `${readme}\n${skill}\n${lanes}`;
  const solSection = lanes.slice(lanes.indexOf("### Sol"), lanes.indexOf("### Luna"));

  assert.doesNotMatch(text, /gpt-5\.6-luna/);
  assert.match(skill, /`sol` as an exact lane alias for Codex CLI model `gpt-6-sol`/);
  assert.match(skill, /`luna` as an exact lane alias for Codex CLI model `gpt-6-luna`/);
  assert.match(solSection, /--lane sol[\s\S]*--model gpt-6-sol[\s\S]*model_reasoning_effort="medium"/);
  assert.doesNotMatch(solSection, /service_tier="priority"/);
  assert.match(lanes, /--lane luna[\s\S]*--model gpt-6-luna[\s\S]*model_reasoning_effort="max"[\s\S]*service_tier="priority"/);
});

test("Jev integration is absent from the orchestrator repository", async () => {
  const [readme, skill] = await Promise.all([
    read("README.md"),
    read("skills/codex-orchestrator/SKILL.md")
  ]);

  assert.doesNotMatch(`${readme}\n${skill}`, /jev|typesafe/i);
});
