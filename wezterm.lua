local init = require 'config/init'

-- 业务配置：显式控制加载/覆盖顺序（theme 最后）
require 'config/deps'
require 'config/font'
require 'config/window'
require 'config/macos'
require 'config/shell'
require 'config/cursor'
require 'config/tabs'
require 'config/keys'
require 'config/theme'

return init.build()
