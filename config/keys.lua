local wezterm = require 'wezterm'
local act = wezterm.action
local deps = require 'config/deps'

local keys_config = {}

local function get_login_shell_args(...)
  local args = { deps.get_shell(), '-ic', 'exec "$0" "$@"' }
  for i = 1, select('#', ...) do
    table.insert(args, select(i, ...))
  end
  return args
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
    return deps.percent_decode(p)
  end

  return nil
end

local function get_selected_text(window, pane)
  local ok, text = pcall(function()
    if window and window.get_selection_text_for_pane then
      return window:get_selection_text_for_pane(pane)
    end
    if pane and pane.get_selection_text then
      return pane:get_selection_text()
    end
    return nil
  end)
  if not ok then
    return nil
  end
  if type(text) ~= 'string' then
    return nil
  end

  -- 选区可能包含换行/空白；提取第一段非空内容
  text = text:gsub('^%s+', ''):gsub('%s+$', '')
  if #text == 0 then
    return nil
  end
  return text
end

local function extract_http_url(text)
  if not text or #text == 0 then
    return nil
  end
  -- 尽量贴近 RFC3986：允许常见 URL 字符，排除空白与引号等分隔符
  return text:match("https?://[%w%-%._~:/%?#%[%]@!$&'%(%)*%+,;=]+")
end

local function open_lazygit(window, pane)
  local ok, lazygit_path = deps.command_exists('lazygit')
  if not ok then
    deps.prompt_install(window, pane, deps.get_missing_dep('lazygit'))
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
      set_environment_variables = {
        PATH = os.getenv('PATH'),
      },
    }),
    pane
  )
end

local function open_selected_http_url(window, pane)
  local selected = get_selected_text(window, pane)
  local url = extract_http_url(selected)
  if not url then
    window:toast_notification('WezTerm', '未在选中文本中找到 http/https 链接', nil, 4000)
    return
  end

  if type(wezterm.open_with) ~= 'function' then
    window:toast_notification('WezTerm', '当前 WezTerm 版本不支持 wezterm.open_with()', nil, 6000)
    return
  end

  local ok, err = pcall(function()
    wezterm.open_with(url)
  end)
  if not ok then
    window:toast_notification('WezTerm', '打开链接失败：' .. tostring(err), nil, 8000)
  end
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

local function prefer_one_third_for_traecli(window, pane)
  -- 需求：仅当当前窗口“足够大”（如全屏）时才用 1/3；否则保持 1/2。
  -- 这里严格以全屏标志判断，避免非全屏但窗口较大时也变成 1/3。
  local ok, wdim = pcall(function()
    return window and window.get_dimensions and window:get_dimensions() or nil
  end)
  if ok and type(wdim) == 'table' then
    return (wdim.is_full_screen == true) or (wdim.full_screen == true)
  end
  return false
end

local function split_claude(window, pane)
  local percent = prefer_one_third_for_traecli(window, pane) and 33 or 50

  if not window or not pane then
    return
  end

  local function split_right(args, toast_title)
    if toast_title and #toast_title > 0 then
      window:toast_notification('WezTerm', toast_title, nil, 1200)
    end

    local ok, err = pcall(function()
      window:perform_action(
        act.SplitPane({
          direction = 'Right',
          size = { Percent = percent },
          command = {
            args = args,
            set_environment_variables = {
              PATH = os.getenv('PATH'),
            },
          },
        }),
        pane
      )
    end)
    if not ok then
      window:toast_notification('WezTerm', '打开分屏失败：' .. tostring(err), nil, 8000)
    end
  end

  local claude_ok, claude_path = deps.command_exists('claude')
  if claude_ok then
    split_right(get_login_shell_args(claude_path or 'claude'), '正在打开 claude…')
    return
  end

  window:toast_notification('WezTerm', '未检测到 claude，将引导安装…', nil, 4000)
  deps.prompt_install(window, pane, deps.get_missing_dep('claude'))
end

local function split_codex(window, pane)
  local percent = prefer_one_third_for_traecli(window, pane) and 33 or 50

  if not window or not pane then
    return
  end

  local function split_right(args, toast_title)
    if toast_title and #toast_title > 0 then
      window:toast_notification('WezTerm', toast_title, nil, 1200)
    end

    local ok, err = pcall(function()
      window:perform_action(
        act.SplitPane({
          direction = 'Right',
          size = { Percent = percent },
          command = {
            args = args,
            set_environment_variables = {
              PATH = os.getenv('PATH'),
            },
          },
        }),
        pane
      )
    end)
    if not ok then
      window:toast_notification('WezTerm', '打开分屏失败：' .. tostring(err), nil, 8000)
    end
  end

  local codex_ok, codex_path = deps.command_exists('codex')
  if codex_ok then
    split_right(get_login_shell_args(codex_path or 'codex'), '正在打开 codex…')
    return
  end

  window:toast_notification('WezTerm', '未检测到 codex，将引导安装…', nil, 4000)
  deps.prompt_install(window, pane, deps.get_missing_dep('codex'))
end

local function split_traecli(window, pane)
  local percent = prefer_one_third_for_traecli(window, pane) and 33 or 50

  if not window or not pane then
    return
  end

  local function split_right(args, toast_title)
    if toast_title and #toast_title > 0 then
      window:toast_notification('WezTerm', toast_title, nil, 1200)
    end

    -- 用 SplitPane 明确指定 size 与 command；不同 WezTerm 版本更稳定。
    local ok, err = pcall(function()
      window:perform_action(
        act.SplitPane({
          -- 与之前 SplitHorizontal 行为一致：在右侧打开（按宽度比例）
          direction = 'Right',
          size = { Percent = percent },
          command = {
            args = args,
            set_environment_variables = {
              PATH = os.getenv('PATH'),
            },
          },
        }),
        pane
      )
    end)
    if not ok then
      window:toast_notification('WezTerm', '打开分屏失败：' .. tostring(err), nil, 8000)
    end
  end

  -- 像 yazi 一样先判断命令是否存在（按 PATH 查找）
  local trae_ok, trae_path = deps.command_exists('traecli')
  if trae_ok then
    split_right(get_login_shell_args(trae_path or 'traecli'), '正在打开 traecli…')
    return
  end

  -- traecli 不存在时，尝试 fallback 到 claude（存在性判断与安装引导按 yazi 方式）
  local claude_ok, claude_path = deps.command_exists('claude')
  if claude_ok then
    split_right(get_login_shell_args(claude_path or 'claude'), '未检测到 traecli，正在打开 claude…')
    return
  end

  window:toast_notification('WezTerm', '未检测到 traecli/claude，将引导安装 claude…', nil, 4000)
  deps.prompt_install(window, pane, deps.get_missing_for_bins({ 'claude' }))
end

-- 鼠标
keys_config.mouse_bindings = {
  -- 左键双击：选词并复制到剪贴板
  {
    event = { Up = { streak = 2, button = 'Left' } },
    mods = 'NONE',
    action = act.CompleteSelection('ClipboardAndPrimarySelection'),
  },

  -- 右键单击：粘贴
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
            deps.prompt_install(window, pane, deps.get_missing_dep('yazi'))
            return
          end

          local cwd = get_pane_cwd(pane)
          if not cwd then
            window:toast_notification('WezTerm', '未能获取当前 pane 的工作目录（将回退到 $HOME）', nil, 6000)
          end

          local args = get_login_shell_args(yazi_path or 'yazi')
          -- yazi 支持传入初始目录：yazi <dir>
          if cwd and #cwd > 0 then
            table.insert(args, cwd)
          end
          window:perform_action(
            act.SpawnCommandInNewTab({
              domain = 'CurrentPaneDomain',
              cwd = cwd,
              -- 通过 zsh 调用以加载环境变量，解决 yazi 插件找不到命令的问题
              args = args,
              set_environment_variables = {
                PATH = os.getenv('PATH'),
              },
            }),
            pane
          )
        end),
    },
    {
        key = "g",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(open_lazygit),
    },
    -- 兼容部分键盘布局/版本：同一个组合键在事件里可能表现为大写
    {
        key = "G",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(open_lazygit),
    },
    {
        key = "i",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(function(window, pane)
          deps.prompt_install(window, pane, deps.get_missing_managed_deps())
        end),
    },
    {
        key = 'o',
        mods = 'CMD|SHIFT',
        action = wezterm.action_callback(open_selected_http_url),
    },
    {
        key = 'O',
        mods = 'CMD|SHIFT',
        action = wezterm.action_callback(open_selected_http_url),
    },
    {
        key = "A",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(split_claude),
    },
    -- 兼容部分键盘布局/版本：同一个组合键在事件里可能表现为小写
    {
        key = "a",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(split_claude),
    },
    {
        key = "X",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(split_codex),
    },
    -- 兼容部分键盘布局/版本：同一个组合键在事件里可能表现为小写
    {
        key = "x",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(split_codex),
    },
    {
        key = "T",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(split_traecli),
    },
    -- 兼容部分键盘布局/版本：同一个组合键在事件里可能表现为小写
    {
        key = "t",
        mods = "CMD|SHIFT",
        action = wezterm.action_callback(split_traecli),
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
local resurrect_config = require 'config/resurrect'
resurrect_config.setup(keys_config)

init.register('keys', keys_config)
