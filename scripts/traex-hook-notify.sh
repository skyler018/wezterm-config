#!/bin/sh
set -eu

event="${1:-notification}"
cwd="$(pwd -P 2>/dev/null || pwd)"
cwd_hash="$(printf '%s' "$cwd" | shasum | awk '{print $1}')"
tmp_root="${TMPDIR:-/tmp}"
state_dir="${TMUX_AGENT_STATE_DIR:-${tmp_root%/}/tmux-agent-state}"
state_file="${state_dir}/traex-${cwd_hash}.env"
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"

if [ -r "$state_file" ]; then
  export TMUX_AGENT_STATE_FILE="$state_file"
fi

exec "${script_dir}/ai-notify.sh" "$event" traex
