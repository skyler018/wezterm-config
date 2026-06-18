local wezterm = require("wezterm")
local act = wezterm.action
local deps = require("config/deps")

local keys_config = {}
local is_macos = wezterm.target_triple and wezterm.target_triple:find("darwin", 1, true) ~= nil
local PRIMARY_MOD = is_macos and "CMD" or "CTRL"
local PRIMARY_SHIFT_MOD = PRIMARY_MOD .. "|SHIFT"
-- WezTerm 只保留 GUI 容器职责；需要恢复旧的 pane 工作流时改回 true。
local USE_WEZTERM_PANES = false
local AGENT_LAUNCH_MODE = USE_WEZTERM_PANES and "split" or "tab"

local function tmux_prefixed_send(keys, hint_label)
	return wezterm.action_callback(function(window, pane)
		if not window then
			return
		end

		window:perform_action(act.SendString("\x02" .. keys), pane)
		if hint_label and #hint_label > 0 then
			window:toast_notification("WezTerm", hint_label, nil, 800)
		end
	end)
end

local function pane_workflow_hint(action_label)
	return wezterm.action_callback(function(window, pane)
		if not window then
			return
		end

		window:toast_notification(
			"WezTerm",
			tostring(action_label) .. " 已交给 tmux 管理。想恢复旧行为时，把 config/keys.lua 中 USE_WEZTERM_PANES 改为 true。",
			nil,
			4200
		)
	end)
end

local function tmux_workflow_action(keys, hint_label, callback)
	if USE_WEZTERM_PANES then
		return wezterm.action_callback(callback)
	end

	return tmux_prefixed_send(keys, hint_label)
end

local function tmux_user_action(keys, user_hint_label)
	return tmux_prefixed_send(keys, user_hint_label)
end

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

	local cwd = get_pane_cwd(pane)
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
		window:perform_action(
			act.SplitPane({
				direction = "Right",
				size = { Percent = 50 },
				command = {
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

	window:toast_notification(
		"WezTerm",
		"打开分屏失败：" .. tostring(direct_err or shell_err),
		nil,
		8000
	)
	return false
end

local function get_pane_cwd(pane)
	local cwd_uri = pane:get_current_working_dir()
	if not cwd_uri then
		return nil
	end

	-- pane:get_current_working_dir() 在不同版本可能返回 Url 对象或字符串
	-- 优先使用 Url.file_path，其次用官方转换函数，最后自行解析 file:// 作为兜底。
	if type(cwd_uri) == "table" and cwd_uri.file_path then
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

	if cwd_str:match("^file://") then
		local p = cwd_str:gsub("^file://", "")
		-- file:///Users/foo -> /Users/foo
		p = p:gsub("^/*", "/")
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

local function normalize_process_name(proc)
	if not proc then
		return ""
	end

	local name = tostring(proc):gsub("\\", "/"):match("([^/]+)$") or tostring(proc)
	return name:lower()
end

local function process_matches_any_target(process_name, targets)
	if process_name == "" then
		return false
	end

	for _, target in ipairs(targets or {}) do
		local normalized_target = tostring(target):lower()
		if normalized_target ~= "" and process_name:find(normalized_target, 1, true) then
			return true
		end
	end

	return false
end

local function normalize_title_text(text)
	if not text then
		return ""
	end

	local normalized = tostring(text):lower()
	normalized = normalized:gsub("\27%][^\7]*\7", "")
	normalized = normalized:gsub("\27%[[%d;?]*[%a]", "")
	normalized = normalized:gsub("[%c]", " ")
	normalized = normalized:gsub("%s+", " ")
	return normalized:gsub("^%s+", ""):gsub("%s+$", "")
end

local function extract_process_name_from_pane(pane_obj)
	if not pane_obj then
		return ""
	end

	local candidates = {
		pane_obj.foreground_process_name,
	}

	for _, candidate in ipairs(candidates) do
		local normalized = normalize_process_name(candidate)
		if normalized ~= "" then
			return normalized
		end
	end

	if pane_obj.get_foreground_process_name then
		local ok, value = pcall(function()
			return pane_obj:get_foreground_process_name()
		end)
		if ok then
			local normalized = normalize_process_name(value)
			if normalized ~= "" then
				return normalized
			end
		end
	end

	local title_candidates = {
		pane_obj.title,
	}
	if pane_obj.get_title then
		local ok, value = pcall(function()
			return pane_obj:get_title()
		end)
		if ok then
			table.insert(title_candidates, value)
		end
	end

	for _, title in ipairs(title_candidates) do
		local normalized_title = normalize_title_text(title)
		if normalized_title ~= "" then
			return normalized_title
		end
	end

	return ""
end

local function get_active_tab(window)
	if not window then
		return nil
	end

	local tab = window:active_tab()
	if not tab then
		return nil
	end

	return tab
end

local function activate_existing_agent_pane(window, pane, targets, toast_title)
	if not USE_WEZTERM_PANES then
		return false
	end

	local tab = get_active_tab(window)
	if not tab then
		return false
	end

	local ok, panes = pcall(function()
		if tab.panes then
			return tab:panes()
		end
		return nil
	end)
	if not ok or type(panes) ~= "table" or #panes == 0 then
		return false
	end

	local current_pane_id = pane and pane:pane_id() or nil
	for pane_index, candidate_pane in ipairs(panes) do
		local process_name = extract_process_name_from_pane(candidate_pane)
		local pane_id = candidate_pane and candidate_pane.pane_id and candidate_pane:pane_id() or nil
		if process_matches_any_target(process_name, targets) and pane_id ~= current_pane_id then
			local activated = false

			if candidate_pane and candidate_pane.activate then
				local ok = pcall(function()
					candidate_pane:activate()
				end)
				activated = ok
			end

			if not activated then
				local ok = pcall(function()
					window:perform_action(act.ActivatePaneByIndex(pane_index - 1), pane)
				end)
				activated = ok
			end

			if activated then
				if toast_title and #toast_title > 0 then
					window:toast_notification("WezTerm", toast_title, nil, 1200)
				end
				return true
			end
		end
	end

	return false
end

local function open_lazygit(window, pane)
	local ok, lazygit_path = deps.command_exists("lazygit")
	if not ok then
		deps.prompt_install(window, pane, deps.get_missing_dep("lazygit"))
		return
	end

	local cwd = get_pane_cwd(pane)
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

local function pane_direction_action(direction)
	if USE_WEZTERM_PANES then
		return act.ActivatePaneDirection(direction)
	end

	local tmux_direction_key = {
		Left = "h",
		Down = "J",
		Up = "k",
		Right = "l",
	}

	return tmux_prefixed_send(
		tmux_direction_key[direction] or "",
		"tmux: 切换到" .. tostring(direction) .. "侧 pane"
	)
end

local function pane_resize_action(direction)
	if USE_WEZTERM_PANES then
		return wezterm.action_callback(function(window, pane)
			resize_pane_by_percent(window, pane, direction)
		end)
	end

	local tmux_resize_key = {
		Left = "H",
		Down = "J",
		Up = "K",
		Right = "L",
	}

	return tmux_prefixed_send(
		tmux_resize_key[direction] or "",
		"tmux: 调整" .. tostring(direction) .. "侧 pane 大小"
	)
end

local function pane_split_action(direction)
	if USE_WEZTERM_PANES then
		if direction == "horizontal" then
			return act.SplitHorizontal
		end
		return act.SplitVertical
	end

	local tmux_split_key = {
		horizontal = "s",
		vertical = "v",
	}

	local split_hint = {
		horizontal = "tmux: 上下分屏",
		vertical = "tmux: 左右分屏",
	}

	return tmux_prefixed_send(
		tmux_split_key[direction] or "",
		split_hint[direction] or "tmux: 分屏"
	)
end

local function pane_zoom_action()
	if USE_WEZTERM_PANES then
		return "TogglePaneZoomState"
	end

	return tmux_prefixed_send("z", "tmux: 放大或还原当前 pane")
end

local function pane_close_action()
	if USE_WEZTERM_PANES then
		return wezterm.action.CloseCurrentPane({ confirm = true })
	end

	return tmux_prefixed_send("x", "tmux: 关闭当前 pane（需确认）")
end

local function jump_to_agent_attention_action()
	return tmux_user_action("\x1bj", "AI 通知跳转：定位到需要处理的 agent")
end

local function split_claude(window, pane)
	if not window or not pane then
		return
	end

	if activate_existing_agent_pane(window, pane, { "claude" }, "已切换到 claude pane") then
		return
	end

	local claude_ok, claude_path = deps.command_exists("claude")
	if claude_ok then
		if AGENT_LAUNCH_MODE == "tab" then
			open_in_new_tab(
				window,
				pane,
				{
					args = get_login_shell_args(claude_path or "claude", "--dangerously-skip-permissions"),
					toast_title = "正在新标签页打开 claude…",
				}
			)
			return
		end

		split_right_prefer_exec(
			window,
			pane,
			claude_path or "claude",
			{ claude_path or "claude", "--dangerously-skip-permissions" },
			"正在打开 claude…"
		)
		return
	end

	window:toast_notification("WezTerm", "未检测到 claude，将引导安装…", nil, 4000)
	deps.prompt_install(window, pane, deps.get_missing_dep("claude"))
end

local function split_codex(window, pane)
	if not window or not pane then
		return
	end

	if activate_existing_agent_pane(window, pane, { "codex" }, "已切换到 codex pane") then
		return
	end

	local codex_ok, codex_path = deps.command_exists("codex")
	if codex_ok then
		if AGENT_LAUNCH_MODE == "tab" then
			open_in_new_tab(
				window,
				pane,
				{
					args = get_login_shell_args(codex_path or "codex"),
					toast_title = "正在新标签页打开 codex…",
				}
			)
			return
		end

		split_right_prefer_exec(
			window,
			pane,
			codex_path or "codex",
			{ codex_path or "codex" },
			"正在打开 codex…"
		)
		return
	end

	window:toast_notification("WezTerm", "未检测到 codex，将引导安装…", nil, 4000)
	deps.prompt_install(window, pane, deps.get_missing_dep("codex"))
end

local function split_traex(window, pane)
	if not window or not pane then
		return
	end

	local trae_ok, trae_path = deps.command_exists("traex")
	if trae_ok and activate_existing_agent_pane(window, pane, { "trae", "traex" }, "已切换到 traex pane") then
		return
	end

	if (not trae_ok) and activate_existing_agent_pane(window, pane, { "trae", "traex", "claude" }, "已切换到 agent pane") then
		return
	end

	if trae_ok then
		if AGENT_LAUNCH_MODE == "tab" then
			open_in_new_tab(
				window,
				pane,
				{
					args = get_login_shell_args(trae_path or "traex"),
					toast_title = "正在新标签页打开 traex…",
				}
			)
			return
		end

		split_right_prefer_exec(
			window,
			pane,
			trae_path or "traex",
			{ trae_path or "traex" },
			"正在打开 traex…"
		)
		return
	end

	local claude_ok, claude_path = deps.command_exists("claude")
	if claude_ok then
		if AGENT_LAUNCH_MODE == "tab" then
			open_in_new_tab(
				window,
				pane,
				{
					args = get_login_shell_args(claude_path or "claude", "--dangerously-skip-permissions"),
					toast_title = "未检测到 traex，正在新标签页打开 claude…",
				}
			)
			return
		end

		split_right_prefer_exec(
			window,
			pane,
			claude_path or "claude",
			{ claude_path or "claude", "--dangerously-skip-permissions" },
			"未检测到 traex，正在打开 claude…"
		)
		return
	end

	window:toast_notification("WezTerm", "未检测到 traex/claude，将引导安装 claude…", nil, 4000)
	deps.prompt_install(window, pane, deps.get_missing_for_bins({ "claude" }))
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
	{
		key = "y",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_prefixed_send("y", "tmux: 新建 window 打开 yazi"),
	},
	{
		key = "Y",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_prefixed_send("y", "tmux: 新建 window 打开 yazi"),
	},
	{
		key = "g",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_workflow_action("g", "tmux: 打开 lazygit popup", open_lazygit),
	},
	-- 兼容部分键盘布局/版本：同一个组合键在事件里可能表现为大写
	{
		key = "G",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_workflow_action("g", "tmux: 打开 lazygit popup", open_lazygit),
	},
	{
		key = "i",
		mods = PRIMARY_SHIFT_MOD,
		action = wezterm.action_callback(function(window, pane)
			deps.prompt_install(window, pane, deps.get_missing_managed_deps())
		end),
	},
	{
		key = "o",
		mods = PRIMARY_SHIFT_MOD,
		action = wezterm.action_callback(open_selected_http_url),
	},
	{
		key = "O",
		mods = PRIMARY_SHIFT_MOD,
		action = wezterm.action_callback(open_selected_http_url),
	},
	{
		key = "X",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_workflow_action(";", "tmux: 打开 codex pane", split_codex),
	},
	-- 兼容部分键盘布局/版本：同一个组合键在事件里可能表现为小写
	{
		key = "x",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_workflow_action(";", "tmux: 打开 codex pane", split_codex),
	},
	{
		key = "T",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_workflow_action("[", "tmux: 打开 traex pane", split_traex),
	},
	-- 兼容部分键盘布局/版本：同一个组合键在事件里可能表现为小写
	{
		key = "t",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_workflow_action("[", "tmux: 打开 traex pane", split_traex),
	},
	{
		key = "t",
		mods = PRIMARY_MOD,
		action = tmux_prefixed_send("c", "tmux: 新建 window"),
	},
	{
		key = "h",
		mods = PRIMARY_MOD,
		action = pane_direction_action("Left"),
	},
	{
		key = "l",
		mods = PRIMARY_MOD,
		action = pane_direction_action("Right"),
	},

	{
		key = "k",
		mods = PRIMARY_MOD,
		action = pane_direction_action("Up"),
	},
	{
		key = "C",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_workflow_action("]", "tmux: 打开 claude pane", split_claude),
	},
	{
		key = "c",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_workflow_action("]", "tmux: 打开 claude pane", split_claude),
	},

	{
		key = "j",
		mods = PRIMARY_MOD,
		action = pane_direction_action("Down"),
	},
	{
		key = "g",
		mods = PRIMARY_MOD,
		action = jump_to_agent_attention_action(),
	},
	{
		key = "b",
		mods = PRIMARY_MOD,
		action = tmux_prefixed_send("B", "tmux: 打开左侧窗口侧栏"),
	},
	{
		key = "[",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_prefixed_send("\x08", "tmux: 上一个 window"),
	},
	{
		key = "]",
		mods = PRIMARY_SHIFT_MOD,
		action = tmux_prefixed_send("\x0c", "tmux: 下一个 window"),
	},
	{
		key = "F1",
		mods = "NONE",
		action = wezterm.action.ActivateCopyMode,
	},

	-- resize pane（仅在同 tab 多 pane 时生效）
	{
		key = "h",
		mods = PRIMARY_SHIFT_MOD,
		action = pane_resize_action("Left"),
	},
	{
		key = "H",
		mods = PRIMARY_SHIFT_MOD,
		action = pane_resize_action("Left"),
	},
	{
		key = "l",
		mods = PRIMARY_SHIFT_MOD,
		action = pane_resize_action("Right"),
	},
	{
		key = "L",
		mods = PRIMARY_SHIFT_MOD,
		action = pane_resize_action("Right"),
	},
	{
		key = "k",
		mods = PRIMARY_SHIFT_MOD,
		action = pane_resize_action("Up"),
	},
	{
		key = "K",
		mods = PRIMARY_SHIFT_MOD,
		action = pane_resize_action("Up"),
	},
	{
		key = "j",
		mods = PRIMARY_SHIFT_MOD,
		action = pane_resize_action("Down"),
	},
	{
		key = "J",
		mods = PRIMARY_SHIFT_MOD,
		action = pane_resize_action("Down"),
	},
	-- 新窗口
	{ key = "n", mods = PRIMARY_MOD, action = wezterm.action.SpawnWindow },
	{ key = "1", mods = PRIMARY_MOD, action = tmux_prefixed_send("1", "tmux: window 1") },
	{ key = "2", mods = PRIMARY_MOD, action = tmux_prefixed_send("2", "tmux: window 2") },
	{ key = "3", mods = PRIMARY_MOD, action = tmux_prefixed_send("3", "tmux: window 3") },
	{ key = "4", mods = PRIMARY_MOD, action = tmux_prefixed_send("4", "tmux: window 4") },
	{ key = "5", mods = PRIMARY_MOD, action = tmux_prefixed_send("5", "tmux: window 5") },
	{ key = "6", mods = PRIMARY_MOD, action = tmux_prefixed_send("6", "tmux: window 6") },
	{ key = "7", mods = PRIMARY_MOD, action = tmux_prefixed_send("7", "tmux: window 7") },
	{ key = "8", mods = PRIMARY_MOD, action = tmux_prefixed_send("8", "tmux: window 8") },
	{ key = "9", mods = PRIMARY_MOD, action = tmux_prefixed_send("9", "tmux: window 9") },

	-- 分屏
	{ key = "d", mods = PRIMARY_MOD, action = pane_split_action("horizontal") },
	{ key = "D", mods = PRIMARY_SHIFT_MOD, action = pane_split_action("vertical") },

	-- 关闭 pane
	{ key = "w", mods = PRIMARY_MOD, action = pane_close_action() },

	-- 放大 pane
	{ key = "Enter", mods = PRIMARY_MOD, action = pane_zoom_action() },

	-- 全屏
	{ key = "f", mods = PRIMARY_SHIFT_MOD, action = "ToggleFullScreen" },
}

local init = require("config/init")
local resurrect_config = require("config/resurrect")
resurrect_config.setup(keys_config)

init.register("keys", keys_config)
