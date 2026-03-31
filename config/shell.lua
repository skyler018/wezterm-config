local shell_config = {}

-- ===== Shell =====
local user_shell = os.getenv('SHELL')
if user_shell and #user_shell > 0 then
  shell_config.default_prog = { user_shell, '-l' }
else
  shell_config.default_prog = { '/bin/zsh', '-l' }
end

local init = require 'config/init'
init.register('shell', shell_config)
