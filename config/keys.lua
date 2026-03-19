local wezterm = require 'wezterm'
local act = wezterm.action
local deps = require 'config/deps'

local keys_config = {}

local function percent_decode(s)
  return (s:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function get_pane_cwd(pane)
  local cwd_uri = pane:get_current_working_dir()
  if not cwd_uri then
    return nil
  end

  -- pane:get_current_working_dir() 在不同版本可能返回 Url 对象或字符串
  -- 优先使用 Url.file_path，其次用官方转换函数，最后自行解析 file:// 作为兜底。
  if type(cwd_uri) == 'table' and cwd_uri.file_path then
    return cwd_uri.file_path
  end

  local cwd_str = tostring(cwd_uri)
  local ok, path = pcall(function()
    if wezterm.uri_to_file_path then
      return wezterm.uri_to_file_path(cwd_str)
    end
    if wezterm.uri_to_path then
      return wezterm.uri_to_path(cwd_str)
    end
    return nil
  end)
  if ok and path and #path > 0 then
    return path
  end

  if cwd_str:match('^file://') then
    local p = cwd_str:gsub('^file://', '')
    -- file:///Users/foo -> /Users/foo
    p = p:gsub('^/*', '/')
    return percent_decode(p)
  end

  return nil
end

local RESIZE_PERCENT = 0.05
local MAX_STEP_COLS = 30
local MAX_STEP_ROWS = 15

local function tab_has_multiple_panes(window)
  if not window then
    return false
  end

  local tab = window:active_tab()
  if not tab then
    return false
  end

  -- WezTerm 版本差异：不同版本可能暴露 panes()/panes_with_info()。
  local ok, panes = pcall(function()
    if tab.panes then
      return tab:panes()
    end
    return nil
  end)
  if ok and type(panes) == 'table' then
    return #panes > 1
  end

  local ok2, panes_info = pcall(function()
    if tab.panes_with_info then
      return tab:panes_with_info()
    end
    return nil
  end)
  if ok2 and type(panes_info) == 'table' then
    return #panes_info > 1
  end

  -- 无法判断时：交给 AdjustPaneSize 自身处理（单 pane 时通常是 no-op）。
  return true
end

local function resize_pane_by_percent(window, pane, dir)
  if not window or not pane or not dir then
    return
  end
  if not tab_has_multiple_panes(window) then
    return
  end

  local dims = pane:get_dimensions()
  if not dims then
    return
  end

  local is_lr = (dir == 'Left' or dir == 'Right')
  -- WezTerm 的 pane:get_dimensions() 在垂直方向通常暴露的是 viewport_rows（而不是 rows）。
  -- 左右调整用 cols，上下调整优先用 viewport_rows，兼容旧字段 rows。
  local base = is_lr and dims.cols or (dims.viewport_rows or dims.rows)
  if not base or base <= 0 then
    return
  end

  local step = math.floor((base * RESIZE_PERCENT) + 0.5)
  if step < 1 then
    step = 1
  end

  if is_lr then
    if step > MAX_STEP_COLS then
      step = MAX_STEP_COLS
    end
  else
    if step > MAX_STEP_ROWS then
      step = MAX_STEP_ROWS
    end
  end

  window:perform_action(act.AdjustPaneSize({ dir, step }), pane)
end

-- 鼠标
keys_config.mouse_bindings = {
  -- 选中后复制到 clipboard
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = act.CompleteSelection('ClipboardAndPrimarySelection'),
  },

  -- 右键粘贴
  {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = act.PasteFrom('Clipboard'),
  },
}

-- 快捷键
keys_config.keys = {
    {
        key = "y",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(function(window, pane)
          local ok, yazi_path = deps.command_exists('yazi')
          if not ok then
            deps.prompt_install(window, pane, deps.get_missing_managed_deps())
            return
          end

          local cwd = get_pane_cwd(pane)
          if not cwd then
            window:toast_notification('WezTerm', '未能获取当前 pane 的工作目录（将回退到 $HOME）', nil, 6000)
          end

          local args = { yazi_path or 'yazi' }
          -- yazi 支持传入初始目录：yazi <dir>
          if cwd and #cwd > 0 then
            table.insert(args, cwd)
          end
          window:perform_action(
            act.SpawnCommandInNewTab({
              domain = 'CurrentPaneDomain',
              cwd = cwd,
              -- 直接执行二进制，避免 login shell（-l）把 cwd 重置到 $HOME
              args = args,
            }),
            pane
          )
        end),
    },
    {
        key = "g",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(function(window, pane)
          local ok, lazygit_path = deps.command_exists('lazygit')
          if not ok then
            deps.prompt_install(window, pane, deps.get_missing_managed_deps())
            return
          end

          local cwd = get_pane_cwd(pane)
          if not cwd then
            window:toast_notification('WezTerm', '未能获取当前 pane 的工作目录（将回退到 $HOME）', nil, 6000)
          end
          window:perform_action(
            act.SpawnCommandInNewTab({
              domain = 'CurrentPaneDomain',
              cwd = cwd,
              args = { lazygit_path or 'lazygit', '-p', cwd or '.' },
            }),
            pane
          )
        end),
    },
    {
        key = "i",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(function(window, pane)
          deps.prompt_install(window, pane, deps.get_missing_managed_deps())
        end),
    },
    {
        key = "t",
        mods = "CMD|SHIFT",
        action = wezterm.action.SplitHorizontal { args = { "/Users/bytedance/.local/bin/traecli" }},
    },
    {
        key = "h",
        mods = "CMD",
        action = wezterm.action.ActivatePaneDirection("Left"),
    },
    {
        key = "l",
        mods = "CMD",
        action = wezterm.action.ActivatePaneDirection("Right"),
    },

    {
        key = "k",
        mods = "CMD",
        action = wezterm.action.ActivatePaneDirection("Up"),
    },
    {
        key = 'c',
        mods = 'CMD|SHIFT',
        action = wezterm.action.ActivateCopyMode,
    },

    {
        key = "j",
        mods = "CMD",
        action = wezterm.action.ActivatePaneDirection("Down"),
    },

    -- resize pane（仅在同 tab 多 pane 时生效）
    {
        key = 'h',
        mods = 'CMD|SHIFT',
        action = wezterm.action_callback(function(window, pane)
          resize_pane_by_percent(window, pane, 'Left')
        end),
    },
    {
        key = 'H',
        mods = 'CMD|SHIFT',
        action = wezterm.action_callback(function(window, pane)
          resize_pane_by_percent(window, pane, 'Left')
        end),
    },
    {
        key = 'l',
        mods = 'CMD|SHIFT',
        action = wezterm.action_callback(function(window, pane)
          resize_pane_by_percent(window, pane, 'Right')
        end),
    },
    {
        key = 'L',
        mods = 'CMD|SHIFT',
        action = wezterm.action_callback(function(window, pane)
          resize_pane_by_percent(window, pane, 'Right')
        end),
    },
    {
        key = 'k',
        mods = 'CMD|SHIFT',
        action = wezterm.action_callback(function(window, pane)
          resize_pane_by_percent(window, pane, 'Up')
        end),
    },
    {
        key = 'K',
        mods = 'CMD|SHIFT',
        action = wezterm.action_callback(function(window, pane)
          resize_pane_by_percent(window, pane, 'Up')
        end),
    },
    {
        key = 'j',
        mods = 'CMD|SHIFT',
        action = wezterm.action_callback(function(window, pane)
          resize_pane_by_percent(window, pane, 'Down')
        end),
    },
    {
        key = 'J',
        mods = 'CMD|SHIFT',
        action = wezterm.action_callback(function(window, pane)
          resize_pane_by_percent(window, pane, 'Down')
        end),
    },
    -- 新窗口
    {key="n", mods="CMD", action=wezterm.action.SpawnWindow},

    -- 分屏
    {key="d", mods="CMD", action=wezterm.action.SplitHorizontal},
    {key="D", mods="CMD|SHIFT", action=wezterm.action.SplitVertical},

    -- 关闭 pane
    {key="w", mods="CMD", action=wezterm.action.CloseCurrentPane{confirm=true}},

    -- 放大 pane
    {key="Enter", mods="CMD", action="TogglePaneZoomState"},
}

local init = require 'config/init'
init.register('keys', keys_config)
