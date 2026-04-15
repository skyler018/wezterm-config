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

local function trim(text)
  return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function percent_decode(s)
  return (s:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function cwd_basename(cwd)
  if not cwd then
    return nil
  end

  local path = cwd
  if type(cwd) == 'table' and cwd.file_path then
    path = cwd.file_path
  else
    path = tostring(cwd)
    if wezterm.uri_to_file_path then
      local ok, resolved = pcall(wezterm.uri_to_file_path, path)
      if ok and resolved and #resolved > 0 then
        path = resolved
      end
    elseif path:match('^file://') then
      path = percent_decode(path:gsub('^file://', ''):gsub('^/*', '/'))
    end
  end

  path = tostring(path):gsub('/+$', '')
  if path == '' then
    return nil
  end

  return basename(path)
end

local function normalize_title(title, proc)
  title = trim(title)
  if title == '' then
    return nil
  end

  local proc_name = trim(proc)
  local lower_title = title:lower()
  local lower_proc = proc_name:lower()

  if lower_title == 'wezterm' or lower_title == lower_proc then
    return nil
  end

  if title:match('^file://') or title:find('/') then
    local name = basename(title)
    return name ~= '' and name or title
  end

  return title
end

local function label_for_pane(pane)
  local raw_title = (pane and pane.title) or ""
  local proc = basename((pane and pane.foreground_process_name) or "")
  local title = normalize_title(raw_title, proc)
  local label = title or proc

  if label == '' then
    label = 'shell'
  end

  return label, proc, title
end

local function build_context_suffix(pane, proc, title)
  local parts = {}
  local cwd_name = cwd_basename(pane and pane.current_working_dir)
  if cwd_name and cwd_name ~= '' then
    table.insert(parts, cwd_name)
  end

  local lower_proc = (proc or ''):lower()
  local lower_title = (title or ''):lower()
  local looks_like_editor = lower_proc:find('nvim', 1, true)
    or lower_proc:find('vim', 1, true)
    or lower_proc:find('hx', 1, true)

  if looks_like_editor and pane and pane.pane_id then
    local needs_pane_hint = (#parts == 0) or lower_title == lower_proc
    if needs_pane_hint then
      table.insert(parts, '#' .. tostring(pane.pane_id))
    end
  end

  if #parts == 0 then
    return nil
  end

  return table.concat(parts, ' · ')
end

local function fit_to_width(text, max_width)
  if not max_width or max_width <= 0 or #text <= max_width then
    return text
  end

  if max_width <= 1 then
    return string.sub(text, 1, max_width)
  end

  return string.sub(text, 1, max_width - 1) .. '…'
end

wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local pane = tab.active_pane

  local idx = (tab.tab_index or 0) + 1

  local label, proc, title = label_for_pane(pane)

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

  local has_duplicate_label = false
  for _, other_tab in ipairs(tabs or {}) do
    if other_tab.tab_id ~= tab.tab_id then
      local other_label = label_for_pane(other_tab.active_pane)
      if other_label == label then
        has_duplicate_label = true
        break
      end
    end
  end

  local suffix = has_duplicate_label and build_context_suffix(pane, proc, title) or nil
  if has_duplicate_label and suffix then
    label = label .. ' · ' .. suffix
  end

  label = fit_to_width(label, math.max(16, (max_width or 0) + 1))

  return {
    { Attribute = { Intensity = 'Bold' } },
    { Text = " " .. idx .. " " .. icon .. label .. " " },
  }
end)

local init = require 'config/init'
init.register('tabs', tabs_config)
