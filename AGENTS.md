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

## Keybinding scope — no herdr/tmux coupling

- All keybindings in `keys.lua` are native WezTerm actions (panes, tabs, windows, agent launch); they must not invoke `herdr` or send tmux prefixes.
- Agent shortcuts (`CMD+SHIFT+c/x/t/o`) open the agent directly in a new WezTerm tab with the current pane cwd.
- **Never loop synchronous `wezterm.run_child_process(...)` inside an action callback.** It blocks the GUI thread and toasts never render. Push long-running work to a background process instead.
- `scripts/start-herdr-agent.sh` is no longer referenced by any keybinding; leave it alone unless the user asks to remove it.

## Style conventions

- Comments and UI strings are written in Chinese; match that in new code.
- `tabs.lua` suppresses app-set tab titles for `claude`/`codex`/`trae` (AI prompts would pollute the tab bar) and treats `top`/`htop`/`btop` as transient shell commands. Keep these sets updated if AI tool names change.
