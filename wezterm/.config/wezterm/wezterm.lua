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
-- Define the default color scheme based on appearance
local default_color_scheme = depending_on_appearance({
	light = "Builtin Solarized Light", --"Tokyo Night Day", -- Color scheme for light mode
	dark = "Builtin Solarized Dark", -- Color scheme for dark mode
})
config.color_scheme = default_color_scheme
-- local file = io.open(wezterm.config_dir .. "/colorscheme", "r")
-- if file then
-- 	config.color_scheme = default_color_scheme
-- 	-- config.color_scheme = file:read("*a")
-- 	file:close()
-- else
-- 	config.color_scheme = default_color_scheme
-- 	-- config.color_scheme = "Tokyo Night Day"
-- end

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
config.window_decorations = "RESIZE"

config.font_size = 13

local act = wezterm.action
config.keys = {
	{
		key = "PageUp",
		mods = "NONE",
		action = wezterm.action.ScrollByLine(-3),
	},
	-- Scroll down by 3 lines
	{
		key = "PageDown",
		mods = "NONE",
		action = wezterm.action.ScrollByLine(3),
	},
	{
		key = "Enter",
		mods = "CMD|SHIFT",
		action = wezterm.action.SpawnCommandInNewWindow({
			args = { "zsh" },
		}),
	},

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
	-- -- Close the current tab
	{ key = "w", mods = "CMD", action = act({ CloseCurrentTab = { confirm = true } }) },

	-- Show tab navigator
	{ key = "p", mods = "SUPER", action = act.ShowTabNavigator },
	-- Show launcher menu
	{ key = "P", mods = "SUPER|SHIFT", action = act.ShowLauncher },
	-- Spawn a new tab
	{ key = "t", mods = "CMD", action = act({ SpawnTab = "CurrentPaneDomain" }) },

	-- Vertical pipe (|) -> horizontal split
	{ key = "|", mods = "CTRL|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	-- Underscore (_) -> vertical split
	{ key = "_", mods = "CTRL|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

	-- Use CTRL + SHIFT + [h|j|k|l] to move between panes
	{ key = "h", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Right") },

	-- Move to another tab (next or previous) using CTRL+[ or CTRL+]
	{ key = "[", mods = "CTRL", action = wezterm.action.ActivateTabRelative(-1) },
	{ key = "]", mods = "CTRL", action = wezterm.action.ActivateTabRelative(1) },

	-- Activate the last tab
	-- { key = "Tab", mods = "CTRL", action = act.ActivateLastTab },
	-- { key = "Tab", mods = "CTRL", action = act.SendKey{key = "Tab", mods = "CTRL"} },

	-- Rename current tab with CTRL + SHIFT + e
	{
		key = "E",
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
	{ mods = "CTRL|SHIFT", key = "M", action = act.PaneSelect },

	-- Switch to tab 1, 2, ...  <C-1,2,...>
	{ key = "1", mods = "CTRL", action = wezterm.action({ ActivateTab = 0 }) },
	{ key = "2", mods = "CTRL", action = wezterm.action({ ActivateTab = 1 }) },
	{ key = "3", mods = "CTRL", action = wezterm.action({ ActivateTab = 2 }) },
	{ key = "4", mods = "CTRL", action = wezterm.action({ ActivateTab = 3 }) },
	{ key = "5", mods = "CTRL", action = wezterm.action({ ActivateTab = 4 }) },
	{ key = "6", mods = "CTRL", action = wezterm.action({ ActivateTab = 5 }) },
	{ key = "7", mods = "CTRL", action = wezterm.action({ ActivateTab = 6 }) },

	-- close current pane
	{ key = "w", mods = "CTRL", action = act({ CloseCurrentPane = { confirm = true } }) },
}

config.pane_focus_follows_mouse = false
config.quick_select_patterns = {
	"(?<=[$] ).{1,100}",
	'(?<=")[a-z][^"]+',
}

config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }

return config
