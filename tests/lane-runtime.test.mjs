import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const runtime = path.join(root, "skills/codex-orchestrator/scripts/lane-runtime.sh");
const supervisor = path.join(root, "skills/codex-orchestrator/scripts/lane-supervisor.sh");

test("state-dir uses the configured shared root", () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "orchestrator-runtime-"));
  const spec = path.join(temp, "spec.md");
  const stateRoot = path.join(temp, "shared-state");
  fs.writeFileSync(spec, "Objective: inspect one file\n");

  const env = {
    ...process.env,
    CODEX_ORCHESTRATOR_RUNTIME: "supervisor",
    CODEX_ORCHESTRATOR_SUPERVISOR_REASON: "user_requested",
    CODEX_ORCHESTRATOR_STATE_ROOT: stateRoot,
  };
  const stateDir = execFileSync(
    runtime,
    ["state-dir", "--lane", "test", "--cwd", temp, "--spec", spec],
    { encoding: "utf8", env },
  ).trim();

  assert.equal(path.dirname(stateDir), stateRoot);

  const herdrStateDir = execFileSync(
    runtime,
    ["state-dir", "--lane", "test", "--cwd", temp, "--spec", spec],
    {
      encoding: "utf8",
      env: { ...env, CODEX_ORCHESTRATOR_RUNTIME: "herdr" },
    },
  ).trim();
  assert.equal(herdrStateDir, stateDir);

  const start = spawnSync(
    runtime,
    [
      "start",
      "--lane",
      "test",
      "--cwd",
      temp,
      "--spec",
      spec,
      "--state-dir",
      path.join(temp, "wrong-state"),
      "--",
      "true",
    ],
    { encoding: "utf8", env },
  );

  assert.equal(start.status, 2);
  assert.match(start.stderr, /State directory must come from lane-runtime\.sh state-dir/);
});

test("state-dir trims a trailing temporary-directory separator", () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "orchestrator-temp-root-"));
  const spec = path.join(temp, "spec.md");
  fs.writeFileSync(spec, "Objective: inspect one file\n");
  const env = { ...process.env };
  delete env.CODEX_ORCHESTRATOR_STATE_ROOT;
  env.CODEX_ORCHESTRATOR_RUNTIME = "supervisor";
  env.CODEX_ORCHESTRATOR_SUPERVISOR_REASON = "user_requested";
  env.TMPDIR = `${temp}${path.sep}`;

  const stateDir = execFileSync(
    runtime,
    ["state-dir", "--lane", "test", "--cwd", temp, "--spec", spec],
    { encoding: "utf8", env },
  ).trim();

  assert.equal(path.dirname(stateDir), path.join(temp, "codex-orchestrator"));
  assert.doesNotMatch(stateDir, /\/\//);
});

test("a stale supervisor override is rejected while Herdr is ready", () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "orchestrator-runtime-guard-"));
  const bin = path.join(temp, "bin");
  const spec = path.join(temp, "spec.md");
  fs.mkdirSync(bin);
  fs.writeFileSync(spec, "Objective: inspect one file\n");
  const herdr = path.join(bin, "herdr");
  fs.writeFileSync(herdr, "#!/bin/sh\nprintf 'status: running\\n'\n");
  fs.chmodSync(herdr, 0o755);

  const run = spawnSync(
    runtime,
    ["state-dir", "--lane", "test", "--cwd", temp, "--spec", spec],
    {
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${bin}${path.delimiter}${process.env.PATH}`,
        CODEX_ORCHESTRATOR_RUNTIME: "supervisor",
        CODEX_ORCHESTRATOR_SUPERVISOR_REASON: "",
      },
    },
  );

  assert.equal(run.status, 2);
  assert.match(run.stderr, /explicit supervisor mode requires/);
});

test("the supervisor backend rejects a direct start", () => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "orchestrator-direct-start-"));
  const spec = path.join(temp, "spec.md");
  fs.writeFileSync(spec, "Objective: inspect one file\n");

  const run = spawnSync(
    supervisor,
    [
      "start",
      "--lane",
      "test",
      "--cwd",
      temp,
      "--spec",
      spec,
      "--state-dir",
      path.join(temp, "state"),
      "--",
      "true",
    ],
    { encoding: "utf8", env: process.env },
  );

  assert.equal(run.status, 2);
  assert.match(run.stderr, /Start lanes through lane-runtime\.sh/);
});
