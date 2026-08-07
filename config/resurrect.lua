local wezterm = require 'wezterm'

local M = {}
local ENABLE_WEZTERM_RESURRECT = false
local is_macos = wezterm.target_triple and wezterm.target_triple:find('darwin', 1, true) ~= nil
local PRIMARY_SHIFT_MOD = is_macos and 'CMD|SHIFT' or 'CTRL|SHIFT'

function M.setup(keys_config)
  if not ENABLE_WEZTERM_RESURRECT then
    return
  end

  -- 仅在启用时再拉取插件，避免每次启动都去 fetch 仓库。
  local resurrect = wezterm.plugin.require("https://github.com/MLFlexer/resurrect.wezterm")

  -- 快速保存状态 (Window + Workspace)
  table.insert(keys_config.keys, {
    key = "s",
    mods = PRIMARY_SHIFT_MOD,
    action = wezterm.action_callback(function(win, pane)
      resurrect.state_manager.save_state(resurrect.workspace_state.get_workspace_state())
      resurrect.window_state.save_window_action()
      win:toast_notification('WezTerm', '已保存当前 Window 和 Workspace 状态 (Tab/Pane/运行中的命令)', nil, 4000)
    end),
  })

  -- 快速恢复状态 (通过 fuzzy finder 模糊搜索选择恢复)
  table.insert(keys_config.keys, {
    key = "r",
    mods = PRIMARY_SHIFT_MOD,
    action = wezterm.action_callback(function(win, pane)
      resurrect.fuzzy_loader.fuzzy_load(win, pane, function(id, label)
        local type = string.match(id, "^([^/]+)") -- match before '/'
        id = string.match(id, "([^/]+)$") -- match after '/'
        id = string.match(id, "(.+)%..+$") -- remove file extention
        local opts = {
          relative = true,
          restore_text = true,
          on_pane_restore = resurrect.tab_state.default_on_pane_restore,
        }
        if type == "workspace" then
          local state = resurrect.state_manager.load_state(id, "workspace")
          resurrect.workspace_state.restore_workspace(state, opts)
        elseif type == "window" then
          local state = resurrect.state_manager.load_state(id, "window")
          resurrect.window_state.restore_window(pane:window(), state, opts)
        elseif type == "tab" then
          local state = resurrect.state_manager.load_state(id, "tab")
          resurrect.tab_state.restore_tab(pane:tab(), state, opts)
        end
      end)
    end),
  })
end

return M
