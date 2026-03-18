local macos_config = {}

-- ===== macOS Specific =====
-- Keep Left Option as Meta so Alt-based Vim/Neovim keybindings work reliably.
macos_config.send_composed_key_when_left_alt_is_pressed = false
-- Keep Right Option available for composing locale/symbol characters.
macos_config.send_composed_key_when_right_alt_is_pressed = true
macos_config.native_macos_fullscreen_mode = true
macos_config.quit_when_all_windows_are_closed = false

local init = require 'config/init'
init.register('macos', macos_config)

