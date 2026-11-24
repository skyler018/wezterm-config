local wezterm = require("wezterm")
local act = wezterm.action
local deps = require("config/deps")

local keys_config = {}
local is_macos = wezterm.target_triple and wezterm.target_triple:find("darwin", 1, true) ~= nil
local PRIMARY_MOD = is_macos and "CMD" or "CTRL"
local PRIMARY_SHIFT_MOD = PRIMARY_MOD .. "|SHIFT"

local function get_login_shell_args(...)
	local args = { deps.get_shell(), "-ic", 'exec "$0" "$@"' }
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		table.insert(args, v)
	end
	return args
end

local function open_in_new_tab(window, pane, options)
	if not window or not pane or not options or type(options.args) ~= "table" then
		return false, "missing window/pane/options"
	end

	if options.toast_title and #options.toast_title > 0 then
		window:toast_notification("WezTerm", options.toast_title, nil, 1200)
	end

	local cwd = deps.get_pane_cwd(pane)
	window:perform_action(
		act.SpawnCommandInNewTab({
			domain = "CurrentPaneDomain",
			cwd = cwd,
			args = options.args,
			set_environment_variables = {
				PATH = os.getenv("PATH"),
			},
		}),
		pane
	)
	return true, nil
end

local function split_right_command(window, pane, options)
	if not window or not pane or not options then
		return false, "missing window/pane/options"
	end

	if options.toast_title and #options.toast_title > 0 then
		window:toast_notification("WezTerm", options.toast_title, nil, 1200)
	end

	local ok, err = pcall(function()
		local cwd = deps.get_pane_cwd(pane)
		window:perform_action(
			act.SplitPane({
				direction = "Right",
				size = { Percent = 50 },
				command = {
					cwd = cwd,
					args = options.args,
					set_environment_variables = {
						PATH = os.getenv("PATH"),
					},
				},
			}),
			pane
		)
	end)

	if not ok then
		return false, tostring(err)
	end

	return true, nil
end

local function split_right_prefer_exec(window, pane, bin_path, fallback_args, toast_title)
	local direct_ok, direct_err = split_right_command(window, pane, {
		args = fallback_args,
		toast_title = toast_title,
	})
	if direct_ok then
		return true
	end

	local shell_args = get_login_shell_args(table.unpack(fallback_args))
	local shell_ok, shell_err = split_right_command(window, pane, {
		args = shell_args,
		toast_title = nil,
	})
	if shell_ok then
		window:toast_notification(
			"WezTerm",
			"直接启动失败，已回退到 shell 启动：" .. tostring(bin_path),
			nil,
			2500
		)
		return true
	end

	window:toast_notification("WezTerm", "打开分屏失败：" .. tostring(direct_err or shell_err), nil, 8000)
	return false
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
	if type(text) ~= "string" then
		return nil
	end

	-- 选区可能包含换行/空白；提取第一段非空内容
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
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
	local ok, lazygit_path = deps.command_exists("lazygit")
	if not ok then
		deps.prompt_install(window, pane, deps.get_missing_dep("lazygit"))
		return
	end

	local cwd = deps.get_pane_cwd(pane)
	if not cwd then
		window:toast_notification(
			"WezTerm",
			"未能获取当前 pane 的工作目录（将回退到 $HOME）",
			nil,
			6000
		)
	end
	window:perform_action(
		act.SpawnCommandInNewTab({
			domain = "CurrentPaneDomain",
			cwd = cwd,
			args = { lazygit_path or "lazygit", "-p", cwd or "." },
			set_environment_variables = {
				PATH = os.getenv("PATH"),
			},
		}),
		pane
	)
end

local function open_selected_http_url(window, pane)
	local selected = get_selected_text(window, pane)
	local url = extract_http_url(selected)
	if not url then
		window:toast_notification("WezTerm", "未在选中文本中找到 http/https 链接", nil, 4000)
		return
	end

	if type(wezterm.open_with) ~= "function" then
		window:toast_notification("WezTerm", "当前 WezTerm 版本不支持 wezterm.open_with()", nil, 6000)
		return
	end

	local ok, err = pcall(function()
		wezterm.open_with(url)
	end)
	if not ok then
		window:toast_notification("WezTerm", "打开链接失败：" .. tostring(err), nil, 8000)
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
	if ok and type(panes) == "table" then
		return #panes > 1
	end

	local ok2, panes_info = pcall(function()
		if tab.panes_with_info then
			return tab:panes_with_info()
		end
		return nil
	end)
	if ok2 and type(panes_info) == "table" then
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

	local is_lr = (dir == "Left" or dir == "Right")
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

-- pane 大小调整：按当前 pane 尺寸做比例缩放（纯 WezTerm 实现）
local function pane_resize_action(direction)
	return wezterm.action_callback(function(window, pane)
		resize_pane_by_percent(window, pane, direction)
	end)
end

-- 在新标签页打开 yazi（当前 pane 工作目录）
local function open_yazi(window, pane)
	local exists, yazi_path = deps.command_exists("yazi")
	if not exists then
		deps.prompt_install(window, pane, deps.get_missing_dep("yazi"))
		return
	end
	open_in_new_tab(window, pane, { args = { yazi_path or "yazi" } })
end

-- agent 直接在新标签页启动，不再经由 herdr/tmux
local function open_agent_in_new_tab(window, pane, bin, extra_args, toast_title)
	if not window or not pane then
		return
	end

	local exists, bin_path = deps.command_exists(bin)
	if not exists then
		local missing = deps.get_missing_for_bins({ bin })
		if #missing > 0 then
			deps.prompt_install(window, pane, missing)
		else
			window:toast_notification("WezTerm", "未检测到 " .. bin .. "，请先安装", nil, 4000)
		end
		return
	end

	local args = { bin_path or bin }
	for _, arg in ipairs(extra_args or {}) do
		table.insert(args, arg)
	end
	open_in_new_tab(window, pane, {
		args = get_login_shell_args(table.unpack(args)),
		toast_title = toast_title,
	})
end

local function open_claude_tab(window, pane)
	open_agent_in_new_tab(window, pane, "claude", { "--dangerously-skip-permissions" }, "正在新标签页打开 claude…")
end

local function open_codex_tab(window, pane)
	open_agent_in_new_tab(window, pane, "codex", nil, "正在新标签页打开 codex…")
end

local function open_traex_tab(window, pane)
	open_agent_in_new_tab(window, pane, "traex", nil, "正在新标签页打开 traex…")
end

local function open_omp_tab(window, pane)
	open_agent_in_new_tab(window, pane, "omp", nil, "正在新标签页打开 omp…")
end

-- 鼠标
keys_config.mouse_bindings = {
	-- 左键双击：选词并复制到剪贴板
	{
		event = { Up = { streak = 2, button = "Left" } },
		mods = "NONE",
		action = act.CompleteSelection("ClipboardAndPrimarySelection"),
	},

	-- 右键单击：粘贴
	{
		event = { Down = { streak = 1, button = "Right" } },
		mods = "NONE",
		action = act.PasteFrom("Clipboard"),
	},
}

-- 快捷键
keys_config.keys = {
	-- yazi / lazygit：直接在 WezTerm 新标签页打开
	{ key = "y", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_yazi) },
	{ key = "Y", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_yazi) },
	{ key = "g", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_lazygit) },
	-- 兼容部分键盘布局/版本：同一个组合键在事件里可能表现为大写
	{ key = "G", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_lazygit) },

	-- 依赖检测/安装
	{
		key = "i",
		mods = PRIMARY_SHIFT_MOD,
		action = wezterm.action_callback(function(window, pane)
			deps.prompt_install(window, pane, deps.get_missing_managed_deps())
		end),
	},

	-- agent：直接在新标签页启动（不依赖 herdr/tmux）
	{ key = "o", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_omp_tab) },
	{ key = "O", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_omp_tab) },
	{ key = "x", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_codex_tab) },
	{ key = "X", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_codex_tab) },
	{ key = "t", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_traex_tab) },
	{ key = "T", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_traex_tab) },
	{ key = "c", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_claude_tab) },
	{ key = "C", mods = PRIMARY_SHIFT_MOD, action = wezterm.action_callback(open_claude_tab) },

	-- 新标签页 / 新窗口（WezTerm 原生）
	{ key = "t", mods = PRIMARY_MOD, action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "n", mods = PRIMARY_MOD, action = act.SpawnWindow },
	{ key = "n", mods = PRIMARY_SHIFT_MOD, action = act.SpawnWindow },
	-- 兼容部分键盘布局/版本：同一个组合键在事件里可能表现为大写
	{ key = "N", mods = PRIMARY_SHIFT_MOD, action = act.SpawnWindow },

	-- pane 焦点切换（WezTerm 原生）
	{ key = "h", mods = PRIMARY_MOD, action = act.ActivatePaneDirection("Left") },
	{ key = "l", mods = PRIMARY_MOD, action = act.ActivatePaneDirection("Right") },
	{ key = "k", mods = PRIMARY_MOD, action = act.ActivatePaneDirection("Up") },
	{ key = "j", mods = PRIMARY_MOD, action = act.ActivatePaneDirection("Down") },

	-- tab 切换（WezTerm 原生）
	{ key = "[", mods = PRIMARY_SHIFT_MOD, action = act.ActivateTabRelative(-1) },
	{ key = "]", mods = PRIMARY_SHIFT_MOD, action = act.ActivateTabRelative(1) },

	{
		key = "F1",
		mods = "NONE",
		action = wezterm.action.ActivateCopyMode,
	},

	-- 调整 pane 大小（纯 WezTerm，h=左/k=上/j=下/l=右）
	{ key = "h", mods = PRIMARY_SHIFT_MOD, action = pane_resize_action("Left") },
	{ key = "H", mods = PRIMARY_SHIFT_MOD, action = pane_resize_action("Left") },
	{ key = "l", mods = PRIMARY_SHIFT_MOD, action = pane_resize_action("Right") },
	{ key = "L", mods = PRIMARY_SHIFT_MOD, action = pane_resize_action("Right") },
	{ key = "k", mods = PRIMARY_SHIFT_MOD, action = pane_resize_action("Up") },
	{ key = "K", mods = PRIMARY_SHIFT_MOD, action = pane_resize_action("Up") },
	{ key = "j", mods = PRIMARY_SHIFT_MOD, action = pane_resize_action("Down") },
	{ key = "J", mods = PRIMARY_SHIFT_MOD, action = pane_resize_action("Down") },

	-- 分屏（d=左右，D=上下）
	{ key = "d", mods = PRIMARY_MOD, action = act.SplitVertical },
	{ key = "D", mods = PRIMARY_SHIFT_MOD, action = act.SplitHorizontal },

	-- 关闭 pane
	{ key = "w", mods = PRIMARY_MOD, action = act.CloseCurrentPane({ confirm = true }) },

	-- 放大 pane
	{ key = "Enter", mods = PRIMARY_MOD, action = act.TogglePaneZoomState },

	-- 全屏
	{ key = "f", mods = PRIMARY_SHIFT_MOD, action = act.ToggleFullScreen },
}

-- 直接切换到第 N 个 WezTerm tab
for i = 1, 9 do
	table.insert(keys_config.keys, {
		key = tostring(i),
		mods = PRIMARY_MOD,
		action = act.ActivateTab(i - 1),
	})
end

local init = require("config/init")
local resurrect_config = require("config/resurrect")
resurrect_config.setup(keys_config)

init.register("keys", keys_config)
