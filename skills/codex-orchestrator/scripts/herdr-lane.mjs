#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";

const RESULT_LIMIT = 16 * 1024;
const SPEC_LIMIT = 16 * 1024;

function usage() {
  process.stderr.write(
    "Usage: herdr-lane.mjs check-spec --spec FILE | key --lane NAME --cwd DIR --spec FILE | start --lane NAME --cwd DIR --spec FILE --state-dir DIR [--title TEXT] [--model-label TEXT] [--mode read|write] [--stdin FILE] [--result-source FILE] [--ephemeral-watch] -- COMMAND [ARG...] | await|status|stop|result --state-dir DIR\n",
  );
}

function cleanLine(value) {
  return String(value ?? "").replace(/[\r\n]+/g, " ");
}

function utcNow() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function readFields(stateFile) {
  const fields = {};
  for (const line of fs.readFileSync(stateFile, "utf8").split("\n")) {
    const split = line.indexOf("=");
    if (split > 0) fields[line.slice(0, split)] = line.slice(split + 1);
  }
  return fields;
}

function writeFields(stateFile, fields) {
  const temp = `${stateFile}.tmp.${process.pid}`;
  const text = Object.entries(fields)
    .map(([key, value]) => `${key}=${cleanLine(value)}`)
    .join("\n");
  fs.writeFileSync(temp, `${text}\n`);
  fs.renameSync(temp, stateFile);
}

function updateState(stateDir, values) {
  const stateFile = path.join(stateDir, "state");
  const fields = readFields(stateFile);
  Object.assign(fields, values, { updated_at: utcNow() });
  writeFields(stateFile, fields);
  return fields;
}

function parseOptions(args) {
  const values = {};
  const command = [];
  for (let index = 0; index < args.length; index += 1) {
    const item = args[index];
    if (item === "--") {
      command.push(...args.slice(index + 1));
      break;
    }
    if (item === "--ephemeral-watch") {
      values.ephemeralWatch = true;
      continue;
    }
    if (!item.startsWith("--") || index + 1 >= args.length) {
      usage();
      process.exit(2);
    }
    const key = item
      .slice(2)
      .replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    values[key] = args[index + 1];
    index += 1;
  }
  return { values, command };
}

function quoteShell(value) {
  return `'${String(value).replaceAll("'", `'\"'\"'`)}'`;
}

function scriptPath() {
  return path.isAbsolute(process.argv[1])
    ? process.argv[1]
    : path.join(process.cwd(), process.argv[1]);
}

function runHerdr(args, options = {}) {
  const run = spawnSync("herdr", args, {
    encoding: "utf8",
    ...options,
  });
  if (run.error) throw run.error;
  if (run.status !== 0) {
    throw new Error(`herdr ${args.slice(0, 2).join(" ")} failed: ${run.stderr || run.stdout}`);
  }
  return run.stdout;
}

function herdrReady() {
  const check = spawnSync("herdr", ["status", "server"], { encoding: "utf8" });
  return check.status === 0 && check.stdout.includes("status: running");
}

function processExists(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function finishFiles(stateDir, state, exitCode, message) {
  const fields = readFields(path.join(stateDir, "state"));
  const source = fields.result_source;
  const sourceStatus = source ? `${source}.status` : "";
  const result = fields.result || path.join(stateDir, "result.txt");
  const adapterStatus = sourceStatus && fs.existsSync(sourceStatus) ? readFields(sourceStatus) : {};
  const producerExitCode = adapterStatus.producer_exit_code ?? "";
  const finalAvailable = adapterStatus.final_available ?? "";
  if (producerExitCode === "0" && finalAvailable === "false") {
    state = "failed";
    message = "missing_final";
  }
  let content = "";
  if (source && fs.existsSync(source)) content = fs.readFileSync(source);
  if (!content.length) {
    content = Buffer.from(
      state === "exited"
        ? "STATUS: completed\nThe agent emitted no final response.\n"
        : `STATUS: ${state}\nThe Herdr lane ended with code ${exitCode}.\n`,
    );
  }
  const clipped = content.length > RESULT_LIMIT ? content.subarray(-RESULT_LIMIT) : content;
  fs.writeFileSync(result, clipped);
  updateState(stateDir, {
    state,
    exit_code: exitCode,
    result_truncated: content.length > RESULT_LIMIT ? "true" : "false",
    log_bytes: fs.existsSync(fields.log) ? fs.statSync(fields.log).size : 0,
    producer_exit_code: producerExitCode,
    final_available: finalAvailable,
    message,
  });
  fs.writeFileSync(fields.done || path.join(stateDir, "done"), "");

  if (fields.ephemeral_watch === "true") {
    const diagnosticTemp = `${fields.diagnostic}.tmp`;
    if (
      (state === "failed" || state === "interrupted") &&
      fs.existsSync(diagnosticTemp) &&
      !fs.existsSync(fields.diagnostic)
    ) {
      fs.renameSync(diagnosticTemp, fields.diagnostic);
    } else {
      fs.rmSync(diagnosticTemp, { force: true });
    }
    if (state === "exited" || state === "cancelled") {
      for (const file of [fields.log, source, sourceStatus]) {
        if (file && file !== result) fs.rmSync(file, { force: true });
      }
      fs.rmSync(fields.supervisor_log, { force: true });
    }
  }
  fs.rmSync(path.join(stateDir, "command.sh"), { force: true });
  fs.rmSync(path.join(stateDir, "exit-code"), { force: true });
}

function closeWorkspace(fields) {
  if (!fields.herdr_workspace) return;
  spawnSync("herdr", ["workspace", "close", fields.herdr_workspace], {
    encoding: "utf8",
  });
}

async function watchLane(stateDir) {
  const stateFile = path.join(stateDir, "state");
  const fields = readFields(stateFile);
  const wait = spawnSync(
    "herdr",
    [
      "pane",
      "wait-output",
      fields.herdr_pane,
      "--regex",
      `^${fields.completion_marker}$`,
      "--source",
      "recent-unwrapped",
      "--lines",
      "120",
    ],
    { encoding: "utf8" },
  );
  const latest = readFields(stateFile);
  if (["exited", "failed", "cancelled", "interrupted"].includes(latest.state)) return;
  if (fs.existsSync(path.join(stateDir, "stop-requested"))) return;

  const exitFile = path.join(stateDir, "exit-code");
  if (wait.status !== 0 || !fs.existsSync(exitFile)) {
    finishFiles(stateDir, "interrupted", 125, "herdr_wait_ended");
    closeWorkspace(latest);
    return;
  }
  const exitCode = Number.parseInt(fs.readFileSync(exitFile, "utf8").trim(), 10);
  finishFiles(
    stateDir,
    exitCode === 0 ? "exited" : "failed",
    Number.isInteger(exitCode) ? exitCode : 1,
    exitCode === 0 ? "completed" : "command_failed",
  );
  closeWorkspace(latest);
}

function startWatcher(stateDir) {
  const child = spawn(process.execPath, [scriptPath(), "_watch", "--state-dir", stateDir], {
    detached: true,
    stdio: "ignore",
  });
  child.unref();
  updateState(stateDir, { state: "running", pid: child.pid });
  return child.pid;
}

function checkSpec(spec) {
  if (!spec || !fs.existsSync(spec)) throw new Error(`Spec file not found: ${spec || ""}`);
  const bytes = fs.statSync(spec).size;
  if (bytes > SPEC_LIMIT) throw new Error(`Spec exceeds ${SPEC_LIMIT}-byte limit: bytes=${bytes} path=${spec}`);
  return bytes;
}

function commandStart(args) {
  const { values, command } = parseOptions(args);
  for (const name of ["lane", "cwd", "spec", "stateDir"]) {
    if (!values[name]) throw new Error(`Missing --${name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)}`);
  }
  if (!command.length) throw new Error("Missing lane command");
  checkSpec(values.spec);
  if (!fs.statSync(values.cwd).isDirectory()) throw new Error(`Working directory not found: ${values.cwd}`);
  if (values.stdin && !fs.existsSync(values.stdin)) throw new Error(`Stdin file not found: ${values.stdin}`);
  if (!herdrReady()) throw new Error("Herdr server is not running. Start it with `brew services start herdr` or run `herdr server`.");

  fs.mkdirSync(values.stateDir, { recursive: true });
  const stateFile = path.join(values.stateDir, "state");
  if (fs.existsSync(stateFile)) {
    const existing = readFields(stateFile);
    if (["starting", "running"].includes(existing.state) && processExists(Number(existing.pid))) {
      process.stdout.write(`ALREADY_RUNNING lane=${values.lane} pid=${existing.pid} state=${stateFile}\n`);
      return;
    }
  }

  const taskId = path.basename(values.stateDir);
  const log = path.join(values.stateDir, "lane.log");
  const supervisorLog = path.join(values.stateDir, "supervisor.log");
  const result = path.join(values.stateDir, "result.txt");
  const diagnostic = path.join(values.stateDir, "diagnostic.log");
  const done = path.join(values.stateDir, "done");
  for (const file of [log, supervisorLog, result]) fs.writeFileSync(file, "");
  for (const file of [done, path.join(values.stateDir, "stop-requested"), diagnostic, `${diagnostic}.tmp`]) {
    fs.rmSync(file, { force: true });
  }

  const created = JSON.parse(
    runHerdr([
      "workspace",
      "create",
      "--cwd",
      path.dirname(values.stateDir),
      "--label",
      `codex-${values.lane}-${taskId}`,
      "--no-focus",
    ]),
  );
  const workspace = created.result.workspace.workspace_id;
  const pane = created.result.root_pane.pane_id;
  const marker = `__CODEX_HERDR_DONE_${taskId.replace(/[^A-Za-z0-9_]/g, "_")}__`;
  const started = utcNow();
  writeFields(stateFile, {
    version: 4,
    task_id: taskId,
    title: values.title || "",
    state: "starting",
    lane: values.lane,
    model: values.modelLabel || "",
    mode: values.mode || "",
    pid: 0,
    launch_label: "",
    controller: scriptPath(),
    runtime: "herdr",
    runtime_target: pane,
    herdr_workspace: workspace,
    herdr_pane: pane,
    completion_marker: marker,
    started_at: started,
    updated_at: started,
    cwd: values.cwd,
    spec: values.spec,
    log,
    supervisor_log: supervisorLog,
    result,
    result_source: values.resultSource || "",
    ephemeral_watch: values.ephemeralWatch ? "true" : "false",
    diagnostic,
    done,
    exit_code: "",
    producer_exit_code: "",
    final_available: "",
    log_bytes: 0,
    result_truncated: "false",
    message: "",
  });

  const commandFile = path.join(values.stateDir, "command.sh");
  const exitFile = path.join(values.stateDir, "exit-code");
  const script = [
    "#!/bin/sh",
    "set +e",
    "export HERDR_ENV=1",
    `cd ${quoteShell(values.cwd)} || exit 72`,
    command.map(quoteShell).join(" "),
    "lane_code=$?",
    `printf '%s\\n' \"$lane_code\" > ${quoteShell(exitFile)}`,
    `printf '%s\\n' ${quoteShell(marker)}`,
    "exit \"$lane_code\"",
    "",
  ].join("\n");
  fs.writeFileSync(commandFile, script, { mode: 0o700 });
  runHerdr(["pane", "run", pane, `/bin/sh ${quoteShell(commandFile)}`]);
  const watcherPid = startWatcher(values.stateDir);
  process.stdout.write(`STARTED lane=${values.lane} pid=${watcherPid} runtime=herdr pane=${pane} state=${stateFile} log=${log} result=${result} done=${done}\n`);
}

async function waitForDone(stateDir) {
  const done = path.join(stateDir, "done");
  if (fs.existsSync(done)) return;
  await new Promise((accept) => {
    const watcher = fs.watch(stateDir, (_event, name) => {
      if (name === "done" && fs.existsSync(done)) {
        watcher.close();
        clearInterval(timer);
        accept();
      }
    });
    const timer = setInterval(() => {
      if (fs.existsSync(done)) {
        watcher.close();
        clearInterval(timer);
        accept();
      }
    }, 2000);
  });
}

async function commandAwait(stateDir) {
  const stateFile = path.join(stateDir, "state");
  if (!fs.existsSync(stateFile)) throw new Error(`Missing state: ${stateFile}`);
  await waitForDone(stateDir);
  process.stdout.write("AWAIT_COMPLETE\n");
  process.stdout.write(fs.readFileSync(stateFile));
  process.stdout.write("--- result ---\n");
  const result = path.join(stateDir, "result.txt");
  if (fs.existsSync(result)) process.stdout.write(fs.readFileSync(result));
}

function commandStatus(stateDir) {
  const stateFile = path.join(stateDir, "state");
  if (!fs.existsSync(stateFile)) throw new Error(`Missing state: ${stateFile}`);
  const fields = readFields(stateFile);
  if (["starting", "running"].includes(fields.state) && !processExists(Number(fields.pid))) {
    const pane = spawnSync("herdr", ["pane", "get", fields.herdr_pane], { encoding: "utf8" });
    if (pane.status === 0) startWatcher(stateDir);
    else finishFiles(stateDir, "interrupted", 125, "herdr_pane_missing");
  }
  process.stdout.write(fs.readFileSync(stateFile));
}

function commandStop(stateDir) {
  const stateFile = path.join(stateDir, "state");
  if (!fs.existsSync(stateFile)) throw new Error(`Missing state: ${stateFile}`);
  const fields = readFields(stateFile);
  if (["exited", "failed", "cancelled", "interrupted"].includes(fields.state)) {
    process.stdout.write(`ALREADY_TERMINAL state=${fields.state} path=${stateFile}\n`);
    return;
  }
  fs.writeFileSync(path.join(stateDir, "stop-requested"), "");
  spawnSync("herdr", ["pane", "send-keys", fields.herdr_pane, "ctrl-c"], { encoding: "utf8" });
  closeWorkspace(fields);
  const watcherPid = Number(fields.pid);
  if (processExists(watcherPid)) process.kill(watcherPid, "SIGTERM");
  finishFiles(stateDir, "cancelled", 130, "user_stopped");
  process.stdout.write(`STOPPED lane=${fields.lane} pid=${fields.pid} runtime=herdr state=${stateFile}\n`);
}

function commandResult(stateDir) {
  const fields = readFields(path.join(stateDir, "state"));
  if (!["exited", "failed", "cancelled", "interrupted"].includes(fields.state)) {
    throw new Error(`Result is not ready; state=${fields.state}`);
  }
  process.stdout.write(fs.readFileSync(fields.result));
}

const action = process.argv[2];
const { values } = parseOptions(process.argv.slice(3));
try {
  if (action === "check-spec") {
    const bytes = checkSpec(values.spec);
    process.stdout.write(`SPEC_OK bytes=${bytes} limit=${SPEC_LIMIT} path=${values.spec}\n`);
  } else if (action === "key") {
    checkSpec(values.spec);
    const input = `${values.lane}\n${values.cwd}\n${fs.readFileSync(values.spec)}\nherdr\n`;
    const key = spawnSync("cksum", { input, encoding: "utf8" }).stdout.trim().split(/\s+/)[0];
    process.stdout.write(`${key}\n`);
  } else if (action === "start") {
    commandStart(process.argv.slice(3));
  } else if (action === "await") {
    await commandAwait(values.stateDir);
  } else if (action === "status") {
    commandStatus(values.stateDir);
  } else if (action === "stop") {
    commandStop(values.stateDir);
  } else if (action === "result") {
    commandResult(values.stateDir);
  } else if (action === "_watch") {
    await watchLane(values.stateDir);
  } else {
    usage();
    process.exit(2);
  }
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exit(1);
}
