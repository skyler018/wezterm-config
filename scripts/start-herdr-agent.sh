#!/bin/sh

set -u

if [ "$#" -lt 5 ]; then
  echo "usage: start-herdr-agent.sh <herdr> <kind> <name> <pane_id> <timeout_ms> [agent args...]" >&2
  exit 2
fi

if [ "${WEZTERM_HERDR_AGENT_WORKER:-}" != 1 ]; then
  WEZTERM_HERDR_AGENT_WORKER=1 /bin/sh "$0" "$@" >/dev/null 2>&1 &
  exit 0
fi

herdr_path=$1
agent_kind=$2
agent_name=$3
pane_id=$4
timeout_ms=$5
shift 5

timeout_sec=$(( (timeout_ms + 999) / 1000 ))
deadline=$(( $(date +%s) + timeout_sec ))
log_file="${TMPDIR:-/tmp}/wezterm-herdr-agent-start-${agent_name}.log"

while :; do
  if [ "$#" -gt 0 ]; then
    output=$("$herdr_path" agent start "$agent_name" --kind "$agent_kind" --pane "$pane_id" --timeout "$timeout_ms" -- "$@" 2>&1)
    status=$?
  else
    output=$("$herdr_path" agent start "$agent_name" --kind "$agent_kind" --pane "$pane_id" --timeout "$timeout_ms" 2>&1)
    status=$?
  fi

  printf '%s\n' "$output" >>"$log_file"

  if printf '%s\n' "$output" | grep -q '"type":"agent_started"'; then
    exit 0
  fi

  if printf '%s\n' "$output" | grep -q '"code":"agent_pane_busy"'; then
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "timed out waiting for pane shell to become available: $pane_id" >>"$log_file"
      exit 1
    fi
    sleep 0.5
    continue
  fi

  exit "$status"
done
