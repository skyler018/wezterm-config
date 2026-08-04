local theme_config = {}

-- 与 nvim（LazyVim + catppuccin mocha，透明背景）保持一致
theme_config.color_scheme = "Catppuccin Mocha"

local init = require("config/init")
init.register("theme", theme_config)
