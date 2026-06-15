local wezterm = require("wezterm")

local font_config = {}
-- 当前机器上可稳定命中的 family 是 WezTerm 内置的 JetBrains Mono；
-- Nerd 图标单独交给 Symbols Nerd Font Mono 兜底，避免 family 名不匹配时整体回退。
local base_font_family = "JetBrains Mono"

-- 字体
font_config.font = wezterm.font_with_fallback({
	{ family = base_font_family, weight = "Medium" },
	"Symbols Nerd Font Mono",
	"Apple Color Emoji",
})
font_config.font_rules = {
	-- Prevent thin weight: use Medium instead of Light for Half intensity
	{
		intensity = "Half",
		font = wezterm.font_with_fallback({
			{ family = base_font_family, weight = "Medium" },
			"Symbols Nerd Font Mono",
		}),
	},
	-- Normal italic: disable real italics (keep upright)
	{
		intensity = "Normal",
		italic = true,
		font = wezterm.font_with_fallback({
			{ family = base_font_family, weight = "Medium", italic = false },
			"Symbols Nerd Font Mono",
		}),
	},
	-- Bold: use Bold weight for real visual emphasis distinct from normal text
	{
		intensity = "Bold",
		font = wezterm.font_with_fallback({
			{ family = base_font_family, weight = "Bold" },
			"Symbols Nerd Font Mono",
		}),
	},
}

font_config.bold_brightens_ansi_colors = false
font_config.font_size = 18.0
font_config.line_height = 1.1
font_config.cell_width = 1.0
font_config.harfbuzz_features = { "calt=0", "clig=0", "liga=0" }
font_config.use_cap_height_to_scale_fallback_fonts = false

local init = require("config/init")
init.register("font", font_config)
