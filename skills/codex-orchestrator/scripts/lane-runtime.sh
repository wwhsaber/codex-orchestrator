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

requested_runtime=${CODEX_ORCHESTRATOR_RUNTIME:-auto}
action=${1-}
selected_runtime=

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
    herdr|supervisor) selected_runtime=$requested_runtime ;;
    *)
      printf 'CODEX_ORCHESTRATOR_RUNTIME must be auto, herdr, or supervisor\n' >&2
      exit 2
      ;;
  esac
fi

case "$selected_runtime" in
  herdr) exec node "$herdr_lane" "$@" ;;
  supervisor) exec "$supervisor" "$@" ;;
  *)
    printf 'Unknown lane runtime in state: %s\n' "$selected_runtime" >&2
    exit 2
    ;;
esac
