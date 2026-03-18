local wezterm = require 'wezterm'

local tabs_config = {}

-- Tab 设置
tabs_config.enable_tab_bar = true
tabs_config.tab_bar_at_bottom = true
tabs_config.use_fancy_tab_bar = true
tabs_config.hide_tab_bar_if_only_one_tab = true

local function basename(path)
  return string.gsub(path, ".*/", "")
end

wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local pane = tab.active_pane

  local idx = (tab.tab_index or 0) + 1

  local title = (pane and pane.title) or ""
  local proc = (pane and pane.foreground_process_name) or ""

  proc = basename(proc)

  -- 根据前台进程推断 icon（无论 title 是否存在都生效）
  local icon = ""
  if proc:find("nvim") then
    icon = " "
  elseif proc:find("vim") then
    icon = " "
  elseif proc:find("ssh") then
    icon = " "
  elseif proc:find("henv") then
    icon = " "
  elseif proc:find("docker") then
    icon = " "
  elseif proc:find("git") then
    icon = " "
  end

  -- 给普通 shell 一个默认 icon，避免出现“完全没有 icon”
  if icon == "" then
    icon = " "
  end

  -- ========= 优先使用 shell 注入 =========
  if title ~= "" then
    return {
      { Text = " " .. idx .. " " .. icon .. title .. " " },
    }
  end

  -- ========= fallback =========
  return {
    { Text = " " .. idx .. " " .. icon .. proc .. " " },
  }
end)

local init = require 'config/init'
init.register('tabs', tabs_config)
