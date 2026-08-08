# AGENTS.md

Modular WezTerm config. `wezterm.lua` requires `config/*.lua` in order; each module calls `init.register(name, fragment_or_fn)` and `init.build()` (in `config/init.lua`) merges them into the final config. See `CLAUDE.md` (architecture) and `README.md` (usage, keybinding reference).

## Non-obvious architecture facts

- **No build step.** Edit a `.lua` file, then reload WezTerm (restart or built-in reload) to test.
- **Merge is top-level key overwrite, not deep merge.** Later registration wins for the same key. So load order in `wezterm.lua` is behavior: `theme.lua` is last so its `colors` win. If you add a config key to a module and it silently has no effect, an earlier or later module is overwriting it.
- **macOS gating** uses `wezterm.target_triple:find('darwin')` (see `wezterm.lua:3`); `config/macos.lua` is only required on macOS.
- **`config/deps.lua` is a service module**, not just a fragment — `keys.lua` and others `require 'config/deps'` for `command_exists()`, `get_shell()`, `percent_decode()`, etc. Don't rename/move its exports without updating importers.
- **Cross-module mutation:** `keys.lua` builds its `keys_config` then calls `resurrect.setup(keys_config)`, which injects keybindings via `table.insert`. This is the only module that mutates another's fragment.
- **Resurrect is disabled by default** (`ENABLE_WEZTERM_RESURRECT = false` in `config/resurrect.lua`). When disabled, `setup()` returns before requiring the plugin — so `CMD+SHIFT+s/r` are NOT registered. Flip that flag to enable.
- **WezTerm API version compat** lives in `keys.lua`: `get_pane_cwd()` handles Url-object vs string cwd; `tab_has_multiple_panes()` tries `tab:panes()` then `tab:panes_with_info()`. Keep these fallbacks when editing near them.

## herdr agent launch — the trap

Agent shortcuts (`CMD+SHIFT+c/x/o`, trae) split a herdr pane and start the agent via `scripts/start-herdr-agent.sh` — a self-forking background worker that retries `herdr agent start` until `agent_started` or deadline.

- **Never loop synchronous `wezterm.run_child_process(...)` inside an action callback.** It blocks the GUI thread; retry loops mean **toast notifications never render** — the user sees "no toast" even though the binding fired and requests hit herdr. `wezterm.call_after` is not reliable on the targeted WezTerm build. Push retry/wait logic to a background process instead.
- `agent_pane_busy` early on is **normal** — the new pane's shell isn't interactive yet; the worker retries.

Debugging "pane opens but agent never starts / no toast":
1. `grep -E "cli:(pane:split|agent:start)" ~/.config/herdr/herdr-server.log` — proves the binding fired.
2. `cat "${TMPDIR:-/tmp}/wezterm-herdr-agent-start-"*.log` — the worker's log.
3. `herdr pane list` — `agent_pane_not_found` means the pane shell died, not a retry problem.
4. Missing toast ≠ config not reloaded; a blocked GUI thread is the usual cause.

## Style conventions

- Comments and UI strings are written in Chinese; match that in new code.
- `tabs.lua` suppresses app-set tab titles for `claude`/`codex`/`trae` (AI prompts would pollute the tab bar) and treats `top`/`htop`/`btop` as transient shell commands. Keep these sets updated if AI tool names change.
