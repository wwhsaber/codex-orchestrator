#!/bin/sh
set -eu

result_limit_bytes=16384
spec_limit_bytes=16384
diagnostic_retention_days=7

usage() {
  printf '%s\n' \
    'Usage:' \
    '  lane-supervisor.sh check-spec --spec FILE' \
    '  lane-supervisor.sh key --lane NAME --cwd DIR --spec FILE' \
    '  lane-supervisor.sh start --lane NAME --cwd DIR --spec FILE --state-dir DIR [--title TEXT] [--model-label TEXT] [--mode read|write] [--stdin FILE] [--result-source FILE] [--ephemeral-watch] -- COMMAND [ARG...]' \
    '  lane-supervisor.sh await --state-dir DIR' \
    '  lane-supervisor.sh status --state-dir DIR' \
    '  lane-supervisor.sh stop --state-dir DIR' \
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
    printf 'version=3\n'
    printf 'task_id=%s\n' "$task_id"
    printf 'title=%s\n' "$task_title"
    printf 'state=%s\n' "$lane_state"
    printf 'lane=%s\n' "$lane_name"
    printf 'model=%s\n' "$model_label"
    printf 'mode=%s\n' "$lane_mode"
    printf 'pid=%s\n' "$lane_pid"
    printf 'launch_label=%s\n' "$launch_label"
    printf 'controller=%s\n' "$controller_path"
    printf 'started_at=%s\n' "$started_at"
    printf 'updated_at=%s\n' "$(utc_now)"
    printf 'cwd=%s\n' "$lane_cwd"
    printf 'spec=%s\n' "$spec_file"
    printf 'log=%s\n' "$log_file"
    printf 'supervisor_log=%s\n' "$supervisor_log_file"
    printf 'result=%s\n' "$result_file"
    printf 'result_source=%s\n' "$result_source_file"
    printf 'ephemeral_watch=%s\n' "$ephemeral_watch"
    printf 'diagnostic=%s\n' "$diagnostic_file"
    printf 'done=%s\n' "$done_file"
    printf 'exit_code=%s\n' "$exit_code"
    printf 'log_bytes=%s\n' "$log_bytes"
    printf 'result_truncated=%s\n' "$result_truncated"
    printf 'message=%s\n' "$state_message"
  } > "$state_temp"
  mv "$state_temp" "$state_file"
}

task_process_matches() {
  checked_pid=$1
  checked_task_id=$2
  case "$checked_pid" in
    ''|0|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$checked_pid" 2>/dev/null || return 1
  process_command=$(ps -p "$checked_pid" -o command= 2>/dev/null || true)
  case "$process_command" in
    *"_run"*"$checked_task_id"*) return 0 ;;
    *) return 1 ;;
  esac
}

finish_output_files() {
  if [ "$ephemeral_watch" != "true" ]; then
    return
  fi
  diagnostic_temp="${diagnostic_file}.tmp"
  if [ "$lane_state" = "interrupted" ] && [ -f "$diagnostic_temp" ] \
    && [ ! -f "$diagnostic_file" ]; then
    mv "$diagnostic_temp" "$diagnostic_file"
  else
    rm -f "$diagnostic_temp"
  fi
  rm -f "$log_file"
  if [ -n "$result_source_file" ] && [ "$result_source_file" != "$result_file" ]; then
    rm -f "$result_source_file"
  fi
  case "$lane_state" in
    exited|cancelled) rm -f "$supervisor_log_file" ;;
  esac
}

clean_old_diagnostics() {
  state_root_dir=$1
  find "$state_root_dir" -mindepth 2 -maxdepth 2 \
    \( -name diagnostic.log -o -name diagnostic.log.tmp \) \
    -type f -mtime "+$diagnostic_retention_days" -delete 2>/dev/null || true
}

finish_missing_process() {
  state_dir=$1
  state_file="$state_dir/state"
  task_id=$(read_field task_id "$state_file")
  [ -n "$task_id" ] || task_id=$(basename "$state_dir")
  task_title=$(read_field title "$state_file")
  lane_name=$(read_field lane "$state_file")
  model_label=$(read_field model "$state_file")
  lane_mode=$(read_field mode "$state_file")
  lane_pid=$(read_field pid "$state_file")
  launch_label=$(read_field launch_label "$state_file")
  controller_path=$(read_field controller "$state_file")
  [ -n "$controller_path" ] || controller_path=$0
  started_at=$(read_field started_at "$state_file")
  lane_cwd=$(read_field cwd "$state_file")
  spec_file=$(read_field spec "$state_file")
  log_file=$(read_field log "$state_file")
  [ -n "$log_file" ] || log_file="$state_dir/lane.log"
  supervisor_log_file=$(read_field supervisor_log "$state_file")
  [ -n "$supervisor_log_file" ] || supervisor_log_file="$state_dir/supervisor.log"
  result_file=$(read_field result "$state_file")
  [ -n "$result_file" ] || result_file="$state_dir/result.txt"
  result_source_file=$(read_field result_source "$state_file")
  ephemeral_watch=$(read_field ephemeral_watch "$state_file")
  [ -n "$ephemeral_watch" ] || ephemeral_watch=false
  diagnostic_file=$(read_field diagnostic "$state_file")
  [ -n "$diagnostic_file" ] || diagnostic_file="$state_dir/diagnostic.log"
  done_file=$(read_field "done" "$state_file")
  [ -n "$done_file" ] || done_file="$state_dir/done"

  log_bytes=0
  result_truncated=false
  if [ "$ephemeral_watch" = "true" ] && { [ -z "$result_source_file" ] \
    || [ ! -s "$result_source_file" ]; }; then
    printf '%s\n' 'STATUS: interrupted' 'The agent process ended before emitting a final response.' \
      > "$result_file"
    lane_state=interrupted
    exit_code=125
    state_message=process_missing
    write_state
    : > "$done_file"
    finish_output_files
    return
  fi
  selected_result_file=$log_file
  if [ -n "$result_source_file" ] && [ -s "$result_source_file" ]; then
    selected_result_file=$result_source_file
  fi
  if [ -f "$selected_result_file" ]; then
    if [ -f "$log_file" ]; then
      log_bytes=$(wc -c < "$log_file" | tr -d ' ')
    fi
    selected_result_bytes=$(wc -c < "$selected_result_file" | tr -d ' ')
    if [ "$selected_result_bytes" -gt "$result_limit_bytes" ]; then
      tail -c "$result_limit_bytes" "$selected_result_file" > "$result_file"
      result_truncated=true
    else
      cp "$selected_result_file" "$result_file"
    fi
  else
    : > "$result_file"
  fi

  lane_state=interrupted
  exit_code=125
  state_message=process_missing
  write_state
  : > "$done_file"
  finish_output_files
}

require_value() {
  option_name=$1
  option_value=${2-}
  if [ -z "$option_value" ]; then
    printf 'Missing value for %s\n' "$option_name" >&2
    exit 2
  fi
}

single_line() {
  printf '%s' "$1" | tr '\r\n' '  '
}

check_spec_size() {
  checked_spec_file=$1
  spec_bytes=$(wc -c < "$checked_spec_file" | tr -d ' ')
  if [ "$spec_bytes" -gt "$spec_limit_bytes" ]; then
    printf 'Spec exceeds %s-byte limit: bytes=%s path=%s\n' \
      "$spec_limit_bytes" "$spec_bytes" "$checked_spec_file" >&2
    exit 2
  fi
}

command_check_spec() {
  shift
  if [ "${1-}" != "--spec" ] || [ -z "${2-}" ] || [ "$#" -ne 2 ]; then
    usage >&2
    exit 2
  fi
  spec_file=$2
  if [ ! -f "$spec_file" ]; then
    printf 'Spec file not found: %s\n' "$spec_file" >&2
    exit 2
  fi
  check_spec_size "$spec_file"
  printf 'SPEC_OK bytes=%s limit=%s path=%s\n' \
    "$spec_bytes" "$spec_limit_bytes" "$spec_file"
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
  check_spec_size "$spec_file"

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
  result_source_file=
  ephemeral_watch=false
  task_title=
  model_label=
  lane_mode=

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
      --title)
        require_value "$1" "${2-}"
        task_title=$(single_line "$2")
        shift 2
        ;;
      --model-label)
        require_value "$1" "${2-}"
        model_label=$(single_line "$2")
        shift 2
        ;;
      --mode)
        require_value "$1" "${2-}"
        lane_mode=$2
        shift 2
        ;;
      --stdin)
        require_value "$1" "${2-}"
        stdin_file=$2
        shift 2
        ;;
      --result-source)
        require_value "$1" "${2-}"
        result_source_file=$2
        shift 2
        ;;
      --ephemeral-watch)
        ephemeral_watch=true
        shift
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
  case "$lane_mode" in
    ''|read|write) ;;
    *)
      printf 'Mode must be read or write\n' >&2
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
  check_spec_size "$spec_file"
  if [ -n "$stdin_file" ] && [ ! -f "$stdin_file" ]; then
    printf 'Stdin file not found: %s\n' "$stdin_file" >&2
    exit 2
  fi

  mkdir -p "$state_dir"
  state_file="$state_dir/state"
  log_file="$state_dir/lane.log"
  supervisor_log_file="$state_dir/supervisor.log"
  result_file="$state_dir/result.txt"
  diagnostic_file="$state_dir/diagnostic.log"
  done_file="$state_dir/done"
  launcher_pid_file="$state_dir/launcher.pid"
  stop_marker_file="$state_dir/stop-requested"
  task_id=$(basename "$state_dir")
  clean_old_diagnostics "$(dirname "$state_dir")"

  case "$0" in
    /*) controller_path=$0 ;;
    *) controller_path=$(cd "$(dirname "$0")" && pwd)/$(basename "$0") ;;
  esac

  if [ -f "$state_file" ]; then
    existing_state=$(read_field state "$state_file")
    existing_pid=$(read_field pid "$state_file")
    if [ "$existing_state" = "starting" ] && [ -f "$launcher_pid_file" ]; then
      existing_pid=$(sed -n '1p' "$launcher_pid_file")
    fi
    if { [ "$existing_state" = "starting" ] || [ "$existing_state" = "running" ]; } \
      && task_process_matches "$existing_pid" "$task_id"; then
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
  rm -f "$diagnostic_file" "${diagnostic_file}.tmp"
  if [ -n "$result_source_file" ]; then
    mkdir -p "$(dirname "$result_source_file")"
    : > "$result_source_file"
  fi
  rm -f "$done_file" "$launcher_pid_file" "$stop_marker_file"
  write_state

  self_path=$controller_path

  if [ -n "$launch_label" ]; then
    set +e
    screen -dmS "$launch_label" /bin/sh "$self_path" _run \
      --lane "$lane_name" \
      --cwd "$lane_cwd" \
      --spec "$spec_file" \
      --state-dir "$state_dir" \
      --stdin "$stdin_file" \
      --result-source "$result_source_file" \
      --ephemeral-watch "$ephemeral_watch" \
      --title "$task_title" \
      --model-label "$model_label" \
      --mode "$lane_mode" \
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
      finish_output_files
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
      --result-source "$result_source_file" \
      --ephemeral-watch "$ephemeral_watch" \
      --title "$task_title" \
      --model-label "$model_label" \
      --mode "$lane_mode" \
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
  result_source_file=
  ephemeral_watch=false
  started_at=
  launch_label=
  task_title=
  model_label=
  lane_mode=

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --lane) lane_name=$2; shift 2 ;;
      --cwd) lane_cwd=$2; shift 2 ;;
      --spec) spec_file=$2; shift 2 ;;
      --state-dir) state_dir=$2; shift 2 ;;
      --stdin) stdin_file=$2; shift 2 ;;
      --result-source) result_source_file=$2; shift 2 ;;
      --ephemeral-watch) ephemeral_watch=$2; shift 2 ;;
      --title) task_title=$2; shift 2 ;;
      --model-label) model_label=$2; shift 2 ;;
      --mode) lane_mode=$2; shift 2 ;;
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
  diagnostic_file="$state_dir/diagnostic.log"
  done_file="$state_dir/done"
  stop_marker_file="$state_dir/stop-requested"
  task_id=$(basename "$state_dir")
  case "$0" in
    /*) controller_path=$0 ;;
    *) controller_path=$(cd "$(dirname "$0")" && pwd)/$(basename "$0") ;;
  esac
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
    printf '%s\n' 'STATUS: failed' 'The lane working directory is unavailable.' > "$result_file"
    write_state
    : > "$done_file"
    finish_output_files
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
  if [ "$ephemeral_watch" = "true" ] && { [ -z "$result_source_file" ] \
    || [ ! -s "$result_source_file" ]; }; then
    if [ "$command_exit" -eq 0 ]; then
      printf '%s\n' 'STATUS: completed' 'The agent emitted no final response.' > "$result_file"
    else
      printf 'STATUS: failed\nAgent process ended with code %s before emitting a final response.\n' \
        "$command_exit" > "$result_file"
    fi
    selected_result_file=$result_file
  else
    selected_result_file=$log_file
    if [ -n "$result_source_file" ] && [ -s "$result_source_file" ]; then
      selected_result_file=$result_source_file
    fi
  fi
  selected_result_bytes=$(wc -c < "$selected_result_file" | tr -d ' ')
  if [ "$selected_result_file" = "$result_file" ]; then
    result_truncated=false
  elif [ "$selected_result_bytes" -gt "$result_limit_bytes" ]; then
    tail -c "$result_limit_bytes" "$selected_result_file" > "$result_file"
    result_truncated=true
  else
    cp "$selected_result_file" "$result_file"
    result_truncated=false
  fi

  exit_code=$command_exit
  if [ -f "$stop_marker_file" ]; then
    lane_state=cancelled
    exit_code=130
    state_message=user_stopped
  elif [ "$command_exit" -eq 0 ]; then
    lane_state=exited
    state_message=completed
  else
    lane_state=failed
    state_message=command_failed
  fi
  write_state
  : > "$done_file"
  finish_output_files
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
  done_file=$2/done
  if [ ! -f "$state_file" ]; then
    printf 'MISSING state=%s\n' "$state_file"
    exit 1
  fi
  lane_state=$(read_field state "$state_file")
  saved_done_file=$(read_field "done" "$state_file")
  [ -n "$saved_done_file" ] && done_file=$saved_done_file
  case "$lane_state" in
    exited|failed|cancelled|interrupted)
      [ -f "$done_file" ] || : > "$done_file"
      ;;
  esac
  lane_pid=$(read_field pid "$state_file")
  task_id=$(read_field task_id "$state_file")
  [ -n "$task_id" ] || task_id=$(basename "$2")
  if [ "$lane_state" = "starting" ] && [ -f "$launcher_pid_file" ]; then
    lane_pid=$(sed -n '1p' "$launcher_pid_file")
  fi
  if [ "$lane_state" = "running" ] || [ "$lane_state" = "starting" ]; then
    case "$lane_pid" in
      ''|0|*[!0-9]*)
        if [ "$lane_state" = "running" ]; then
          finish_missing_process "$2"
        fi
        ;;
      *)
        if ! task_process_matches "$lane_pid" "$task_id"; then
          finish_missing_process "$2"
        fi
        ;;
    esac
  fi
  cat "$state_file"
}

command_await() {
  shift
  if [ "${1-}" != "--state-dir" ] || [ -z "${2-}" ]; then
    usage >&2
    exit 2
  fi

  state_dir=$2
  state_file=$state_dir/state
  result_file=$state_dir/result.txt
  done_file=$state_dir/done
  launcher_pid_file=$state_dir/launcher.pid

  if [ ! -f "$state_file" ]; then
    printf 'MISSING state=%s\n' "$state_file" >&2
    exit 1
  fi
  task_id=$(read_field task_id "$state_file")
  [ -n "$task_id" ] || task_id=$(basename "$state_dir")

  empty_pid_checks=0
  while [ ! -f "$done_file" ]; do
    lane_state=$(read_field state "$state_file")
    lane_pid=$(read_field pid "$state_file")
    if [ "$lane_state" = "starting" ] && [ -f "$launcher_pid_file" ]; then
      lane_pid=$(sed -n '1p' "$launcher_pid_file")
    fi

    case "$lane_state" in
      exited|failed|cancelled|interrupted)
        : > "$done_file"
        continue
        ;;
    esac

    case "$lane_state:$lane_pid" in
      starting:0|running:0|starting:|running:|starting:*[!0-9]*|running:*[!0-9]*)
        empty_pid_checks=$((empty_pid_checks + 1))
        if [ "$empty_pid_checks" -ge 5 ]; then
          finish_missing_process "$state_dir"
          continue
        fi
        ;;
      starting:*|running:*)
        if ! task_process_matches "$lane_pid" "$task_id"; then
          finish_missing_process "$state_dir"
          continue
        fi
        ;;
    esac
    sleep 2
  done

  printf 'AWAIT_COMPLETE\n'
  cat "$state_file"
  printf '%s\n' '--- result ---'
  if [ -f "$result_file" ]; then
    cat "$result_file"
  fi
}

stop_tree() {
  stop_pid=$1
  stop_signal=$2
  for child_pid in $(pgrep -P "$stop_pid" 2>/dev/null || true); do
    stop_tree "$child_pid" "$stop_signal"
  done
  kill "-$stop_signal" "$stop_pid" 2>/dev/null || true
}

command_stop() {
  shift
  if [ "${1-}" != "--state-dir" ] || [ -z "${2-}" ] || [ "$#" -ne 2 ]; then
    usage >&2
    exit 2
  fi

  state_dir=$2
  state_file="$state_dir/state"
  launcher_pid_file="$state_dir/launcher.pid"
  stop_marker_file="$state_dir/stop-requested"
  if [ ! -f "$state_file" ]; then
    printf 'MISSING state=%s\n' "$state_file" >&2
    exit 1
  fi

  lane_state=$(read_field state "$state_file")
  case "$lane_state" in
    exited|failed|cancelled|interrupted)
      printf 'ALREADY_TERMINAL state=%s path=%s\n' "$lane_state" "$state_file"
      exit 0
      ;;
  esac
  if [ -f "$state_dir/done" ]; then
    terminal_state=$(read_field state "$state_file")
    printf 'ALREADY_TERMINAL state=%s path=%s\n' "$terminal_state" "$state_file"
    exit 0
  fi

  task_id=$(read_field task_id "$state_file")
  [ -n "$task_id" ] || task_id=$(basename "$state_dir")
  task_title=$(read_field title "$state_file")
  lane_name=$(read_field lane "$state_file")
  model_label=$(read_field model "$state_file")
  lane_mode=$(read_field mode "$state_file")
  lane_pid=$(read_field pid "$state_file")
  launch_label=$(read_field launch_label "$state_file")
  controller_path=$(read_field controller "$state_file")
  [ -n "$controller_path" ] || controller_path=$0
  started_at=$(read_field started_at "$state_file")
  lane_cwd=$(read_field cwd "$state_file")
  spec_file=$(read_field spec "$state_file")
  log_file=$(read_field log "$state_file")
  supervisor_log_file=$(read_field supervisor_log "$state_file")
  result_file=$(read_field result "$state_file")
  result_source_file=$(read_field result_source "$state_file")
  ephemeral_watch=$(read_field ephemeral_watch "$state_file")
  [ -n "$ephemeral_watch" ] || ephemeral_watch=false
  diagnostic_file=$(read_field diagnostic "$state_file")
  [ -n "$diagnostic_file" ] || diagnostic_file="$state_dir/diagnostic.log"
  done_file=$(read_field "done" "$state_file")
  [ -n "$done_file" ] || done_file="$state_dir/done"
  : > "$stop_marker_file"

  if [ "$lane_state" = "starting" ] && [ -f "$launcher_pid_file" ]; then
    lane_pid=$(sed -n '1p' "$launcher_pid_file")
  fi

  if { [ "$lane_state" = "starting" ] || [ "$lane_state" = "running" ]; } \
    && ! task_process_matches "$lane_pid" "$task_id"; then
    finish_missing_process "$state_dir"
    printf 'INTERRUPTED lane=%s pid=%s state=%s result=%s\n' \
      "$lane_name" "$lane_pid" "$state_file" "$result_file"
    exit 0
  fi

  if [ -n "$launch_label" ] && command -v screen >/dev/null 2>&1; then
    screen -S "$launch_label" -X quit >/dev/null 2>&1 || true
  elif [ -n "$lane_pid" ] && [ "$lane_pid" -gt 0 ] 2>/dev/null; then
    stop_tree "$lane_pid" TERM
  fi

  wait_count=0
  while [ -n "$lane_pid" ] && [ "$lane_pid" -gt 0 ] 2>/dev/null \
    && kill -0 "$lane_pid" 2>/dev/null && [ "$wait_count" -lt 20 ]; do
    sleep 0.1
    wait_count=$((wait_count + 1))
  done
  if [ -n "$lane_pid" ] && [ "$lane_pid" -gt 0 ] 2>/dev/null \
    && kill -0 "$lane_pid" 2>/dev/null; then
    stop_tree "$lane_pid" KILL
  fi

  log_bytes=0
  result_truncated=false
  if [ "$ephemeral_watch" = "true" ] && { [ -z "$result_source_file" ] \
    || [ ! -s "$result_source_file" ]; }; then
    printf '%s\n' 'STATUS: cancelled' 'The agent was stopped before emitting a final response.' \
      > "$result_file"
    selected_result_file=$result_file
  else
    selected_result_file=$log_file
    if [ -n "$result_source_file" ] && [ -s "$result_source_file" ]; then
      selected_result_file=$result_source_file
    fi
  fi
  if [ -f "$selected_result_file" ]; then
    if [ -f "$log_file" ]; then
      log_bytes=$(wc -c < "$log_file" | tr -d ' ')
    fi
    selected_result_bytes=$(wc -c < "$selected_result_file" | tr -d ' ')
    if [ "$selected_result_file" = "$result_file" ]; then
      result_truncated=false
    elif [ "$selected_result_bytes" -gt "$result_limit_bytes" ]; then
      tail -c "$result_limit_bytes" "$selected_result_file" > "$result_file"
      result_truncated=true
    else
      cp "$selected_result_file" "$result_file"
    fi
  else
    : > "$result_file"
  fi

  lane_state=cancelled
  exit_code=130
  state_message=user_stopped
  write_state
  : > "$done_file"
  finish_output_files
  printf 'STOPPED lane=%s pid=%s state=%s result=%s\n' \
    "$lane_name" "$lane_pid" "$state_file" "$result_file"
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
    exited|failed|cancelled|interrupted) cat "$result_file" ;;
    *)
      printf 'Result is not ready; state=%s\n' "$lane_state" >&2
      exit 1
      ;;
  esac
}

case "${1-}" in
  check-spec) command_check_spec "$@" ;;
  key) command_key "$@" ;;
  start) command_start "$@" ;;
  await) command_await "$@" ;;
  status) command_status "$@" ;;
  stop) command_stop "$@" ;;
  result) command_result "$@" ;;
  _run) command_run "$@" ;;
  *) usage >&2; exit 2 ;;
esac
