local wezterm = require 'wezterm'
local init = require 'config/init'
local is_macos = wezterm.target_triple and wezterm.target_triple:find('darwin', 1, true) ~= nil

-- 业务配置：显式控制加载/覆盖顺序（theme 最后）
require 'config/deps'
require 'config/font'
require 'config/window'
if is_macos then
  require 'config/macos'
end
require 'config/shell'
require 'config/cursor'
require 'config/tabs'
require 'config/keys'
require 'config/theme'

return init.build()
