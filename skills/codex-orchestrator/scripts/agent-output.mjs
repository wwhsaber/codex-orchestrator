#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import readline from "node:readline";

const WATCH_LIMIT = 2 * 1024 * 1024;
const DIAGNOSTIC_LIMIT = 2 * 1024 * 1024;

function usage() {
  process.stderr.write(
    "Usage: agent-output.mjs --format NAME --watch FILE --final FILE --diagnostic FILE -- COMMAND [ARG...]\n",
  );
}

const options = { format: "", watch: "", final: "", diagnostic: "" };
let index = 2;
for (; index < process.argv.length; index += 1) {
  const argument = process.argv[index];
  if (argument === "--") {
    index += 1;
    break;
  }
  if (!["--format", "--watch", "--final", "--diagnostic"].includes(argument)) {
    usage();
    process.exit(2);
  }
  const value = process.argv[index + 1];
  if (!value) {
    usage();
    process.exit(2);
  }
  options[argument.slice(2)] = value;
  index += 1;
}

const command = process.argv[index];
const commandArgs = process.argv.slice(index + 1);
if (!options.format || !options.watch || !options.final || !options.diagnostic || !command) {
  usage();
  process.exit(2);
}

for (const file of [options.watch, options.final, options.diagnostic]) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
}
const diagnosticTemp = `${options.diagnostic}.tmp`;
fs.writeFileSync(options.watch, "");
fs.writeFileSync(options.final, "");
fs.writeFileSync(diagnosticTemp, "");
try {
  fs.unlinkSync(options.diagnostic);
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}

function createRing(file, limit) {
  const chunks = [];
  let bytes = 0;
  return (value) => {
    let text = value.endsWith("\n") ? value : `${value}\n`;
    if (Buffer.byteLength(text) > limit) {
      text = Buffer.from(text).subarray(-limit).toString();
    }
    chunks.push(text);
    bytes += Buffer.byteLength(text);
    let trimmed = false;
    while (bytes > limit && chunks.length > 1) {
      bytes -= Buffer.byteLength(chunks.shift());
      trimmed = true;
    }
    if (trimmed) fs.writeFileSync(file, chunks.join(""));
    else fs.appendFileSync(file, text);
  };
}

const writeWatchLine = createRing(options.watch, WATCH_LIMIT);
const writeDiagnosticLine = createRing(diagnosticTemp, DIAGNOSTIC_LIMIT);
const emitted = new Set();
let explicitResult = "";
let lastAssistant = "";
let streamedText = "";
const openCodeMessages = new Map();
let latestOpenCodeMessage = "";

function clip(value, limit = 800) {
  const clean = String(value ?? "")
    .replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/\s{2,}/g, " ")
    .trim();
  return clean.length > limit ? `${clean.slice(0, limit)}...[truncated]` : clean;
}

function emitOnce(key, value) {
  if (!value || emitted.has(key)) return;
  emitted.add(key);
  writeWatchLine(value);
}

function contentText(value) {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return value.map(contentText).filter(Boolean).join("");
  if (!value || typeof value !== "object") return "";
  if (typeof value.text === "string") return value.text;
  if (typeof value.output_text === "string") return value.output_text;
  if (value.content !== undefined) return contentText(value.content);
  return "";
}

function messageText(event) {
  if (event?.type === "assistant") return contentText(event.message?.content);
  if (event?.item?.type === "agent_message") return contentText(event.item.text);
  if (event?.type === "message" && event?.role === "assistant") {
    return contentText(event.content ?? event.message);
  }
  if (event?.type === "text") return contentText(event.part ?? event);
  if (event?.sessionUpdate === "agent_message_chunk") return contentText(event.content);
  return "";
}

function deltaText(event) {
  const streamEvent = event?.type === "stream_event" ? event.event : event;
  if (streamEvent?.delta?.type === "text_delta") return contentText(streamEvent.delta.text);
  if (streamEvent?.type === "content_block_delta" && streamEvent?.delta?.text) {
    return contentText(streamEvent.delta.text);
  }
  if (event?.type === "text_delta") return contentText(event.text ?? event.delta);
  return "";
}

function thinkingText(event) {
  const streamEvent = event?.type === "stream_event" ? event.event : event;
  const delta = streamEvent?.delta;
  if (delta?.type === "thinking_delta") return contentText(delta.thinking ?? delta.text);
  if (event?.type === "thinking" || event?.type === "reasoning") {
    return contentText(event.part ?? event.content ?? event.text);
  }
  if (event?.part?.type === "reasoning" || event?.part?.type === "thinking") {
    return contentText(event.part);
  }
  if (event?.item?.type === "reasoning" || event?.item?.type === "thinking") {
    return contentText(event.item);
  }
  const messageBlocks = event?.message?.content;
  if (Array.isArray(messageBlocks)) {
    return messageBlocks
      .filter((block) => block?.type === "thinking" || block?.type === "reasoning")
      .map((block) => block.thinking ?? contentText(block))
      .filter(Boolean)
      .join("\n");
  }
  return "";
}

function finalText(event) {
  if (event?.type === "result") {
    return contentText(event.result ?? event.output ?? event.message);
  }
  if (event?.type === "final" || event?.type === "completed") {
    return contentText(event.result ?? event.output ?? event.content ?? event.message);
  }
  return "";
}

function eventName(event) {
  return String(event?.type ?? event?.event?.type ?? event?.sessionUpdate ?? "");
}

function toolSummary(event) {
  const candidates = [
    event?.item,
    event?.part,
    event?.message,
    event?.event?.content_block,
    event?.content,
    event,
  ];
  for (const candidate of candidates) {
    if (!candidate || typeof candidate !== "object") continue;
    const kind = String(candidate.type ?? eventName(event)).toLowerCase();
    if (!kind.includes("tool") && !kind.includes("command")) continue;
    const name = candidate.name ?? candidate.tool ?? candidate.tool_name ?? candidate.command;
    const input = candidate.input ?? candidate.state?.input ?? candidate.arguments;
    let detail = "";
    if (typeof input === "string") detail = input;
    else if (input && typeof input === "object") {
      detail = input.path ?? input.file_path ?? input.command ?? input.query ?? "";
    }
    return clip([name, detail].filter(Boolean).join(" "), 500);
  }
  return "";
}

function handleEvent(event) {
  const name = eventName(event).toLowerCase();
  const thinking = thinkingText(event);
  if (thinking) writeWatchLine(`THINKING ${clip(thinking, 8000)}`);
  else if (name.includes("thinking") || name.includes("reasoning")) {
    emitOnce("thinking", "THINKING active");
  }
  if (name.includes("thread") || name.includes("session") || name === "init") {
    emitOnce("session", `SESSION started format=${options.format}`);
  }
  const tool = toolSummary(event);
  if (tool) writeWatchLine(`TOOL ${tool}`);
  if (name.includes("error") || name.includes("fail")) {
    const detail = clip(event.error?.message ?? event.error ?? event.message ?? name, 1200);
    writeWatchLine(`ERROR ${detail}`);
  }

  const delta = deltaText(event);
  if (delta) {
    streamedText += delta;
    emitOnce("response", "RESPONSE streaming");
  }
  const assistant = messageText(event);
  if (assistant) {
    if (event?.type === "text" && event?.part?.id) {
      const messageId = event.part.messageID ?? event.messageID ?? event.part.id;
      if (!openCodeMessages.has(messageId)) openCodeMessages.set(messageId, new Map());
      openCodeMessages.get(messageId).set(event.part.id, assistant);
      latestOpenCodeMessage = messageId;
      lastAssistant = [...openCodeMessages.get(latestOpenCodeMessage).values()].join("\n");
    } else {
      lastAssistant = assistant;
    }
    emitOnce("assistant", "RESPONSE available");
  }
  const completed = finalText(event);
  if (completed) explicitResult = completed;

  const best = explicitResult || lastAssistant || streamedText;
  if (best) fs.writeFileSync(options.final, best);
}

function handleLine(line, source) {
  if (!line) return;
  writeDiagnosticLine(`${source.toUpperCase()} ${line}`);
  try {
    handleEvent(JSON.parse(line));
  } catch {
    const clean = clip(line, 1000);
    if (clean) writeWatchLine(`${source.toUpperCase()} ${clean}`);
  }
}

writeWatchLine(`STARTED agent=${path.basename(command)} format=${options.format}`);
const child = spawn(command, commandArgs, {
  cwd: process.cwd(),
  env: process.env,
  stdio: ["pipe", "pipe", "pipe"],
});
process.stdin.pipe(child.stdin);

for (const [stream, source] of [
  [child.stdout, "stdout"],
  [child.stderr, "stderr"],
]) {
  const lines = readline.createInterface({ input: stream, crlfDelay: Infinity });
  lines.on("line", (line) => handleLine(line, source));
}

for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.on(signal, () => {
    if (!child.killed) child.kill(signal);
  });
}

child.on("error", (error) => {
  writeWatchLine(`ERROR ${clip(error.message, 1200)}`);
});

child.on("close", (code, signal) => {
  const exitCode = Number.isInteger(code) ? code : 1;
  const best = explicitResult || lastAssistant || streamedText;
  if (best) {
    fs.writeFileSync(options.final, best);
  } else if (exitCode !== 0) {
    fs.writeFileSync(
      options.final,
      `STATUS: failed\nAgent process ended with code ${exitCode}${signal ? ` (${signal})` : ""}.`,
    );
  } else {
    fs.writeFileSync(options.final, "STATUS: completed\nThe agent emitted no final response.");
  }

  writeWatchLine(`FINISHED code=${exitCode}${signal ? ` signal=${signal}` : ""}`);
  if (exitCode === 0) {
    try {
      fs.unlinkSync(diagnosticTemp);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  } else {
    try {
      fs.renameSync(diagnosticTemp, options.diagnostic);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  process.exit(exitCode);
});
