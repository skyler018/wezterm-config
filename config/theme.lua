local theme_config = {}

-- 主题
--theme_config.color_scheme = "Catppuccin Macchiato"
--theme_config.color_scheme = "Darcula (base16)"
theme_config.color_scheme = "Tokyo Night"
--theme_config.color_scheme = "Default Dark (base16)"

local init = require("config/init")
init.register("theme", theme_config)
