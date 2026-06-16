local wezterm = require("wezterm")

local window_config = {}
local is_macos = wezterm.target_triple and wezterm.target_triple:find("darwin", 1, true) ~= nil

-- 初始化窗口大小
window_config.initial_cols = 120
window_config.initial_rows = 32

-- Resize 行为
window_config.use_resize_increments = true

-- 窗口内边距
window_config.window_padding = {
	left = "20px",
	right = "20px",
	top = "60px",
	bottom = "10px",
}

window_config.window_decorations = is_macos and "INTEGRATED_BUTTONS|RESIZE" or "TITLE|RESIZE"
window_config.macos_window_background_blur = is_macos and 20 or nil -- 背景模糊，阴影效果会自然呈现
window_config.window_background_opacity = 0.92 -- 半透明
window_config.window_frame = {
	-- Keep the titlebar closer to Kevin's appearance config.
	active_titlebar_bg = "#090909",
	inactive_titlebar_bg = "#090909",
}

local init = require("config/init")
init.register("window", window_config)
