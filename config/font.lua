local wezterm = require 'wezterm'

local font_config = {}

-- 字体
font_config.font = wezterm.font_with_fallback({
  { family = 'JetBrainsMono Nerd Font', weight = 'Bold' },
  --{ family = 'Maple Mono NF CN', weight = 'Regular' },
  -- Omit explicit CJK font; macOS selects the best one based on locale.
  'Apple Color Emoji',
})
font_config.font_rules = {
  -- Prevent thin weight: use Regular instead of Light for Half intensity
  {
    intensity = 'Half',
    font = wezterm.font_with_fallback({
      { family = 'JetBrainsMono Nerd Font', weight = 'Bold' },
    }),
  },
  -- Normal italic: disable real italics (keep upright)
  {
    intensity = 'Normal',
    italic = true,
    font = wezterm.font_with_fallback({
      { family = 'JetBrainsMono Nerd Font', weight = 'Bold', italic = false },
    }),
  },
  -- Bold: keep consistent with base font weight
  {
    intensity = 'Bold',
    font = wezterm.font_with_fallback({
      { family = 'JetBrainsMono Nerd Font', weight = 'Bold' },
    }),
  },
}

font_config.bold_brightens_ansi_colors = false
font_config.font_size = 16.0
font_config.line_height = 1.1
font_config.cell_width = 1.0
font_config.harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' }
font_config.use_cap_height_to_scale_fallback_fonts = false

local init = require 'config/init'
init.register('font', font_config)
