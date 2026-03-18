local wezterm = require 'wezterm'

local M = {}
-- 预先放入 package.loaded，用于打破循环引用：
-- init.build() 会 require 各模块；各模块也会 require('config/init') 来注册自己。
package.loaded['config/init'] = M

local registry = {}

function M.register(name, fragment_or_fn)
  table.insert(registry, {
    name = name,
    item = fragment_or_fn,
  })
end

local function apply_fragment(config, fragment)
  for k, v in pairs(fragment) do
    config[k] = v
  end
end

function M.build()
  local config = {}
  if wezterm.config_builder then
    config = wezterm.config_builder()
  end

  for _, entry in ipairs(registry) do
    local item = entry.item
    if type(item) == 'function' then
      item(config, wezterm)
    elseif type(item) == 'table' then
      apply_fragment(config, item)
    else
      error('config/init: invalid registry item for ' .. tostring(entry.name))
    end
  end

  return config
end

return M
