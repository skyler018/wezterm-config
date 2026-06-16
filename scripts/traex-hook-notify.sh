#!/bin/sh
set -eu

event="${1:-notification}"
cwd="$(pwd -P 2>/dev/null || pwd)"
cwd_hash="$(printf '%s' "$cwd" | shasum | awk '{print $1}')"
state_file="/tmp/tmux-agent-state/traex-${cwd_hash}.env"

if [ -r "$state_file" ]; then
  export TMUX_AGENT_STATE_FILE="$state_file"
fi

exec "/Users/bytedance/.config/wezterm/scripts/ai-notify.sh" "$event" traex
