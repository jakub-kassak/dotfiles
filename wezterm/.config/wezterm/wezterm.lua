-- https://diego.codes/post/honing-the-tools/02-wezterm/
local wezterm = require("wezterm")

local config = wezterm.config_builder()

-- For example, changing the color scheme:

local function depending_on_appearance(arg)
	local appearance = wezterm.gui.get_appearance()
	if appearance:find("Dark") then
		return arg.dark
	else
		return arg.light
	end
end

config.initial_rows = 35
config.initial_cols = 110
config.color_scheme = depending_on_appearance({
	light = "Tokyo Night Moon", -- "Vs Code Light+ (Gogh)", -- 3024 (light) (terminal.sexy)", --One Light (Gogh)", --Vs Code Light+ (Gogh)", -- Catppuccin Latte',
	dark = "Tokyo Night", -- "Vs Code Dark+ (Gogh)", --3024 (dark) (terminal.sexy)", -- Catppuccin Mocha",
})
config.use_fancy_tab_bar = false
config.tab_max_width = 32
config.colors = {
	tab_bar = {
		active_tab = depending_on_appearance({
			light = { fg_color = "#f8f8f2", bg_color = "#209fb5" },
			dark = { fg_color = "#6c7086", bg_color = "#74c7ec" },
		}),
	},
}
config.window_decorations = "RESIZE|TITLE"

config.font_size = 15

config.keys = {
	-- Copy to clipboard using Ctrl+C
	{ key = "c", mods = "CTRL", action = wezterm.action({ CopyTo = "Clipboard" }) },

	-- Send interrupt signal (SIGINT) using Ctrl+Shift+C
	{ key = "c", mods = "CTRL|SHIFT", action = wezterm.action({ SendKey = { key = "c", mods = "CTRL" } }) },

	-- Paste from clipboard using Ctrl+V
	{ key = "v", mods = "CTRL", action = wezterm.action({ PasteFrom = "Clipboard" }) },

	-- Send Ctrl+V key combination using Ctrl+Shift+V
	{ key = "v", mods = "CTRL|SHIFT", action = wezterm.action({ SendKey = { key = "v", mods = "CTRL" } }) },

	-- Send Ctrl+V key combination using SUPER+V
	{ key = "v", mods = "SUPER", action = wezterm.action({ SendKey = { key = "v", mods = "CTRL" } }) },

	-- Send interrupt signal (SIGINT) using Super+C
	{ key = "c", mods = "SUPER", action = wezterm.action({ SendKey = { key = "c", mods = "CTRL" } }) },

	-- Show tab navigator
	{
		key = "p",
		mods = "CTRL",
		action = wezterm.action.ShowTabNavigator,
	},
	-- Show launcher menu
	{
		key = "P",
		mods = "CTRL|SHIFT",
		action = wezterm.action.ShowLauncher,
	},
	-- Vertical pipe (|) -> horizontal split
	{
		key = "|",
		mods = "SUPER|SHIFT",
		action = wezterm.action.SplitHorizontal({
			domain = "CurrentPaneDomain",
		}),
	},
	-- Underscore (_) -> vertical split
	{
		key = "_",
		mods = "SUPER|SHIFT",
		action = wezterm.action.SplitVertical({
			domain = "CurrentPaneDomain",
		}),
	},
	-- Use CTRL + [h|j|k|l] to move between panes
	{
		key = "h",
		mods = "SUPER|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Left"),
	},

	{
		key = "j",
		mods = "SUPER|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Down"),
	},

	{
		key = "k",
		mods = "SUPER|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Up"),
	},

	{
		key = "l",
		mods = "SUPER|SHIFT",
		action = wezterm.action.ActivatePaneDirection("Right"),
	},
	-- Rename current tab
	{
		key = "E",
		mods = "SUPER|SHIFT",
		action = wezterm.action.PromptInputLine({
			description = "Enter new name for tab",
			action = wezterm.action_callback(function(window, _, line)
				if line then
					window:active_tab():set_title(line)
				end
			end),
		}),
	},

	-- Move to a pane (prompt to which one)
	{
		mods = "SUPER|SHIFT",
		key = "m",
		action = wezterm.action.PaneSelect,
	},
}

config.pane_focus_follows_mouse = false

return config
