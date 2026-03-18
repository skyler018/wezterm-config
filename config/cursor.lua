local cursor_config = {}

-- 光标样式
cursor_config.default_cursor_style = "BlinkingBlock"
cursor_config.scrollback_lines = 20000

-- 滚动条
cursor_config.enable_scroll_bar = false

-- 鼠标
cursor_config.selection_word_boundary = ' \t\n{}[]()"\'-'

local init = require 'config/init'
init.register('cursor', cursor_config)
