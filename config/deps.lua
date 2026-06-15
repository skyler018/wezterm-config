local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}
local command_exists_cache = {}

-- 只管理与键映射强相关的第三方工具（根据确认：不纳入 traecli）
local MANAGED_BINS = {
  { bin = 'yazi', brew = 'yazi' },
  { bin = 'lazygit', brew = 'lazygit' },
  { bin = 'claude', brew = 'claude' },
  { bin = 'codex', brew = 'codex' },
}

local function trim(s)
  return (s or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function shell_quote(s)
  -- POSIX shell 单引号转义：' => '\''
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function M.percent_decode(s)
  return (s:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

function M.get_shell()
  local shell = os.getenv('SHELL')
  if shell and #shell > 0 then
    return shell
  end
  return '/bin/zsh'
end

function M.command_exists(bin)
  local cached = command_exists_cache[bin]
  if cached ~= nil then
    return cached[1], cached[2]
  end

  local path_env = os.getenv('PATH') or ''
  for dir in string.gmatch(path_env, '([^:]+)') do
    local candidate = dir .. '/' .. bin
    local ok, stdout, stderr = wezterm.run_child_process({ '/bin/sh', '-c', '[ -x "$1" ] && printf "%s" "$1"', 'sh', candidate })
    local path = trim(stdout)
    if ok and #path > 0 then
      command_exists_cache[bin] = { true, path }
      return true, path
    end
  end

  -- PATH 内未找到时，再回退到 login shell，兼容 alias/path_helper 等环境注入。
  local shell = M.get_shell()
  local ok, stdout = wezterm.run_child_process({ shell, '-lc', 'command -v ' .. shell_quote(bin) })
  local path = trim(stdout)
  if ok and #path > 0 then
    command_exists_cache[bin] = { true, path }
    return true, path
  end
  command_exists_cache[bin] = { false, nil }
  return false, nil
end

function M.get_missing_managed_deps()
  local missing = {}
  for _, item in ipairs(MANAGED_BINS) do
    local exists = M.command_exists(item.bin)
    if not exists then
      table.insert(missing, item)
    end
  end
  return missing
end

function M.get_missing_dep(bin)
  return M.get_missing_for_bins({ bin })
end

function M.get_missing_for_bins(bins)
  if type(bins) ~= 'table' or #bins == 0 then
    return {}
  end

  local wanted = {}
  for _, bin in ipairs(bins) do
    if type(bin) == 'string' and #bin > 0 then
      wanted[bin] = true
    end
  end

  local missing = {}
  for _, item in ipairs(MANAGED_BINS) do
    if wanted[item.bin] then
      local exists = M.command_exists(item.bin)
      if not exists then
        table.insert(missing, item)
      end
    end
  end
  return missing
end

local function list_to_csv(items)
  local parts = {}
  for _, item in ipairs(items) do
    table.insert(parts, item.bin)
  end
  return table.concat(parts, ', ')
end

function M.install_with_brew(window, pane, missing)
  local has_brew = M.command_exists('brew')
  if not has_brew then
    window:toast_notification(
      'WezTerm',
      '未检测到 Homebrew（brew）。请先安装：https://brew.sh',
      nil,
      10000
    )
    return
  end

  local pkgs = {}
  for _, item in ipairs(missing) do
    table.insert(pkgs, item.brew)
  end

  local shell = M.get_shell()
  local cmd = 'brew install ' .. table.concat(pkgs, ' ')
  window:perform_action(
    act.SpawnCommandInNewTab({
      args = { shell, '-lc', cmd },
    }),
    pane
  )
end

function M.prompt_install(window, pane, missing)
  if #missing == 0 then
    return
  end

  local has_brew = M.command_exists('brew')
  local title = '缺少依赖：' .. list_to_csv(missing)
  local description
  if has_brew then
    local pkgs = {}
    for _, item in ipairs(missing) do
      table.insert(pkgs, item.brew)
    end
    description = '确认后将在新标签页执行：brew install ' .. table.concat(pkgs, ' ')
  else
    description = '未检测到 brew。请先安装 Homebrew：https://brew.sh'
  end

  local choices = {}
  if has_brew then
    table.insert(choices, { id = 'install', label = 'Install now (brew)' })
  else
    table.insert(choices, { id = 'open_brew', label = 'Open brew.sh' })
  end
  table.insert(choices, { id = 'later', label = 'Not now' })

  window:perform_action(
    act.InputSelector({
      title = title,
      description = description,
      choices = choices,
      action = wezterm.action_callback(function(win, p, id)
        if id == 'install' then
          M.install_with_brew(win, p, missing)
        elseif id == 'open_brew' then
          local ok, err = pcall(function()
            wezterm.open_with('https://brew.sh')
          end)
          if not ok then
            win:toast_notification('WezTerm', '打开 brew.sh 失败：' .. tostring(err), nil, 8000)
          end
        end
      end),
    }),
    pane
  )
end

wezterm.on('gui-startup', function(cmd)
  wezterm.mux.spawn_window(cmd or {})
end)

return M
