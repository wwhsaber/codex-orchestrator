#!/bin/sh
set -eu

result_limit_bytes=16384

usage() {
  printf '%s\n' \
    'Usage:' \
    '  lane-supervisor.sh key --lane NAME --cwd DIR --spec FILE' \
    '  lane-supervisor.sh start --lane NAME --cwd DIR --spec FILE --state-dir DIR [--stdin FILE] -- COMMAND [ARG...]' \
    '  lane-supervisor.sh status --state-dir DIR' \
    '  lane-supervisor.sh result --state-dir DIR'
}

utc_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

read_field() {
  field_name=$1
  field_file=$2
  awk -F= -v key="$field_name" '$1 == key { print substr($0, length(key) + 2); exit }' "$field_file"
}

write_state() {
  state_temp="${state_file}.tmp.$$"
  {
    printf 'version=1\n'
    printf 'state=%s\n' "$lane_state"
    printf 'lane=%s\n' "$lane_name"
    printf 'pid=%s\n' "$lane_pid"
    printf 'launch_label=%s\n' "$launch_label"
    printf 'started_at=%s\n' "$started_at"
    printf 'updated_at=%s\n' "$(utc_now)"
    printf 'cwd=%s\n' "$lane_cwd"
    printf 'spec=%s\n' "$spec_file"
    printf 'log=%s\n' "$log_file"
    printf 'supervisor_log=%s\n' "$supervisor_log_file"
    printf 'result=%s\n' "$result_file"
    printf 'done=%s\n' "$done_file"
    printf 'exit_code=%s\n' "$exit_code"
    printf 'log_bytes=%s\n' "$log_bytes"
    printf 'result_truncated=%s\n' "$result_truncated"
    printf 'message=%s\n' "$state_message"
  } > "$state_temp"
  mv "$state_temp" "$state_file"
}

require_value() {
  option_name=$1
  option_value=${2-}
  if [ -z "$option_value" ]; then
    printf 'Missing value for %s\n' "$option_name" >&2
    exit 2
  fi
}

parse_common() {
  lane_name=
  lane_cwd=
  spec_file=
  state_dir=

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --lane)
        require_value "$1" "${2-}"
        lane_name=$2
        shift 2
        ;;
      --cwd)
        require_value "$1" "${2-}"
        lane_cwd=$2
        shift 2
        ;;
      --spec)
        require_value "$1" "${2-}"
        spec_file=$2
        shift 2
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        exit 2
        ;;
    esac
  done
}

command_key() {
  shift
  parse_common "$@"

  if [ -z "$lane_name" ] || [ -z "$lane_cwd" ] || [ -z "$spec_file" ]; then
    usage >&2
    exit 2
  fi
  if [ ! -f "$spec_file" ]; then
    printf 'Spec file not found: %s\n' "$spec_file" >&2
    exit 2
  fi

  spec_sum=$(cksum < "$spec_file" | awk '{ print $1 "-" $2 }')
  {
    printf '%s\n' "$lane_name"
    printf '%s\n' "$lane_cwd"
    printf '%s\n' "$spec_sum"
  } | cksum | awk '{ print $1 }'
}

command_start() {
  shift

  lane_name=
  lane_cwd=
  spec_file=
  state_dir=
  stdin_file=

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --lane)
        require_value "$1" "${2-}"
        lane_name=$2
        shift 2
        ;;
      --cwd)
        require_value "$1" "${2-}"
        lane_cwd=$2
        shift 2
        ;;
      --spec)
        require_value "$1" "${2-}"
        spec_file=$2
        shift 2
        ;;
      --state-dir)
        require_value "$1" "${2-}"
        state_dir=$2
        shift 2
        ;;
      --stdin)
        require_value "$1" "${2-}"
        stdin_file=$2
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

  if [ -z "$lane_name" ] || [ -z "$lane_cwd" ] || [ -z "$spec_file" ] || [ -z "$state_dir" ] || [ "$#" -eq 0 ]; then
    usage >&2
    exit 2
  fi
  case "$lane_name" in
    *[!A-Za-z0-9._-]*)
      printf 'Lane name may contain only letters, digits, dot, underscore, and hyphen\n' >&2
      exit 2
      ;;
  esac
  if [ ! -d "$lane_cwd" ]; then
    printf 'Working directory not found: %s\n' "$lane_cwd" >&2
    exit 2
  fi
  if [ ! -f "$spec_file" ]; then
    printf 'Spec file not found: %s\n' "$spec_file" >&2
    exit 2
  fi
  if [ -n "$stdin_file" ] && [ ! -f "$stdin_file" ]; then
    printf 'Stdin file not found: %s\n' "$stdin_file" >&2
    exit 2
  fi

  mkdir -p "$state_dir"
  state_file="$state_dir/state"
  log_file="$state_dir/lane.log"
  supervisor_log_file="$state_dir/supervisor.log"
  result_file="$state_dir/result.txt"
  done_file="$state_dir/done"
  launcher_pid_file="$state_dir/launcher.pid"

  if [ -f "$state_file" ]; then
    existing_state=$(read_field state "$state_file")
    existing_pid=$(read_field pid "$state_file")
    if [ "$existing_state" = "starting" ] && [ -f "$launcher_pid_file" ]; then
      existing_pid=$(sed -n '1p' "$launcher_pid_file")
    fi
    if { [ "$existing_state" = "starting" ] || [ "$existing_state" = "running" ]; } \
      && [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
      printf 'ALREADY_RUNNING lane=%s pid=%s state=%s log=%s result=%s\n' \
        "$lane_name" "$existing_pid" "$state_file" "$log_file" "$result_file"
      exit 0
    fi
  fi

  started_at=$(utc_now)
  launch_label=
  if command -v screen >/dev/null 2>&1; then
    label_suffix=$(printf '%s' "$state_dir-$started_at-$$" | cksum | awk '{ print $1 }')
    launch_label="codex-${lane_name}-${label_suffix}"
  fi
  lane_state=starting
  lane_pid=0
  exit_code=
  log_bytes=0
  result_truncated=false
  state_message=
  : > "$log_file"
  : > "$supervisor_log_file"
  : > "$result_file"
  rm -f "$done_file" "$launcher_pid_file"
  write_state

  case "$0" in
    /*) self_path=$0 ;;
    *) self_path=$(cd "$(dirname "$0")" && pwd)/$(basename "$0") ;;
  esac

  if [ -n "$launch_label" ]; then
    set +e
    screen -dmS "$launch_label" /bin/sh "$self_path" _run \
      --lane "$lane_name" \
      --cwd "$lane_cwd" \
      --spec "$spec_file" \
      --state-dir "$state_dir" \
      --stdin "$stdin_file" \
      --started-at "$started_at" \
      --launch-label "$launch_label" \
      -- "$@"
    launch_exit=$?
    set -e
    if [ "$launch_exit" -ne 0 ]; then
      lane_state=failed
      exit_code=$launch_exit
      state_message=launch_failed
      write_state
      : > "$done_file"
      exit "$launch_exit"
    fi

    child_pid=0
    check_count=0
    while [ "$check_count" -lt 20 ]; do
      current_state=$(read_field state "$state_file")
      child_pid=$(read_field pid "$state_file")
      if [ "$current_state" != "starting" ]; then
        break
      fi
      sleep 0.05
      check_count=$((check_count + 1))
    done
  else
    nohup "$self_path" _run \
      --lane "$lane_name" \
      --cwd "$lane_cwd" \
      --spec "$spec_file" \
      --state-dir "$state_dir" \
      --stdin "$stdin_file" \
      --started-at "$started_at" \
      --launch-label "" \
      -- "$@" </dev/null >"$supervisor_log_file" 2>&1 &
    child_pid=$!
    printf '%s\n' "$child_pid" > "$launcher_pid_file"
  fi

  printf 'STARTED lane=%s pid=%s state=%s log=%s result=%s done=%s\n' \
    "$lane_name" "$child_pid" "$state_file" "$log_file" "$result_file" "$done_file"
}

command_run() {
  shift

  lane_name=
  lane_cwd=
  spec_file=
  state_dir=
  stdin_file=
  started_at=
  launch_label=

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --lane) lane_name=$2; shift 2 ;;
      --cwd) lane_cwd=$2; shift 2 ;;
      --spec) spec_file=$2; shift 2 ;;
      --state-dir) state_dir=$2; shift 2 ;;
      --stdin) stdin_file=$2; shift 2 ;;
      --started-at) started_at=$2; shift 2 ;;
      --launch-label) launch_label=$2; shift 2 ;;
      --) shift; break ;;
      *) exit 2 ;;
    esac
  done

  state_file="$state_dir/state"
  log_file="$state_dir/lane.log"
  supervisor_log_file="$state_dir/supervisor.log"
  result_file="$state_dir/result.txt"
  done_file="$state_dir/done"
  lane_state=running
  lane_pid=$$
  exit_code=
  log_bytes=0
  result_truncated=false
  state_message=
  write_state

  if ! cd "$lane_cwd"; then
    lane_state=failed
    exit_code=72
    state_message=working_directory_unavailable
    write_state
    : > "$done_file"
    exit "$exit_code"
  fi

  set +e
  if [ -n "$stdin_file" ]; then
    "$@" < "$stdin_file" > "$log_file" 2>&1
  else
    "$@" > "$log_file" 2>&1
  fi
  command_exit=$?
  set -e

  log_bytes=$(wc -c < "$log_file" | tr -d ' ')
  if [ "$log_bytes" -gt "$result_limit_bytes" ]; then
    tail -c "$result_limit_bytes" "$log_file" > "$result_file"
    result_truncated=true
  else
    cp "$log_file" "$result_file"
    result_truncated=false
  fi

  exit_code=$command_exit
  if [ "$command_exit" -eq 0 ]; then
    lane_state=exited
    state_message=completed
  else
    lane_state=failed
    state_message=command_failed
  fi
  write_state
  : > "$done_file"
  exit "$command_exit"
}

command_status() {
  shift
  if [ "${1-}" != "--state-dir" ] || [ -z "${2-}" ]; then
    usage >&2
    exit 2
  fi
  state_file=$2/state
  launcher_pid_file=$2/launcher.pid
  if [ ! -f "$state_file" ]; then
    printf 'MISSING state=%s\n' "$state_file"
    exit 1
  fi
  cat "$state_file"
  lane_state=$(read_field state "$state_file")
  lane_pid=$(read_field pid "$state_file")
  if [ "$lane_state" = "starting" ] && [ -f "$launcher_pid_file" ]; then
    lane_pid=$(sed -n '1p' "$launcher_pid_file")
  fi
  if { [ "$lane_state" = "starting" ] || [ "$lane_state" = "running" ]; } \
    && ! kill -0 "$lane_pid" 2>/dev/null; then
    printf 'observed_state=process_missing\n'
  fi
}

command_result() {
  shift
  if [ "${1-}" != "--state-dir" ] || [ -z "${2-}" ]; then
    usage >&2
    exit 2
  fi
  state_file=$2/state
  result_file=$2/result.txt
  if [ ! -f "$state_file" ] || [ ! -f "$result_file" ]; then
    printf 'Result is not available\n' >&2
    exit 1
  fi
  lane_state=$(read_field state "$state_file")
  case "$lane_state" in
    exited|failed) cat "$result_file" ;;
    *)
      printf 'Result is not ready; state=%s\n' "$lane_state" >&2
      exit 1
      ;;
  esac
}

case "${1-}" in
  key) command_key "$@" ;;
  start) command_start "$@" ;;
  status) command_status "$@" ;;
  result) command_result "$@" ;;
  _run) command_run "$@" ;;
  *) usage >&2; exit 2 ;;
esac
