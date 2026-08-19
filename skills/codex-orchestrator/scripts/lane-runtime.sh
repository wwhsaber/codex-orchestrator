#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
supervisor="$script_dir/lane-supervisor.sh"
herdr_lane="$script_dir/herdr-lane.mjs"

read_runtime() {
  state_dir=$1
  state_file="$state_dir/state"
  if [ -f "$state_file" ]; then
    awk -F= '$1 == "runtime" { print substr($0, 9); exit }' "$state_file"
  fi
}

herdr_ready() {
  command -v herdr >/dev/null 2>&1 || return 1
  herdr status server 2>/dev/null | grep -q '^status: running$'
}

state_root() {
  if [ -n "${CODEX_ORCHESTRATOR_STATE_ROOT-}" ]; then
    root=$CODEX_ORCHESTRATOR_STATE_ROOT
  else
    temp_root=${TMPDIR:-/tmp}
    root="${temp_root%/}/codex-orchestrator"
  fi
  printf '%s\n' "${root%/}"
}

task_key_for() {
  "$supervisor" key "$@"
}

state_dir_for() {
  task_key=$(task_key_for "$@")
  root=$(state_root)
  printf '%s/%s\n' "${root%/}" "$task_key"
}

check_start_state_dir() {
  lane_name=
  lane_cwd=
  spec_file=
  supplied_state_dir=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --lane) lane_name=${2-}; shift 2 ;;
      --cwd) lane_cwd=${2-}; shift 2 ;;
      --spec) spec_file=${2-}; shift 2 ;;
      --state-dir) supplied_state_dir=${2-}; shift 2 ;;
      --) break ;;
      *) shift ;;
    esac
  done
  if [ -z "$lane_name" ] || [ -z "$lane_cwd" ] || [ -z "$spec_file" ] \
    || [ -z "$supplied_state_dir" ]; then
    return
  fi
  expected_state_dir=$(state_dir_for \
    --lane "$lane_name" --cwd "$lane_cwd" --spec "$spec_file")
  if [ "$supplied_state_dir" != "$expected_state_dir" ]; then
    printf 'State directory must come from lane-runtime.sh state-dir\n' >&2
    printf 'Expected: %s\nReceived: %s\n' \
      "$expected_state_dir" "$supplied_state_dir" >&2
    exit 2
  fi
}

requested_runtime=${CODEX_ORCHESTRATOR_RUNTIME:-auto}
action=${1-}
selected_runtime=

if [ "$action" = "producer-session" ]; then
  if [ "${2-}" != "--task-id" ] || [ -z "${3-}" ] || [ "$#" -ne 3 ]; then
    printf 'Usage: lane-runtime.sh producer-session --task-id ID\n' >&2
    exit 2
  fi
  task_id=$3
  case "$task_id" in
    *[!A-Za-z0-9._-]*)
      printf 'Invalid task ID: %s\n' "$task_id" >&2
      exit 2
      ;;
  esac
  state_file="$(state_root)/$task_id/state"
  if [ ! -f "$state_file" ]; then
    printf 'Task state not found: %s\n' "$task_id" >&2
    exit 1
  fi
  session_id=$(awk -F= '$1 == "producer_session_id" { print substr($0, 21); exit }' "$state_file")
  if [ -z "$session_id" ]; then
    printf 'Task has no producer session ID: %s\n' "$task_id" >&2
    exit 1
  fi
  printf '%s\n' "$session_id"
  exit 0
fi

case "$action" in
  await|status|stop|result)
    if [ "${2-}" = "--state-dir" ] && [ -n "${3-}" ]; then
      selected_runtime=$(read_runtime "$3")
    fi
    ;;
esac

if [ -z "$selected_runtime" ]; then
  case "$requested_runtime" in
    auto)
      if herdr_ready; then selected_runtime=herdr; else selected_runtime=supervisor; fi
      ;;
    herdr) selected_runtime=herdr ;;
    supervisor)
      if herdr_ready; then
        case "${CODEX_ORCHESTRATOR_SUPERVISOR_REASON-}" in
          user_requested|herdr_launch_failed) ;;
          *)
            printf '%s\n' \
              'Herdr is ready; explicit supervisor mode requires CODEX_ORCHESTRATOR_SUPERVISOR_REASON=user_requested or herdr_launch_failed' >&2
            exit 2
            ;;
        esac
      fi
      selected_runtime=supervisor
      ;;
    *)
      printf 'CODEX_ORCHESTRATOR_RUNTIME must be auto, herdr, or supervisor\n' >&2
      exit 2
      ;;
  esac
fi

if [ "$action" = "key" ]; then
  shift
  task_key_for "$@"
  exit 0
fi

if [ "$action" = "state-dir" ]; then
  shift
  state_dir_for "$@"
  exit 0
fi

if [ "$action" = "start" ]; then
  shift
  check_start_state_dir "$@"
  set -- start "$@"
fi

case "$selected_runtime" in
  herdr) exec node "$herdr_lane" "$@" ;;
  supervisor) exec env CODEX_ORCHESTRATOR_SELECTOR_ACTIVE=1 "$supervisor" "$@" ;;
  *)
    printf 'Unknown lane runtime in state: %s\n' "$selected_runtime" >&2
    exit 2
    ;;
esac
