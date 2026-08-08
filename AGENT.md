# AGENT.md

This file records hard-won debugging knowledge for AI agents working on this WezTerm configuration, especially around the herdr integration shortcuts. It complements CLAUDE.md (architecture) and README.md (usage).

## Symptoms: AI agent shortcuts "open a pane but no agent starts" / "no toast"

When pressing `CMD+SHIFT+o` (opencode), `CMD+SHIFT+c` (claude), or `CMD+SHIFT+x` (codex), the intended behavior is: split a new herdr pane, then start the agent in it. The bug report looked like:

- A new herdr pane appears but the agent never launches inside it.
- Sometimes it works, sometimes not ("unstable").
- No toast notification appears at all, even though the keybinding fires.

## Root cause (the trap)

The naive fix is to retry `herdr agent start` in Lua via `wezterm.call_after(...)` every ~0.5s until the pane shell is ready (it returns `agent_pane_busy` until then). **This does not work** on this WezTerm version:

1. `wezterm.run_child_process(...)` is **synchronous and blocks the GUI thread**.
2. Spinning a retry loop (or re-splitting on `agent_pane_not_found`) inside the action callback keeps the GUI event loop busy.
3. Because the GUI thread is blocked, **toast notifications never render** — so the user sees no toast at all, even though the code path runs and the split/start requests hit the herdr server (visible in `herdr-server.log`).

Do not conclude "the config wasn't reloaded" from missing toasts. Verify whether the GUI thread is being blocked by a synchronous child-process loop first. The server-side `cli:pane:split` / `cli:agent:start` requests in `~/.config/herdr/herdr-server.log` prove the binding fired even when the UI shows nothing.

## The working solution: background shell worker

Commit `de76baf` ("Fix herdr agent startup race"). Instead of retrying in Lua, delegate the retry loop to a background shell script so the GUI thread returns immediately.

- `scripts/start-herdr-agent.sh` — a self-forking worker:
  - First invocation checks `WEZTERM_HERDR_AGENT_WORKER != 1` and re-execs itself in the background with that var set, then returns immediately (non-blocking).
  - The worker loop calls `herdr agent start ... --pane <id> --timeout <ms>`, greps stdout for `"type":"agent_started"` (success) or `"code":"agent_pane_busy"` (retry after `sleep 0.5` until deadline), and exits otherwise.
  - Writes a log to `${TMPDIR:-/tmp}/wezterm-herdr-agent-start-<name>.log` for debugging.
- `config/keys.lua` — `herdr_agent_in_new_pane_action`:
  - Splits the pane, parses the new `pane_id`.
  - Invokes `/bin/sh <script> <herdr_path> <kind> <name> <pane_id> <timeout_ms>` via `wezterm.run_child_process` (returns immediately because the script forks).
  - Shows a "正在启动 <label> ..." toast right away.

Key principle: **never loop synchronous child processes inside a WezTerm action callback.** If retry/wait logic is needed, push it to a background process.

## Debugging checklist

1. Confirm the server sees the requests: `grep -E "cli:(pane:split|agent:start)" ~/.config/herdr/herdr-server.log`.
2. Read the worker log: `cat "${TMPDIR:-/tmp}/wezterm-herdr-agent-start-"*.log`.
3. Check the pane survived: `herdr pane list` — a pane whose shell exited (`agent_pane_not_found`) means the shell itself died, not a retry problem.
4. `agent_pane_busy` early on is **normal** (the new pane's shell isn't interactive yet); the worker retries it.
5. Toast absence ≠ config not loaded. Blocked GUI thread (synchronous loops) is the usual cause.

## Version note

This configuration targets a WezTerm build where `wezterm.call_after` is not reliable for this purpose. If a future WezTerm version fixes that, the background-script approach can be reconsidered — but it is currently the correct pattern here.