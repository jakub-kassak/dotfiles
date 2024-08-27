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
	-- Close the current tab
	{ key = "w", mods = "CTRL", action = act({ CloseCurrentTab = { confirm = true } }) },

	{ key = "a", mods = "SUPER", action = act({ SendKey = { key = "a", mods = "CTRL" } }) },
	{ key = "c", mods = "SUPER", action = act({ SendKey = { key = "c", mods = "CTRL" } }) },
	{ key = "d", mods = "SUPER", action = act({ SendKey = { key = "d", mods = "CTRL" } }) },
	{ key = "e", mods = "SUPER", action = act({ SendKey = { key = "e", mods = "CTRL" } }) },
	{ key = "h", mods = "SUPER", action = act({ SendKey = { key = "h", mods = "CTRL" } }) },
	{ key = "j", mods = "SUPER", action = act({ SendKey = { key = "j", mods = "CTRL" } }) },
	{ key = "k", mods = "SUPER", action = act({ SendKey = { key = "k", mods = "CTRL" } }) },
	{ key = "l", mods = "SUPER", action = act({ SendKey = { key = "l", mods = "CTRL" } }) },
	{ key = "l", mods = "SUPER", action = act({ SendKey = { key = "l", mods = "CTRL" } }) },
	{ key = "o", mods = "SUPER", action = act({ SendKey = { key = "o", mods = "CTRL" } }) },
	{ key = "p", mods = "SUPER", action = act({ SendKey = { key = "p", mods = "CTRL" } }) },
	{ key = "r", mods = "SUPER", action = act({ SendKey = { key = "r", mods = "CTRL" } }) },
	{ key = "v", mods = "SUPER", action = act({ SendKey = { key = "v", mods = "CTRL" } }) },
	{ key = "y", mods = "SUPER", action = act({ SendKey = { key = "y", mods = "CTRL" } }) },
	{ key = "z", mods = "SUPER", action = act({ SendKey = { key = "z", mods = "CTRL" } }) },
	{ key = "f", mods = "SUPER", action = act({ SendKey = { key = "f", mods = "CTRL" } }) },
	{ key = "/", mods = "SUPER", action = act({ SendKey = { key = "/", mods = "CTRL" } }) },
	{ key = "]", mods = "SUPER", action = act({ SendKey = { key = "]", mods = "CTRL" } }) },
	-- Send Ctrl + [ with SUPER + [
	{ key = "[", mods = "SUPER", action = act({ SendKey = { key = "[", mods = "CTRL" } }) },
	-- Send Ctrl + tab with SUPER + tab
	{ key = "Tab", mods = "SUPER", action = act({ SendKey = { key = "Tab", mods = "CTRL" } }) },
	{ key = " ", mods = "SUPER", action = act({ SendKey = { key = " ", mods = "CTRL" } }) },
	-- Send ctrl + t with SUPER + t
	{ key = "t", mods = "SUPER", action = act({ SendKey = { key = "t", mods = "CTRL" } }) },
	-- Send Alt + c with SUPER + SHIFT + c
	{ key = "c", mods = "SUPER|SHIFT", action = act({ SendKey = { key = "c", mods = "ALT" } }) },

	-- Search with Crtl+F
	{ key = "f", mods = "CTRL", action = act.Search("CurrentSelectionOrEmptyString") },

	-- Show tab navigator
	{ key = "p", mods = "CTRL", action = act.ShowTabNavigator },
	-- Show launcher menu
	{ key = "P", mods = "CTRL|SHIFT", action = act.ShowLauncher },
	-- Spawn a new tab
	{ key = "t", mods = "CTRL", action = act({ SpawnTab = "CurrentPaneDomain" }) },

	-- Vertical pipe (|) -> horizontal split
	{ key = "|", mods = "CTRL|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	-- Underscore (_) -> vertical split
	{ key = "_", mods = "CTRL|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	-- Use CTRL + [h|j|k|l] to move between panes
	{ key = "h", mods = "CTRL", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "CTRL", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "CTRL", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "CTRL", action = act.ActivatePaneDirection("Right") },

	-- Move to another tab (next or previous) using CTRL+[ or CTRL+]
	{ key = "LeftArrow", mods = "CTRL|ALT", action = wezterm.action.ActivateTabRelative(-1) },
	{ key = "RightArrow", mods = "CTRL|ALT", action = wezterm.action.ActivateTabRelative(1) },

	-- Activate the last tab
	{ key = "Tab", mods = "CTRL", action = act.ActivateLastTab },

	-- Rename current tab with CTRL+e
	{
		key = "e",
		mods = "CTRL",
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
	{ mods = "CTRL", key = "m", action = act.PaneSelect },
}

config.pane_focus_follows_mouse = false
config.quick_select_patterns = {
	"(?<=[$] ).{1,100}",
	'(?<=")[a-z][^"]+',
}

config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
return config
