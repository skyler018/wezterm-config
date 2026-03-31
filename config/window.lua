local wezterm = require 'wezterm'

local window_config = {}

-- 初始化窗口大小
window_config.initial_cols = 110
window_config.initial_rows = 30

-- Resize 行为
window_config.use_resize_increments = true

-- 窗口内边距
window_config.window_padding = {
  left = '40px',
  right = '40px',
  top = '70px',
  bottom = '20px',
}

window_config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
--config.window_decorations = "TITLE|RESIZE"   -- 保留标题栏和可调整边框
window_config.macos_window_background_blur = 20     -- 背景模糊，阴影效果会自然呈现
window_config.window_background_opacity = 0.92      -- 半透明
window_config.window_frame = {
  -- tab/titlebar 使用 window_frame.font；这里直接指定 Bold 让所有 tab 标签更“粗”
  font = wezterm.font_with_fallback({
    { family = 'JetBrainsMono Nerd Font', weight = 'Bold' },
    'Symbols Nerd Font Mono',
  }),
  font_size = 15.0,
  -- 中性灰黑：保留层次但减少紫/蓝倾向
  active_titlebar_bg = '#1b1b1f',
  inactive_titlebar_bg = '#141418',
}

local init = require 'config/init'
init.register('window', window_config)
