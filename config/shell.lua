local shell_config = {}

-- ===== Shell =====
local user_shell = os.getenv('SHELL')
if user_shell and #user_shell > 0 then
  shell_config.default_prog = { user_shell, '-l' }
else
  shell_config.default_prog = { '/bin/zsh', '-l' }
end

-- TERM（兼容部分 CLI 程序的识别逻辑）
shell_config.term = 'xterm-256color'

local init = require 'config/init'
init.register('shell', shell_config)
