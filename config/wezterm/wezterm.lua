local wezterm = require 'wezterm'

local config = wezterm.config_builder()

config.default_prog = { 'wsl.exe', '-d', 'Ubuntu', '--cd', '~' }
config.default_cwd = '~'
config.check_for_updates = true
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.window_close_confirmation = 'NeverPrompt'
config.scrollback_lines = 20000
config.adjust_window_size_when_changing_font_size = false

return config
