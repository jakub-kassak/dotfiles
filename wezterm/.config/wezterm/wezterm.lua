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

local act = wezterm.action
config.keys = {
	-- Copy to clipboard using Ctrl+C
	{
		key = "c",
		mods = "CTRL",
		action = wezterm.action_callback(function(win, pane)
			local has_selection = win:get_selection_text_for_pane(pane) ~= ""
			if has_selection then
				-- Copy the selection to the clipboard
				win:perform_action(wezterm.action.CopyTo("Clipboard"), pane)
				-- Clear the selection
				win:perform_action(wezterm.action.ClearSelection, pane)
			else
				-- Send Ctrl+C if no selection is present
				win:perform_action(wezterm.action.SendKey({ key = "c", mods = "CTRL" }), pane)
			end
		end),
	},
	-- { key = "c", mods = "CTRL", action = act({ CopyTo = "Clipboard" }) },
	-- Paste from clipboard using Ctrl+V
	{ key = "v", mods = "CTRL", action = act({ PasteFrom = "Clipboard" }) },
	{ key = "v", mods = "CTRL|SHIFT", action = act.SendKey({ key = "v", mods = "CTRL" }) },
	-- Close the current tab
	{ key = "w", mods = "CTRL", action = act({ CloseCurrentTab = { confirm = true } }) },

	-- Search with Crtl+F
	{ key = "f", mods = "CTRL|SHIFT", action = act.Search("CurrentSelectionOrEmptyString") },

	-- Show tab navigator
	-- { key = "p", mods = "CTRL", action = act.ShowTabNavigator },
	-- Show launcher menu
	{ key = "P", mods = "CTRL|SHIFT", action = act.ShowLauncher },
	-- Spawn a new tab
	{ key = "t", mods = "CTRL", action = act({ SpawnTab = "CurrentPaneDomain" }) },

	-- Vertical pipe (|) -> horizontal split
	{ key = "|", mods = "CTRL|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	-- Underscore (_) -> vertical split
	{ key = "_", mods = "CTRL|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	-- Use CTRL + [h|j|k|l] to move between panes
	{ key = "h", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Right") },

	-- Move to another tab (next or previous) using CTRL+[ or CTRL+]
	{ key = "[", mods = "CTRL", action = wezterm.action.ActivateTabRelative(-1) },
	{ key = "]", mods = "CTRL", action = wezterm.action.ActivateTabRelative(1) },

	-- Activate the last tab
	{ key = "Tab", mods = "CTRL", action = act.ActivateLastTab },
	-- { key = "Tab", mods = "CTRL", action = act.SendKey{key = "Tab", mods = "CTRL"} },

	-- Rename current tab with CTRL + SHIFT + e
	{
		key = "e",
		mods = "CTRL|SHIFT",
		action = act.PromptInputLine({
			description = "Enter new name for tab",
			action = wezterm.action_callback(function(window, _, line)
				if line then
					window:active_tab():set_title(line)
				end
			end),
		}),
	},

	-- Move to a pane (prompt to which one)
	{ mods = "CTRL|SHIFT", key = "m", action = act.PaneSelect },
}

config.pane_focus_follows_mouse = false
config.quick_select_patterns = {
	"(?<=[$] ).{1,100}",
	'(?<=")[a-z][^"]+',
}

config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
return config
