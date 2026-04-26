local wezterm = require("wezterm")

local window_config = {}

-- 初始化窗口大小
window_config.initial_cols = 140
window_config.initial_rows = 38

-- Resize 行为
window_config.use_resize_increments = true

-- 窗口内边距
window_config.window_padding = {
	left = "20px",
	right = "20px",
	top = "60px",
	bottom = "10px",
}

window_config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
--config.window_decorations = "TITLE|RESIZE"   -- 保留标题栏和可调整边框
window_config.macos_window_background_blur = 20 -- 背景模糊，阴影效果会自然呈现
window_config.window_background_opacity = 0.92 -- 半透明
window_config.window_frame = {
	-- Keep the titlebar closer to Kevin's appearance config.
	active_titlebar_bg = "#090909",
	inactive_titlebar_bg = "#090909",
}

local init = require("config/init")
init.register("window", window_config)
