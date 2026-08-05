#!/usr/bin/env bash
set -u
set -o pipefail

usage() {
  printf '%s\n' 'Usage: codex-event-log.sh --raw FILE -- COMMAND [ARG...]'
}

raw_file=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --raw)
      if [ -z "${2-}" ]; then
        usage >&2
        exit 2
      fi
      raw_file=$2
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$raw_file" ] || [ "$#" -eq 0 ]; then
  usage >&2
  exit 2
fi

mkdir -p "$(dirname "$raw_file")"

set +e
"$@" 2>&1 \
  | tee "$raw_file" \
  | awk '
function clip(value, limit) {
  if (length(value) <= limit)
    return value
  return substr(value, 1, limit) "...[truncated]"
}

function string_field(line, key, marker, start_at, index_at, char_at, escaped, output) {
  marker = "\"" key "\":\""
  start_at = index(line, marker)
  if (!start_at)
    return ""
  start_at += length(marker)
  escaped = 0
  output = ""
  for (index_at = start_at; index_at <= length(line); index_at += 1) {
    char_at = substr(line, index_at, 1)
    if (escaped) {
      output = output "\\" char_at
      escaped = 0
    }
    else if (char_at == "\\") {
      escaped = 1
    }
    else if (char_at == "\"") {
      break
    }
    else {
      output = output char_at
    }
  }
  return output
}

function scalar_field(line, key, marker, start_at, remaining) {
  marker = "\"" key "\":"
  start_at = index(line, marker)
  if (!start_at)
    return ""
  remaining = substr(line, start_at + length(marker))
  sub(/[,}].*$/, "", remaining)
  return remaining
}

/^[^{]/ {
  print "RUNTIME " clip($0, 1000)
  fflush()
  next
}

{
  event_type = string_field($0, "type")
  item_type = ""
  item_at = index($0, "\"item\":{")
  if (item_at)
    item_type = string_field(substr($0, item_at), "type")

  if (event_type == "thread.started") {
    print "THREAD_STARTED id=" string_field($0, "thread_id")
  }
  else if (event_type == "turn.started") {
    print "TURN_STARTED"
  }
  else if (event_type == "turn.completed") {
    usage_at = index($0, "\"usage\":")
    if (usage_at)
      print "TURN_COMPLETED " clip(substr($0, usage_at), 1000)
    else
      print "TURN_COMPLETED"
  }
  else if (event_type ~ /error|failed/) {
    print "ERROR " clip($0, 4000)
  }
  else if (item_type == "command_execution") {
    command = clip(string_field($0, "command"), 1200)
    status = string_field($0, "status")
    code = scalar_field($0, "exit_code")
    if (event_type == "item.started") {
      print "COMMAND_STARTED command=" command
    }
    else {
      print "COMMAND_FINISHED status=" status " exit_code=" code " command=" command
      if (code != "0" && code != "null" && code != "") {
        error_output = string_field($0, "aggregated_output")
        if (error_output != "")
          print "COMMAND_ERROR_OUTPUT " clip(error_output, 4000)
      }
    }
  }
  else if (item_type == "agent_message") {
    print "AGENT_MESSAGE " clip(string_field($0, "text"), 4000)
  }
  else if (item_type != "") {
    print "ITEM event=" event_type " type=" item_type
  }
  else {
    print "EVENT type=" event_type
  }
  fflush()
}
'
pipeline_status=("${PIPESTATUS[@]}")
set -e

command_status=${pipeline_status[0]}
tee_status=${pipeline_status[1]}
filter_status=${pipeline_status[2]}

if command -v gzip >/dev/null 2>&1; then
  gzip -f "$raw_file"
  printf 'RAW_LOG_COMPRESSED path=%s.gz\n' "$raw_file"
else
  printf 'RAW_LOG path=%s\n' "$raw_file"
fi

if [ "$command_status" -ne 0 ]; then
  exit "$command_status"
fi
if [ "$tee_status" -ne 0 ]; then
  exit "$tee_status"
fi
exit "$filter_status"
