-- Pull in the wezterm API
local wezterm = require 'wezterm'
local act = wezterm.action

-- This will hold the configuration.
local config = wezterm.config_builder()



-- This is where you actually apply your config choices

-- For example, changing the color scheme:
config.color_scheme = 'OneHalfDark'
config.font = wezterm.font 'Hack Nerd Font'

config.wsl_domains = {
  {
    -- The name of this specific domain.  Must be unique amonst all types
    -- of domain in the configuration file.
    name = 'WSL:Ubuntu',

    -- The name of the distribution.  This identifies the WSL distribution.
    -- It must match a valid distribution from your `wsl -l -v` output in
    -- order for the domain to be useful.
    distribution = 'Ubuntu-24.04',
    default_cwd = '~'
  },
}

config.window_decorations = "RESIZE"

local isWindows = string.find(wezterm.target_triple, "windows")

if isWindows then
  config.default_domain = 'WSL:Ubuntu'
end

if not isWindows then
  config.font_size = 16
end

config.window_close_confirmation = 'NeverPrompt'
config.audible_bell = "Disabled"

local mux = wezterm.mux

wezterm.on("gui-startup", function()
  local tab, pane, window = mux.spawn_window {}
  window:gui_window():maximize()
end)


config.leader = { key = "b", mods = "CTRL" }

config.keys = {
  -- Tmux like commands
  {
    mods = "LEADER",
    key = "c",
    action = act.SpawnTab "CurrentPaneDomain"
  },
  {
    mods = "CTRL",
    key = "w",
    action = act.CloseCurrentTab { confirm = false }
  },
  {
    mods = "ALT",
    key = "h",
    action = act.ActivateTabRelative(-1)
  },
  {
    mods = "ALT",
    key = "l",
    action = act.ActivateTabRelative(1)
  },
  {
    mods = "LEADER|SHIFT",
    key = '"',
    action = act.SplitHorizontal { domain = "CurrentPaneDomain" }
  },
  {
    mods = "LEADER|SHIFT",
    key = "%",
    action = act.SplitVertical { domain = "CurrentPaneDomain" }
  },
  {
    mods = "LEADER",
    key = "1",
    action = act.ActivateTab(0)
  },
  {
    mods = "LEADER",
    key = "2",
    action = act.ActivateTab(1)
  },
  {
    mods = "LEADER",
    key = "3",
    action = act.ActivateTab(2)
  },
  {
    mods = "LEADER",
    key = "4",
    action = act.ActivateTab(3)
  },
  {
    mods = "LEADER",
    key = "5",
    action = act.ActivateTab(4)
  },
  {
    mods = "LEADER",
    key = "6",
    action = act.ActivateTab(5)
  },
  {
    mods = "LEADER",
    key = "7",
    action = act.ActivateTab(6)
  },
  {
    mods = "LEADER",
    key = "8",
    action = act.ActivateTab(8)
  },
  -- LEADER, followed by 'r' will put us in resize-pane
  -- mode until we cancel that mode.
  {
    key = 'r',
    mods = 'LEADER',
    action = act.ActivateKeyTable {
      name = 'resize_pane',
      one_shot = false,
    },
  },
  -- LEADER, followed by 'a' will put us in activate-pane
  -- mode until we press some other key or until 1 second (1000ms)
  -- of time elapses
  {
    key = 'a',
    mods = 'LEADER',
    action = act.ActivateKeyTable {
      name = 'activate_pane',
      one_shot = false
    },
  },
}

config.key_tables = {
  -- Defines the keys that are active in our resize-pane mode.
  -- Since we're likely to want to make multiple adjustments,
  -- we made the activation one_shot=false. We therefore need
  -- to define a key assignment for getting out of this mode.
  -- 'resize_pane' here corresponds to the name="resize_pane" in
  -- the key assignments above.
  resize_pane = {
    { key = 'LeftArrow',  action = act.AdjustPaneSize { 'Left', 1 } },
    { key = 'h',          action = act.AdjustPaneSize { 'Left', 1 } },

    { key = 'RightArrow', action = act.AdjustPaneSize { 'Right', 1 } },
    { key = 'l',          action = act.AdjustPaneSize { 'Right', 1 } },

    { key = 'UpArrow',    action = act.AdjustPaneSize { 'Up', 1 } },
    { key = 'k',          action = act.AdjustPaneSize { 'Up', 1 } },

    { key = 'DownArrow',  action = act.AdjustPaneSize { 'Down', 1 } },
    { key = 'j',          action = act.AdjustPaneSize { 'Down', 1 } },

    -- Cancel the mode by pressing escape
    { key = 'Escape',     action = 'PopKeyTable' },
  },

  -- Defines the keys that are active in our activate-pane mode.
  -- 'activate_pane' here corresponds to the name="activate_pane" in
  -- the key assignments above.
  activate_pane = {
    { key = 'h',      action = act.ActivatePaneDirection 'Left' },
    { key = 'l',      action = act.ActivatePaneDirection 'Right' },
    { key = 'k',      action = act.ActivatePaneDirection 'Up' },
    { key = 'j',      action = act.ActivatePaneDirection 'Down' },
    { key = 'n',      action = act.ActivatePaneDirection 'Next' },
    { key = 'p',      action = act.ActivatePaneDirection 'Prev' },
    -- Cancel the mode by pressing escape
    { key = 'Escape', action = 'PopKeyTable' },
  },
}

-- Show which key table is active in the status area
wezterm.on('update-right-status', function(window, pane)
  local name = window:active_key_table()
  if name then
    name = 'TABLE: ' .. name
  end
  window:set_right_status(name or '')
end)

-- and finally, return the configuration to wezterm
return config
