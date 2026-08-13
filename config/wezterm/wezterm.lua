local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()

local ubuntu_devops = { 'wsl.exe', '-d', 'Ubuntu', '--cd', '~', '--exec', 'bash', '-l' }
local powershell7 = { 'pwsh.exe', '-NoLogo' }
local openclaw_cli = {
  'pwsh.exe',
  '-NoLogo',
  '-NoExit',
  '-Command',
  [[
$root = 'D:\AI\OpenClaw'
if (Test-Path -LiteralPath $root) {
  Set-Location -LiteralPath $root
}
$openclaw = Get-Command openclaw -ErrorAction SilentlyContinue
$clawops = Get-Command clawops -ErrorAction SilentlyContinue
Write-Host ''
Write-Host '=== OpenClaw / clawops ===' -ForegroundColor Cyan
Write-Host "Racine : $root"
if ($openclaw) {
  Write-Host "[OK] openclaw : $($openclaw.Source)" -ForegroundColor Green
} else {
  Write-Host '[À FAIRE] openclaw introuvable. Installe/valide OpenClaw puis relance WezTerm.' -ForegroundColor Yellow
}
if ($clawops) {
  Write-Host "[OK] clawops  : $($clawops.Source)" -ForegroundColor Green
} else {
  Write-Host '[À FAIRE] clawops introuvable. Installe/valide OpenClaw puis relance WezTerm.' -ForegroundColor Yellow
}
if ($openclaw -and $clawops) {
  Write-Host '[PRÊT] Session CLI Windows-native prête.' -ForegroundColor Green
  Write-Host 'Exemples : openclaw --version | clawops version | clawops platform check'
}
Write-Host ''
  ]],
}

-- Windows 11 host -> Ubuntu WSL2 -> Bash DevOps.
-- Ubuntu reste le profil quotidien par défaut ; OpenClaw/clawops restent Windows-native.
config.default_prog = ubuntu_devops
config.launch_menu = {
  {
    label = 'Ubuntu DevOps (WSL2)',
    args = ubuntu_devops,
  },
  {
    label = 'PowerShell 7',
    args = powershell7,
  },
  {
    label = 'OpenClaw / clawops (Windows)',
    args = openclaw_cli,
  },
}

config.font = wezterm.font_with_fallback {
  'JetBrainsMono Nerd Font',
  'Cascadia Mono',
  'Consolas',
}
config.font_size = 12.5
config.line_height = 1.05
config.cell_width = 1.0
config.freetype_load_target = 'Normal'
config.freetype_render_target = 'HorizontalLcd'

config.colors = {
  foreground = '#d8dee9',
  background = '#111318',
  cursor_bg = '#88c0d0',
  cursor_fg = '#111318',
  cursor_border = '#88c0d0',
  selection_fg = '#eceff4',
  selection_bg = '#434c5e',
  scrollbar_thumb = '#4c566a',
  split = '#4c566a',
  ansi = {
    '#2e3440', '#bf616a', '#a3be8c', '#ebcb8b',
    '#81a1c1', '#b48ead', '#88c0d0', '#e5e9f0',
  },
  brights = {
    '#4c566a', '#bf616a', '#a3be8c', '#ebcb8b',
    '#81a1c1', '#b48ead', '#8fbcbb', '#eceff4',
  },
}

config.check_for_updates = true
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = false
config.show_new_tab_button_in_tab_bar = true
config.window_close_confirmation = 'NeverPrompt'
config.scrollback_lines = 50000
config.adjust_window_size_when_changing_font_size = false
config.window_padding = { left = 8, right = 8, top = 6, bottom = 6 }
config.inactive_pane_hsb = { saturation = 0.85, brightness = 0.70 }
config.default_cursor_style = 'BlinkingBar'
config.cursor_blink_rate = 650
config.animation_fps = 60
config.max_fps = 120

config.keys = {
  { key = 't', mods = 'CTRL|SHIFT', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentTab { confirm = false } },
  { key = 'f', mods = 'CTRL|SHIFT', action = act.Search 'CurrentSelectionOrEmptyString' },
  { key = 'p', mods = 'CTRL|SHIFT', action = act.ActivateCommandPalette },
  { key = 'Enter', mods = 'ALT', action = act.ToggleFullScreen },
  { key = '\\', mods = 'CTRL|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = '-', mods = 'CTRL|SHIFT', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'LeftArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Left' },
  { key = 'RightArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Right' },
  { key = 'UpArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Up' },
  { key = 'DownArrow', mods = 'ALT', action = act.ActivatePaneDirection 'Down' },
}

return config
