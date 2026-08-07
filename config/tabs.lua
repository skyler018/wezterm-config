local wezterm = require("wezterm")
local deps = require("config/deps")

local tabs_config = {}
local nf = wezterm.nerdfonts

tabs_config.enable_tab_bar = true
-- Keep the GUI-level tab strip separate from tmux's status line.
tabs_config.tab_bar_at_bottom = false
tabs_config.hide_tab_bar_if_only_one_tab = true
tabs_config.use_fancy_tab_bar = false
tabs_config.tab_max_width = 25
tabs_config.show_tab_index_in_tab_bar = false
tabs_config.switch_to_last_active_tab_when_closing_tab = true

local ICON_LEFT = nf.ple_left_half_circle_thick
local ICON_RIGHT = nf.ple_right_half_circle_thick
local ICON_CLAUDE = "✻"

local COLORS = {
	text_default = { bg = "#3a3d44", fg = "#c5c8c6" },
	text_hover = { bg = "#88a1bb", fg = "#1d1f21" },
	text_active = { bg = "#83a5d6", fg = "#1d1f21" },
	scircle_default = { bg = "rgba(0, 0, 0, 0.4)", fg = "#3a3d44" },
	scircle_hover = { bg = "rgba(0, 0, 0, 0.4)", fg = "#88a1bb" },
	scircle_active = { bg = "rgba(0, 0, 0, 0.4)", fg = "#83a5d6" },
}

local function clean_process_name(proc)
	local name = (proc or ""):gsub(".*[/\\](.*)", "%1")
	return name:gsub("%.exe$", "")
end

local function trim(text)
	return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function take_cells(text, max_cells)
	if not text or text == "" or not max_cells or max_cells <= 0 then
		return ""
	end

	local cell_count = 0
	local out = {}
	for _, codepoint in utf8.codes(text) do
		local ch = utf8.char(codepoint)
		local width = wezterm.column_width(ch)
		if (cell_count + width) > max_cells then
			break
		end
		cell_count = cell_count + width
		table.insert(out, ch)
	end
	return table.concat(out)
end

local function pad_cells(text, target_cells)
	local current = wezterm.column_width(text)
	if current >= target_cells then
		return text
	end
	return text .. string.rep(" ", target_cells - current)
end

local function fit_title(text, max_cells)
	local inner_max = math.max(6, max_cells or 25)
	local ellipsis = "…"
	local ellipsis_width = wezterm.column_width(ellipsis)

	if wezterm.column_width(text) > inner_max then
		text = take_cells(text, inner_max - ellipsis_width) .. ellipsis
	end

	return pad_cells(text, inner_max)
end

local function sanitize_title(text)
	text = trim(text or "")
	-- 去掉常见 ANSI/OSC 控制序列与不可见控制字符，避免全屏 TUI 污染 tab 标题渲染。
	text = text:gsub("\27%][^\7]*\7", "")
	text = text:gsub("\27%[[%d;?]*[%a]", "")
	text = text:gsub("[%c]", " ")
	text = text:gsub("%s+", " ")
	return trim(text)
end

local function basename(path)
	if not path or path == "" then
		return nil
	end
	if path == "/" then
		return "/"
	end

	local normalized = path:gsub("[/\\]+$", "")
	local name = normalized:match("([^/\\]+)$")
	return name or normalized
end

local function tmux_window_name()
	local success, stdout, _ = wezterm.run_child_process({ "tmux", "display-message", "-p", "#{window_name}" })
	if not success or type(stdout) ~= "string" then
		return nil
	end

	local name = sanitize_title(stdout)
	if name == "" then
		return nil
	end

	return name
end

local function is_noise_title(text)
	local value = sanitize_title(text)
	if value == "" then
		return true
	end

	-- 常见的 shell/tty 噪声标题，例如随机 token、hostname 占位值。
	if value:match("^[A-Z0-9][A-Z0-9%-_]+$") and #value >= 6 then
		return true
	end

	if value == "wezterm" then
		return true
	end

	return false
end

local function looks_like_noisy_tmux_title(text)
	local value = sanitize_title(text)
	if value == "" then
		return false
	end

	-- tmux/terminal title 有时会退化成无语义 token，例如随机 hostname、tty token。
	if value:match("^[A-Z0-9][A-Z0-9%-_]+$") and #value >= 6 then
		return true
	end

	return false
end

local SHELL_LIKE_PROCS = {
	zsh = true,
	bash = true,
	fish = true,
	tmux = true,
}

local function prefers_structured_title(process_name)
	return SHELL_LIKE_PROCS[(process_name or ""):lower()] == true
end

local function process_icon(process_name)
	local proc = (process_name or ""):lower()

	if proc:find("tmux", 1, true) then
		return ""
	end
	if proc:find("nvim", 1, true) or proc:find("vim", 1, true) then
		return ""
	end
	if proc:find("zsh", 1, true) or proc:find("bash", 1, true) or proc:find("fish", 1, true) then
		return ""
	end
	if proc:find("ssh", 1, true) then
		return "󰣀"
	end
	if proc:find("git", 1, true) or proc:find("lazygit", 1, true) then
		return ""
	end
	if proc:find("docker", 1, true) then
		return ""
	end
	if proc:find("python", 1, true) or proc:find("ipython", 1, true) then
		return ""
	end
	if
		proc:find("node", 1, true)
		or proc:find("npm", 1, true)
		or proc:find("pnpm", 1, true)
		or proc:find("yarn", 1, true)
	then
		return ""
	end
	if proc:find("go", 1, true) then
		return ""
	end
	if proc:find("lua", 1, true) then
		return ""
	end
	if proc:find("cargo", 1, true) or proc:find("rust", 1, true) then
		return ""
	end
	if proc:find("htop", 1, true) or proc:find("btop", 1, true) then
		return ""
	end
	if proc:find("top", 1, true) then
		return ""
	end
	if proc:find("yazi", 1, true) then
		return ""
	end
	if proc:find("claude", 1, true) then
		return ICON_CLAUDE
	end
	if proc:find("codex", 1, true) or proc:find("traex", 1, true) then
		return ""
	end

	return "󰆍"
end

local TRANSIENT_SHELL_PROCS = {
	top = true,
	htop = true,
	btop = true,
}

local function display_process_name(process_name)
	local proc = (process_name or ""):lower()
	if TRANSIENT_SHELL_PROCS[proc] then
		-- 这类全屏监控程序通常只是 shell 内的临时前台命令，不应改变 tab 的整体风格。
		return "zsh"
	end

	return process_name or ""
end

local function is_tmux_process(process_name)
	return (process_name or ""):lower() == "tmux"
end

local function create_title(tab, max_width)
	local tab_index = tostring((tab.tab_index or 0) + 1)
	local process_name = clean_process_name(tab.active_pane.foreground_process_name)
	local shown_process_name = display_process_name(process_name)
	local tmux_process = is_tmux_process(shown_process_name)
	local icon = process_icon(shown_process_name)
	local cwd_name = basename(deps.get_pane_cwd(tab.active_pane))
	local base_title = sanitize_title(tab.active_pane.title)
	local tmux_name = tmux_process and tmux_window_name() or nil

	local no_title_procs = {
		claude = true,
		codex = true,
		traex = true,
	}
	if is_noise_title(base_title) then
		base_title = shown_process_name
	end

	if prefers_structured_title(shown_process_name) then
		if (tmux_name and tmux_name ~= "") and (looks_like_noisy_tmux_title(base_title) or base_title == shown_process_name) then
			base_title = tmux_name
		end
		if base_title == "" or base_title == shown_process_name or is_noise_title(base_title) or looks_like_noisy_tmux_title(base_title) then
			base_title = tmux_name or cwd_name or shown_process_name
		end
	elseif tmux_process then
		if looks_like_noisy_tmux_title(base_title) and tmux_name and tmux_name ~= "" then
			base_title = tmux_name
		end
		-- tmux 下 WezTerm 外层 pane 的 cwd 往往不会跟随 tmux window 切换，
		-- 继续优先显示 cwd 会让多个 tab 长时间显示成同一个旧目录。
		if base_title == "" or base_title:lower() == shown_process_name:lower() then
			base_title = tmux_name or cwd_name or shown_process_name
		end
	elseif cwd_name and cwd_name ~= "" then
		base_title = cwd_name
	elseif no_title_procs[shown_process_name:lower()] then
		base_title = shown_process_name
	end

	local title = base_title
	if
		not tmux_process
		and
		not (cwd_name and cwd_name ~= "")
		and shown_process_name ~= ""
		and base_title ~= ""
		and shown_process_name ~= base_title
	then
		title = shown_process_name .. " ~ " .. base_title
	end

	if title == "" then
		title = "shell"
	end

	title = tab_index .. " " .. icon .. " " .. title

	return fit_title(title, (max_width or 25) - 4)
end

local function fallback_title(tab, max_width)
	local tab_index = tostring((tab and tab.tab_index or 0) + 1)
	local title = tab_index .. "  shell"
	return fit_title(title, (max_width or 25) - 4)
end

local function build_tab_cells(tab, hover, max_width)
	local state = "default"
	if tab.is_active then
		state = "active"
	elseif hover then
		state = "hover"
	end

	local text_colors = COLORS["text_" .. state]
	local edge_colors = COLORS["scircle_" .. state]
	local ok_title, title = pcall(create_title, tab, max_width)
	if not ok_title or type(title) ~= "string" or title == "" then
		title = fallback_title(tab, max_width)
	end

	local active_indicator = tab.is_active and {
		{ Foreground = { Color = "#f38ba8" } },
		{ Text = "● " },
	} or nil

	local cells = {
		{ Background = { Color = edge_colors.bg } },
		{ Foreground = { Color = edge_colors.fg } },
		{ Text = ICON_LEFT },
		{ Background = { Color = text_colors.bg } },
		{ Foreground = { Color = text_colors.fg } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = " " },
		{ Background = { Color = edge_colors.bg } },
		{ Foreground = { Color = edge_colors.fg } },
		{ Text = ICON_RIGHT },
	}

	if active_indicator then
		table.insert(cells, 7, active_indicator[1])
		table.insert(cells, 8, active_indicator[2])
		table.insert(cells, 9, { Foreground = { Color = text_colors.fg } })
		table.insert(cells, 10, { Text = title .. " " })
	else
		table.insert(cells, 7, { Text = title .. " " })
		table.insert(cells, 7, { Foreground = { Color = text_colors.fg } })
	end

	return cells
end

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local ok, cells = pcall(build_tab_cells, tab, hover, max_width)
	if ok and type(cells) == "table" then
		return cells
	end

	local state = tab.is_active and "active" or (hover and "hover" or "default")
	local text_colors = COLORS["text_" .. state]
	local edge_colors = COLORS["scircle_" .. state]
	local title = fallback_title(tab, max_width)

	return {
		{ Background = { Color = edge_colors.bg } },
		{ Foreground = { Color = edge_colors.fg } },
		{ Text = ICON_LEFT },
		{ Background = { Color = text_colors.bg } },
		{ Foreground = { Color = text_colors.fg } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = " " },
		{ Foreground = { Color = text_colors.fg } },
		{ Text = title .. " " },
		{ Background = { Color = edge_colors.bg } },
		{ Foreground = { Color = edge_colors.fg } },
		{ Text = ICON_RIGHT },
	}
end)

local init = require("config/init")
init.register("tabs", tabs_config)
