local wezterm = require("wezterm")

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
	text_default = { bg = "#45475a", fg = "#1c1b19" },
	text_hover = { bg = "#7188b0", fg = "#1c1b19" },
	text_active = { bg = "#89b4fa", fg = "#11111b" },
	scircle_default = { bg = "rgba(0, 0, 0, 0.4)", fg = "#45475a" },
	scircle_hover = { bg = "rgba(0, 0, 0, 0.4)", fg = "#7188b0" },
	scircle_active = { bg = "rgba(0, 0, 0, 0.4)", fg = "#89b4fa" },
}

local function clean_process_name(proc)
	local name = (proc or ""):gsub(".*[/\\](.*)", "%1")
	return name:gsub("%.exe$", "")
end

local function trim(text)
	return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
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
	if proc:find("yazi", 1, true) then
		return ""
	end
	if proc:find("claude", 1, true) then
		return ICON_CLAUDE
	end
	if proc:find("codex", 1, true) or proc:find("trae", 1, true) then
		return ""
	end

	return "󰆍"
end

local function create_title(tab, max_width)
	local tab_index = tostring((tab.tab_index or 0) + 1)
	local process_name = clean_process_name(tab.active_pane.foreground_process_name)
	local icon = process_icon(process_name)
	local base_title = trim(tab.active_pane.title)

	local no_title_procs = { claude = true, codex = true, trae = true }
	if no_title_procs[process_name:lower()] or base_title == "" or base_title == "wezterm" then
		base_title = process_name
	end

	local title = base_title
	if process_name ~= "" and base_title ~= "" and process_name ~= base_title then
		title = process_name .. " ~ " .. base_title
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

wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local state = "default"
	if tab.is_active then
		state = "active"
	elseif hover then
		state = "hover"
	end

	local text_colors = COLORS["text_" .. state]
	local edge_colors = COLORS["scircle_" .. state]
	local title = create_title(tab, max_width)
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
	end

	return cells
end)

local init = require("config/init")
init.register("tabs", tabs_config)
