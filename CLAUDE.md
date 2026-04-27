# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a modular WezTerm terminal emulator configuration. The entry point is `wezterm.lua`, which `require`s each module in a specific order and returns the merged config via `init.build()`.

## Applying Changes

Reload WezTerm after editing any config file — no build step. Either restart WezTerm or use the built-in reload command.

## Architecture: Module Registration & Merge

The config system lives in `config/init.lua` and works as follows:

- Each module calls `init.register(name, fragment_or_fn)` to register a Lua table (or a function that mutates `config`).
- `init.build()` iterates the registry in registration order and merges each fragment into the final config object.
- **Later registrations overwrite earlier ones for the same key** (simple assignment, not deep merge). This is why `theme.lua` is loaded last in `wezterm.lua`.
- `init.lua` inserts itself into `package.loaded['config/init']` before any module `require`s it, breaking the circular dependency (modules require init to register; init.build requires modules).

## Load Order (set in `wezterm.lua`)

1. `deps` — dependency detection framework (must load first; other modules call `deps.command_exists()` etc.)
2. `font`
3. `window`
4. `macos`
5. `shell`
6. `cursor`
7. `tabs`
8. `keys` — also calls `resurrect.setup(keys_config)` to inject resurrect keybindings
9. `theme` — loaded last so its `color_scheme` overrides any earlier value

## Key Patterns

### dep.lua as a service module

`config/deps.lua` is not just a config fragment — it's a utility module that other files import via `require 'config/deps'`. It exposes `command_exists(bin)`, `get_missing_dep(bin)`, `get_missing_for_bins(bins)`, `prompt_install(window, pane, missing)`, `install_with_brew(window, pane, missing)`, `get_shell()`, and `percent_decode(s)`. The `MANAGED_BINS` table at the top maps binary names to their brew package names (`yazi`, `lazygit`, `claude`, `codex`).

On `gui-startup`, deps checks for missing managed binaries and shows an `InputSelector` prompt offering one-click `brew install`. This fires once per WezTerm GUI process (`startup_prompted` guard).

### WezTerm API version compatibility

Several functions handle differences between WezTerm releases:
- `get_pane_cwd(pane)` in `keys.lua` — resolves cwd from either Url object or string, with fallback manual `file://` parsing
- `tab_has_multiple_panes(window)` in `keys.lua` — tries `tab:panes()` then `tab:panes_with_info()`
- `get_pane_id(pane)` / `get_tab_id(tab)` in `keys.lua` — tries `:pane_id()` / `:tab_id()` methods before falling back to `.pane_id` / `.tab_id` fields
- `prefer_one_third_for_traecli()` in `keys.lua` — checks fullscreen status via either `is_full_screen` or `full_screen` field

### AI pane tracking and auto-resize (keys.lua)

When an AI tool (claude, codex, traecli) is launched via a split keybinding, `remember_new_ai_pane()` records the new pane's ID in `tracked_ai_panes_by_tab` keyed by tab ID. This enables the `window-resized` event handler to call `adjust_tracked_ai_panel()` whenever the window is resized.

The resize logic:
- Only applies when the tracked pane is the rightmost pane in the tab.
- Adjusts to 33% width when fullscreen, 50% otherwise (`desired_ai_panel_percent`).
- Cleans up tracking when the tab drops to one pane or the tracked pane disappears.
- Tolerates API diffs (field vs method access) the same way other compat helpers do.

### Cross-module mutation pattern (resurrect + keys)

`keys.lua` builds its `keys_config` table, then calls `resurrect.setup(keys_config)` before registering. `resurrect.lua` receives this table and injects `CMD+SHIFT+s` (save workspace+window state) and `CMD+SHIFT+r` (fuzzy restore) keybindings via `table.insert`. This is the only case where one module mutates another module's fragment before registration.

### Tabs: title suppression for AI tools

The `format-tab-title` handler in `tabs.lua` has a `no_title_procs` set (`claude`, `codex`, `trae`) — when the foreground process is one of these, the app-set title is ignored and the process name is used instead. This prevents AI tool prompts/context from polluting the tab bar.

### Color schemes

The `colors/` directory is present but empty. Color schemes are handled via WezTerm's built-in `color_scheme` setting in `theme.lua` (currently `Tokyo Night`).

## Keybinding Reference

| Keys | Action |
|------|--------|
| `CMD+SHIFT+y` | Open yazi in new tab (current pane cwd) |
| `CMD+SHIFT+g/G` | Open lazygit in new tab (current pane cwd) |
| `CMD+SHIFT+a/A` | Split right: claude |
| `CMD+SHIFT+x/X` | Split right: codex |
| `CMD+SHIFT+t/T` | Split right: traecli (fallback: claude) |
| `CMD+SHIFT+o/O` | Open selected HTTP URL in browser |
| `CMD+SHIFT+i` | Manually trigger dependency check/install prompt |
| `CMD+SHIFT+s` | Save window+workspace state (resurrect) |
| `CMD+SHIFT+r` | Fuzzy restore saved state (resurrect) |
| `CMD+SHIFT+c` | Enter copy mode |
| `CMD+h/j/k/l` | Navigate panes (left/down/up/right) |
| `CMD+SHIFT+h/j/k/l` | Resize pane (H/J/K/L variants also work) |
| `CMD+n` | New window |
| `CMD+d` | Split horizontal |
| `CMD+SHIFT+D` | Split vertical |
| `CMD+w` | Close pane (with confirm) |
| `CMD+Enter` | Toggle pane zoom |
