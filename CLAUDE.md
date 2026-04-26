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

`config/deps.lua` is not just a config fragment — it's a utility module that other files import via `require 'config/deps'`. It exposes `command_exists(bin)`, `get_missing_dep(bin)`, `get_missing_for_bins(bins)`, `prompt_install(window, pane, missing)`, and `get_shell()`. The `MANAGED_BINS` table at the top maps binary names to their brew package names.

### WezTerm API version compatibility

Several functions handle differences between WezTerm releases:
- `get_pane_cwd(pane)` in `keys.lua` — resolves cwd from either Url object or string, with fallback manual parsing
- `tab_has_multiple_panes(window)` in `keys.lua` — tries `tab:panes()` then `tab:panes_with_info()`

### Tabs

`tabs.lua` is intentionally simple and mirrors the tab options from `KevinSilvester/wezterm-config`, with one local override: `tab_bar_at_bottom = true`. The `resurrect.lua` module loads the resurrect.wezterm plugin from GitHub and injects `CMD+SHIFT+s` (save) and `CMD+SHIFT+r` (restore) keybindings into the keys config.

### Color schemes

The `colors/` directory is present but empty. Color schemes are handled via WezTerm's built-in `color_scheme` setting in `theme.lua`.
