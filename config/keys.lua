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
-- herdr agent start 等待新 pane 的 shell 变为可用并启动 agent 的超时（毫秒）。
local HERDR_AGENT_START_TIMEOUT_MS = 20000
local CONFIG_DIR = wezterm.config_dir or ((os.getenv("HOME") or "") .. "/.config/wezterm")

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
			tostring(action_label)
				.. " 已交给 tmux 管理。想恢复旧行为时，把 config/keys.lua 中 USE_WEZTERM_PANES 改为 true。",
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

local function herdr_bin()
	-- macOS 上从 Dock/Spotlight 启动的 wezterm GUI PATH 只有系统目录，
	-- 直接跑 `herdr` 会找不到命令；这里优先用 PATH/登录 shell 解析，再兜底绝对路径。
	local ok, path = deps.command_exists("herdr")
	if ok and path and #path > 0 then
		return path
	end
	return (os.getenv("HOME") or "") .. "/.local/bin/herdr"
end

local function is_abs_path(path)
	return type(path) == "string" and path:match("^/") ~= nil
end

local function get_herdr_focused_pane_cwd(herdr_path)
	local ok, stdout = wezterm.run_child_process({ herdr_path, "pane", "list" })
	if not ok or type(stdout) ~= "string" or #stdout == 0 then
		return nil
	end

	local parsed_ok, data = pcall(wezterm.json_parse, stdout)
	if not parsed_ok or not data or not data.result or type(data.result.panes) ~= "table" then
		return nil
	end

	for _, herdr_pane in ipairs(data.result.panes) do
		if herdr_pane.focused then
			if is_abs_path(herdr_pane.foreground_cwd) then
				return herdr_pane.foreground_cwd
			end
			if is_abs_path(herdr_pane.cwd) then
				return herdr_pane.cwd
			end
			return nil
		end
	end

	return nil
end

-- herdr pane 子命令的方向参数（WezTerm 方向名 -> herdr 方向名）
local HERDR_DIR = {
	Left = "left",
	Right = "right",
	Up = "up",
	Down = "down",
}

-- herdr pane 操作：统一执行 `herdr pane <subcmd> ...`，失败时报错 toast。
local function herdr_pane_action(subcmd, extra_args, ok_toast, fail_label)
	return wezterm.action_callback(function(window, pane)
		if not window then
			return
		end

		local herdr_path = herdr_bin()
		local args = { herdr_path, "pane", subcmd }
		for _, a in ipairs(extra_args or {}) do
			table.insert(args, a)
		end
		local ok, _, stderr = wezterm.run_child_process(args)
		if not ok then
			window:toast_notification("WezTerm", fail_label .. ": " .. tostring(stderr or ""), nil, 2000)
			return
		end

		if ok_toast then
			window:toast_notification("WezTerm", ok_toast, nil, 1000)
		end
	end)
end

local function herdr_pane_split_action(direction)
	return herdr_pane_action(
		"split",
		{ "--direction", direction, "--focus" },
		"herdr 分屏完成（" .. direction .. "）",
		"herdr 分屏失败"
	)
end

local function herdr_pane_resize_action(direction)
	return herdr_pane_action("resize", { "--direction", direction }, nil, "herdr resize 失败")
end

local function herdr_pane_focus_action(direction)
	return herdr_pane_action("focus", { "--direction", direction }, nil, "herdr 跳转失败")
end

local function herdr_pane_zoom_action()
	return herdr_pane_action("zoom", { "--toggle" }, nil, "herdr zoom 失败")
end

-- 在当前 pane 右侧新建 herdr pane，并在其中启动指定 agent（沿用当前工作目录并聚焦新 pane）
local function herdr_agent_in_new_pane_action(agent_kind, toast_label)
	return wezterm.action_callback(function(window, pane)
		if not window or not pane then
			return
		end

		local exists = deps.command_exists(agent_kind)
		if not exists then
			local missing = deps.get_missing_for_bins({ agent_kind })
			if #missing > 0 then
				deps.prompt_install(window, pane, missing)
			else
				window:toast_notification("WezTerm", "未检测到 " .. agent_kind .. "，请先安装", nil, 4000)
			end
			return
		end

		local herdr_path = herdr_bin()
		local cwd = get_herdr_focused_pane_cwd(herdr_path) or deps.get_pane_cwd(pane)

		-- 1) 分屏：右侧新建 herdr pane，沿用当前工作目录并聚焦。
		local split_args = { herdr_path, "pane", "split", "--direction", "right", "--focus" }
		if cwd and #cwd > 0 then
			table.insert(split_args, "--cwd")
			table.insert(split_args, cwd)
		end

		local ok, stdout, stderr = wezterm.run_child_process(split_args)
		if not ok then
			window:toast_notification("WezTerm", toast_label .. " 分屏失败: " .. tostring(stderr or ""), nil, 3000)
			return
		end

		local ok2, data = pcall(wezterm.json_parse, stdout)
		if not ok2 or not data or not data.result or not data.result.pane or not data.result.pane.pane_id then
			window:toast_notification("WezTerm", toast_label .. " 分屏后无法解析新 pane ID", nil, 3000)
			return
		end
		local new_pane_id = data.result.pane.pane_id

		-- 2) 在新 pane 中启动 agent（唯一命名，避免与已有 agent 重名冲突）。
		-- 刚 split 出的 pane 的 shell 尚未就绪，直接 start 会报 agent_pane_busy。
		-- 当前 WezTerm 版本没有可靠的 wezterm.call_after；用后台脚本轮询，避免阻塞 GUI。
		local name = agent_kind .. "-" .. tostring(os.time())
		local start_script = CONFIG_DIR .. "/scripts/start-herdr-agent.sh"
		local start_args = {
			"/bin/sh",
			start_script,
			herdr_path,
			agent_kind,
			name,
			new_pane_id,
			tostring(HERDR_AGENT_START_TIMEOUT_MS),
		}
		if agent_kind == "claude" then
			-- 与原有 claude 启动方式保持一致
			table.insert(start_args, "--dangerously-skip-permissions")
		end

		local ok3, _, stderr3 = wezterm.run_child_process(start_args)
		if not ok3 then
			window:toast_notification(
				"WezTerm",
				toast_label .. " 启动器失败: " .. tostring(stderr3 or ""),
				nil,
				4000
			)
			return
		end

		window:toast_notification("WezTerm", "正在启动 " .. toast_label .. " ...", nil, 2000)
	end)
end

local function pane_direction_action(direction)
	if USE_WEZTERM_PANES then
		return act.ActivatePaneDirection(direction)
	end

	return herdr_pane_focus_action(HERDR_DIR[direction] or "left")
end

local function pane_resize_action(direction)
	if USE_WEZTERM_PANES then
		return wezterm.action_callback(function(window, pane)
			resize_pane_by_percent(window, pane, direction)
		end)
	end

	return herdr_pane_resize_action(HERDR_DIR[direction] or "left")
end

local function pane_split_action(direction)
	if USE_WEZTERM_PANES then
		if direction == "horizontal" then
			return act.SplitHorizontal
		end
		return act.SplitVertical
	end

	-- herdr：horizontal=上下(down)、vertical=左右(right)
	local herdr_dir = direction == "horizontal" and "down" or "right"
	return herdr_pane_split_action(herdr_dir)
end

local function pane_zoom_action()
	if USE_WEZTERM_PANES then
		return "TogglePaneZoomState"
	end

	return herdr_pane_zoom_action()
end

local function pane_close_action()
	if USE_WEZTERM_PANES then
		return wezterm.action.CloseCurrentPane({ confirm = true })
	end

	return tmux_prefixed_send("x", "tmux: 关闭当前 pane（需确认）")
end

local function herdr_focus_agent_action(index)
	return wezterm.action_callback(function(window, pane)
		if not window then
			return
		end

		local herdr_path = herdr_bin()
		local ok, stdout, stderr = wezterm.run_child_process({ herdr_path, "agent", "list" })
		if not ok then
			window:toast_notification(
				"WezTerm",
				"herdr agent list 失败 (" .. herdr_path .. "): " .. tostring(stderr or ""),
				nil,
				2000
			)
			return
		end

		local ok2, data = pcall(wezterm.json_parse, stdout)
		if not ok2 or not data or not data.result or type(data.result.agents) ~= "table" then
			window:toast_notification("WezTerm", "herdr agent list 输出解析失败", nil, 2000)
			return
		end

		local agent = data.result.agents[index]
		if not agent or not agent.tab_id then
			window:toast_notification("WezTerm", "不存在第 " .. index .. " 个 herdr agent", nil, 2000)
			return
		end

		local fok, _, ferr = wezterm.run_child_process({ herdr_path, "tab", "focus", agent.tab_id })
		if not fok then
			window:toast_notification("WezTerm", "herdr 切换失败: " .. tostring(ferr or ""), nil, 2000)
			return
		end

		window:toast_notification("WezTerm", "已切换到 herdr agent: " .. tostring(agent.agent or ""), nil, 1200)
	end)
end

local function herdr_switch_worktree_action(index)
	return wezterm.action_callback(function(window, pane)
		if not window then
			return
		end

		local herdr_path = herdr_bin()
		local ok, stdout, stderr = wezterm.run_child_process({ herdr_path, "workspace", "list" })
		if not ok then
			window:toast_notification("WezTerm", "herdr workspace list 失败: " .. tostring(stderr or ""), nil, 2000)
			return
		end

		local ok2, data = pcall(wezterm.json_parse, stdout)
		if not ok2 or not data or not data.result or type(data.result.workspaces) ~= "table" then
			window:toast_notification("WezTerm", "herdr workspace list 输出解析失败", nil, 2000)
			return
		end

		local ws = data.result.workspaces[index]
		if not ws or not ws.workspace_id then
			window:toast_notification("WezTerm", "不存在第 " .. index .. " 个 herdr workspace", nil, 2000)
			return
		end

		local fok, _, ferr = wezterm.run_child_process({ herdr_path, "workspace", "focus", ws.workspace_id })
		if not fok then
			window:toast_notification("WezTerm", "herdr 切换失败: " .. tostring(ferr or ""), nil, 2000)
			return
		end

		window:toast_notification(
			"WezTerm",
			"已切换到 herdr workspace: " .. tostring(ws.label or ws.workspace_id),
			nil,
			1200
		)
	end)
end

local function herdr_new_workspace_action()
	return wezterm.action_callback(function(window, pane)
		if not window then
			return
		end

		local cwd = deps.get_pane_cwd(pane)
		if not cwd then
			window:toast_notification(
				"WezTerm",
				"herdr 新建 workspace 失败: 无法获取当前 pane 工作目录",
				nil,
				4000
			)
			return
		end

		local herdr_path = herdr_bin()
		local ok, _, stderr = wezterm.run_child_process({
			herdr_path,
			"workspace",
			"create",
			"--cwd",
			cwd,
			"--focus",
		})
		if not ok then
			window:toast_notification("WezTerm", "herdr 新建 workspace 失败: " .. tostring(stderr or ""), nil, 4000)
			return
		end

		window:toast_notification("WezTerm", "herdr 已新建并切换到 workspace", nil, 1200)
	end)
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
			open_in_new_tab(window, pane, {
				args = get_login_shell_args(claude_path or "claude", "--dangerously-skip-permissions"),
				toast_title = "正在新标签页打开 claude…",
			})
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
			open_in_new_tab(window, pane, {
				args = get_login_shell_args(codex_path or "codex"),
				toast_title = "正在新标签页打开 codex…",
			})
			return
		end

		split_right_prefer_exec(window, pane, codex_path or "codex", { codex_path or "codex" }, "正在打开 codex…")
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

	if
		not trae_ok
		and activate_existing_agent_pane(window, pane, { "trae", "traex", "claude" }, "已切换到 agent pane")
	then
		return
	end

	if trae_ok then
		if AGENT_LAUNCH_MODE == "tab" then
			open_in_new_tab(window, pane, {
				args = get_login_shell_args(trae_path or "traex"),
				toast_title = "正在新标签页打开 traex…",
			})
			return
		end

		split_right_prefer_exec(window, pane, trae_path or "traex", { trae_path or "traex" }, "正在打开 traex…")
		return
	end

	local claude_ok, claude_path = deps.command_exists("claude")
	if claude_ok then
		if AGENT_LAUNCH_MODE == "tab" then
			open_in_new_tab(window, pane, {
				args = get_login_shell_args(claude_path or "claude", "--dangerously-skip-permissions"),
				toast_title = "未检测到 traex，正在新标签页打开 claude…",
			})
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
		action = herdr_agent_in_new_pane_action("opencode", "herdr: 新 pane 打开 opencode"),
	},
	{
		key = "O",
		mods = PRIMARY_SHIFT_MOD,
		action = herdr_agent_in_new_pane_action("opencode", "herdr: 新 pane 打开 opencode"),
	},
	{
		key = "X",
		mods = PRIMARY_SHIFT_MOD,
		action = herdr_agent_in_new_pane_action("codex", "herdr: 新 pane 打开 codex"),
	},
	-- 兼容部分键盘布局/版本：同一个组合键在事件里可能表现为小写
	{
		key = "x",
		mods = PRIMARY_SHIFT_MOD,
		action = herdr_agent_in_new_pane_action("codex", "herdr: 新 pane 打开 codex"),
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
		action = herdr_agent_in_new_pane_action("claude", "herdr: 新 pane 打开 claude"),
	},
	{
		key = "c",
		mods = PRIMARY_SHIFT_MOD,
		action = herdr_agent_in_new_pane_action("claude", "herdr: 新 pane 打开 claude"),
	},

	{
		key = "j",
		mods = PRIMARY_MOD,
		action = pane_direction_action("Down"),
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

	-- 调整 pane 大小（herdr，h=左/k=上/j=下/l=右）
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
	-- herdr lazygit popup（Cmd+g，转发 prefix+alt+g）
	{
		key = "g",
		mods = PRIMARY_MOD,
		action = tmux_prefixed_send("\x1bg", "herdr: 打开 lazygit popup"),
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
	-- herdr 新建 workspace（基于当前 pane 工作目录）
	{ key = "n", mods = PRIMARY_MOD, action = herdr_new_workspace_action() },
	-- 新窗口
	{ key = "n", mods = PRIMARY_SHIFT_MOD, action = wezterm.action.SpawnWindow },
	-- 兼容部分键盘布局/版本：同一个组合键在事件里可能表现为大写
	{ key = "N", mods = PRIMARY_SHIFT_MOD, action = wezterm.action.SpawnWindow },

	-- herdr 侧边栏（转发 prefix+b，对应 herdr 的 toggle_sidebar）
	{ key = "b", mods = PRIMARY_MOD, action = tmux_prefixed_send("b", "herdr: 切换侧边栏") },

	-- herdr 设置（转发 prefix+s，对应 herdr 的 settings）
	{ key = "m", mods = PRIMARY_MOD, action = tmux_prefixed_send("s", "herdr: 打开设置") },

	{ key = "1", mods = PRIMARY_MOD, action = tmux_prefixed_send("1", "tmux: window 1") },
	{ key = "2", mods = PRIMARY_MOD, action = tmux_prefixed_send("2", "tmux: window 2") },
	{ key = "3", mods = PRIMARY_MOD, action = tmux_prefixed_send("3", "tmux: window 3") },
	{ key = "4", mods = PRIMARY_MOD, action = tmux_prefixed_send("4", "tmux: window 4") },
	{ key = "5", mods = PRIMARY_MOD, action = tmux_prefixed_send("5", "tmux: window 5") },
	{ key = "6", mods = PRIMARY_MOD, action = tmux_prefixed_send("6", "tmux: window 6") },
	{ key = "7", mods = PRIMARY_MOD, action = tmux_prefixed_send("7", "tmux: window 7") },
	{ key = "8", mods = PRIMARY_MOD, action = tmux_prefixed_send("8", "tmux: window 8") },
	{ key = "9", mods = PRIMARY_MOD, action = tmux_prefixed_send("9", "tmux: window 9") },

	-- 分屏（herdr：d=垂直/左右，D=水平/上下）
	{ key = "d", mods = PRIMARY_MOD, action = pane_split_action("vertical") },
	{ key = "D", mods = PRIMARY_SHIFT_MOD, action = pane_split_action("horizontal") },

	-- 关闭 pane
	{ key = "w", mods = PRIMARY_MOD, action = pane_close_action() },

	-- 放大 pane
	{ key = "Enter", mods = PRIMARY_MOD, action = pane_zoom_action() },

	-- 全屏
	{ key = "f", mods = PRIMARY_SHIFT_MOD, action = "ToggleFullScreen" },

	-- herdr reviewr toggle（Cmd+Shift+R，转发 prefix+alt+r）
	-- { key = "r", mods = PRIMARY_SHIFT_MOD, action = tmux_prefixed_send("\x1br", "herdr: 切换 reviewr") },
	-- { key = "R", mods = PRIMARY_SHIFT_MOD, action = tmux_prefixed_send("\x1br", "herdr: 切换 reviewr") },
}

-- herdr agent 切换：OPT+1..9 聚焦第 N 个 agent（按 `herdr agent list` 顺序）
for i = 1, 9 do
	table.insert(keys_config.keys, {
		key = tostring(i),
		mods = "OPT",
		action = herdr_focus_agent_action(i),
	})
end

-- herdr worktree 切换：CTRL+1..9 聚焦第 N 个打开的 workspace（每个对应一个 worktree/checkout）
for i = 1, 9 do
	table.insert(keys_config.keys, {
		key = tostring(i),
		mods = "CTRL",
		action = herdr_switch_worktree_action(i),
	})
end

local init = require("config/init")
local resurrect_config = require("config/resurrect")
resurrect_config.setup(keys_config)

init.register("keys", keys_config)
