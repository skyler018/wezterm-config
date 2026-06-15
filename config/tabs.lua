local wezterm = require("wezterm")
local deps = require("config/deps")

local tabs_config = {}
local nf = wezterm.nerdfonts

tabs_config.enable_tab_bar = true
tabs_config.tab_bar_at_bottom = true
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

local function sanitize_title(text)
	text = trim(text or "")
	-- 去掉常见 ANSI/OSC 控制序列与不可见控制字符，避免全屏 TUI 污染 tab 标题渲染。
	text = text:gsub("\27%][^\7]*\7", "")
	text = text:gsub("\27%[[%d;?]*[%a]", "")
	text = text:gsub("[%c]", " ")
	text = text:gsub("%s+", " ")
	return trim(text)
end

local function get_pane_cwd(pane)
	if not pane then
		return nil
	end

	local cwd_uri = pane.current_working_dir
	if cwd_uri == nil and type(pane.get_current_working_dir) == "function" then
		cwd_uri = pane:get_current_working_dir()
	end
	if not cwd_uri then
		return nil
	end

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
		local path_from_uri = cwd_str:gsub("^file://", "")
		path_from_uri = path_from_uri:gsub("^/*", "/")
		return deps.percent_decode(path_from_uri)
	end

	return nil
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

local function process_icon(process_name)
	local proc = (process_name or ""):lower()

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

local function create_title(tab, max_width)
	local tab_index = tostring((tab.tab_index or 0) + 1)
	local process_name = clean_process_name(tab.active_pane.foreground_process_name)
	local shown_process_name = display_process_name(process_name)
	local icon = process_icon(shown_process_name)
	local cwd_name = basename(get_pane_cwd(tab.active_pane))
	local base_title = sanitize_title(tab.active_pane.title)

	local no_title_procs = {
		claude = true,
		codex = true,
		traex = true,
	}
	if base_title == "" or base_title == "wezterm" then
		base_title = shown_process_name
	end

	if cwd_name and cwd_name ~= "" then
		base_title = cwd_name
	elseif no_title_procs[shown_process_name:lower()] then
		base_title = shown_process_name
	end

	local title = base_title
	if
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

	local inner_max = math.max(6, (max_width or 25) - 4)
	if #title > inner_max then
		title = title:sub(1, inner_max - 1) .. "…"
	end

	if #title < inner_max then
		title = title .. string.rep(" ", inner_max - #title)
	end

	return title
end

local function fallback_title(tab, max_width)
	local tab_index = tostring((tab and tab.tab_index or 0) + 1)
	local inner_max = math.max(6, (max_width or 25) - 4)
	local title = tab_index .. "  shell"

	if #title > inner_max then
		title = title:sub(1, inner_max - 1) .. "…"
	end
	if #title < inner_max then
		title = title .. string.rep(" ", inner_max - #title)
	end

	return title
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
