#!/bin/sh
set -eu

event="${1:-notification}"
agent_hint="${2:-}"
state_file="${TMUX_AGENT_STATE_FILE:-}"

resolve_state_file() {
  if [ -n "$state_file" ] && [ -r "$state_file" ]; then
    printf '%s\n' "$state_file"
    return 0
  fi

  if [ -z "$agent_hint" ]; then
    return 1
  fi

  current_cwd="$(pwd -P 2>/dev/null || pwd || true)"
  if [ -z "$current_cwd" ]; then
    return 1
  fi

  state_dir="/tmp/tmux-agent-state"
  cwd_hash="$(printf '%s' "$current_cwd" | shasum | awk '{print $1}')"
  candidate="${state_dir}/${agent_hint}-${cwd_hash}.env"
  if [ -r "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  return 1
}

state_file="$(resolve_state_file || true)"
if [ -n "$state_file" ] && [ -r "$state_file" ]; then
  # shellcheck disable=SC1090
  . "$state_file"
fi

if [ -z "$agent_hint" ] && [ -n "${TMUX_AGENT_NAME:-}" ]; then
  agent_hint="$TMUX_AGENT_NAME"
fi

get_current_tty() {
  tty_path="$(ps -o tty= -p "$$" 2>/dev/null | tr -d ' ' || true)"
  case "$tty_path" in
    ""|"?"|"??")
      return 1
      ;;
    /dev/*)
      printf '%s\n' "$tty_path"
      return 0
      ;;
    *)
      printf '/dev/%s\n' "$tty_path"
      return 0
      ;;
  esac
}

find_pane_by_ancestor_pid() {
  pane_info="$(tmux list-panes -a -F '#{pane_id} #{pane_pid}' 2>/dev/null || true)"
  if [ -z "$pane_info" ]; then
    return 1
  fi

  current_pid="$$"
  while [ -n "$current_pid" ] && [ "$current_pid" -gt 1 ] 2>/dev/null; do
    pane_from_pid="$(
      printf '%s\n' "$pane_info" | awk -v pid="$current_pid" '$2 == pid { print $1; exit }'
    )"
    if [ -n "$pane_from_pid" ]; then
      printf '%s\n' "$pane_from_pid"
      return 0
    fi

    current_pid="$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ' || true)"
  done

  return 1
}

find_pane_by_agent_and_cwd() {
  if [ -z "$agent_hint" ]; then
    return 1
  fi

  current_cwd="${TMUX_AGENT_CWD:-}"
  if [ -z "$current_cwd" ]; then
    current_cwd="$(pwd -P 2>/dev/null || pwd || true)"
  fi
  if [ -z "$current_cwd" ]; then
    return 1
  fi

  pane_from_agent_cwd="$(
    tmux list-panes -a -F '#{pane_id} #{@agent_name} #{pane_current_path}' 2>/dev/null \
      | awk -v agent="$agent_hint" -v cwd="$current_cwd" '$2 == agent && $3 == cwd { print $1; exit }'
  )"
  if [ -n "$pane_from_agent_cwd" ]; then
    printf '%s\n' "$pane_from_agent_cwd"
    return 0
  fi

  pane_from_agent="$(
    tmux list-panes -a -F '#{pane_id} #{@agent_name}' 2>/dev/null \
      | awk -v agent="$agent_hint" '$2 == agent { print $1; exit }'
  )"
  if [ -n "$pane_from_agent" ]; then
    printf '%s\n' "$pane_from_agent"
    return 0
  fi

  return 1
}

find_tmux_pane() {
  if [ -n "${TMUX_AGENT_PANE:-}" ]; then
    printf '%s\n' "${TMUX_AGENT_PANE}"
    return 0
  fi

  if [ -n "${TMUX_PANE:-}" ]; then
    printf '%s\n' "${TMUX_PANE}"
    return 0
  fi

  current_tty="$(get_current_tty || true)"
  if [ -n "$current_tty" ]; then
    pane_from_tty="$(tmux list-panes -a -F '#{pane_id} #{pane_tty}' 2>/dev/null | awk -v tty="$current_tty" '$2 == tty { print $1; exit }')"
    if [ -n "$pane_from_tty" ]; then
      printf '%s\n' "$pane_from_tty"
      return 0
    fi
  fi

  pane_from_pid="$(find_pane_by_ancestor_pid || true)"
  if [ -n "$pane_from_pid" ]; then
    printf '%s\n' "$pane_from_pid"
    return 0
  fi

  pane_from_agent="$(find_pane_by_agent_and_cwd || true)"
  if [ -n "$pane_from_agent" ]; then
    printf '%s\n' "$pane_from_agent"
    return 0
  fi

  return 1
}

tmux_bin="$(command -v tmux 2>/dev/null || true)"
if [ -z "$tmux_bin" ]; then
  exit 0
fi

target_pane="$(find_tmux_pane || true)"
if [ -z "$target_pane" ]; then
  exit 0
fi

is_target_active="$(tmux display-message -p -t "$target_pane" '#{pane_active}' 2>/dev/null || echo 0)"

agent_name="$(tmux show-options -pv -t "$target_pane" @agent_name 2>/dev/null || true)"
if [ -z "$agent_name" ]; then
	agent_name="$(tmux display-message -p -t "$target_pane" '#{pane_current_command}' 2>/dev/null || true)"
fi
if [ -z "$agent_name" ] && [ -n "$agent_hint" ]; then
  agent_name="$agent_hint"
fi

case "$agent_name" in
  traex|claude|codex)
    ;;
  *)
    exit 0
    ;;
esac

tmux set-option -pt "$target_pane" @agent_name "$agent_name"

case "$event" in
  wait|notification)
    if [ "$is_target_active" = "1" ]; then
      tmux set-option -pt "$target_pane" @agent_attention "0"
      tmux set-option -pt "$target_pane" @agent_attention_at ""
      /Users/bytedance/.tmux/scripts/recompute-window-agent-attention.sh "$target_pane" >/dev/null 2>&1 || true
      /Users/bytedance/.tmux/scripts/apply-agent-tab-attention.sh >/dev/null 2>&1 || true
      exit 0
    fi
    tmux set-option -pt "$target_pane" @agent_attention "1"
    tmux set-option -pt "$target_pane" @agent_attention_at "$(date +%s)"
    /Users/bytedance/.tmux/scripts/recompute-window-agent-attention.sh "$target_pane" >/dev/null 2>&1 || true
    /Users/bytedance/.tmux/scripts/apply-agent-tab-attention.sh >/dev/null 2>&1 || true
    tmux display-message "agent needs input: ${agent_name} (press CMD+g in WezTerm)"
    ;;
  done|stop)
    tmux set-option -pt "$target_pane" @agent_attention "0"
    tmux set-option -pt "$target_pane" @agent_attention_at ""
    /Users/bytedance/.tmux/scripts/recompute-window-agent-attention.sh "$target_pane" >/dev/null 2>&1 || true
    /Users/bytedance/.tmux/scripts/apply-agent-tab-attention.sh >/dev/null 2>&1 || true
    ;;
  *)
    exit 0
    ;;
esac
