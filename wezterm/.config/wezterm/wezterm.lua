-- https://diego.codes/post/honing-the-tools/02-wezterm/
local wezterm = require("wezterm")

local config = wezterm.config_builder()

-- For example, changing the color scheme:

local function depending_on_appearance(arg)
	-- local appearance = wezterm.gui.get_appearance()
	-- if appearance:find("Dark") then
	-- 	return arg.dark
	-- else
	-- 	return arg.light
	-- end
	local hour = tonumber(os.date("%H"))

	if hour >= 5 and hour < 20 then
		return arg.light
	else
		return arg.dark
	end
end

config.color_schemes = {
	["AMOLED Dark"] = {
		foreground = "#D0D0D0", -- Light gray text
		background = "#000000", -- True black background
		cursor_bg = "#D0D0D0",
		cursor_border = "#D0D0D0",
		cursor_fg = "#000000",
		selection_bg = "#44475a",
		selection_fg = "#FFFFFF",

		ansi = { "#000000", "#FF5555", "#50FA7B", "#F1FA8C", "#BD93F9", "#FF79C6", "#8BE9FD", "#BFBFBF" },
		brights = { "#4D4D4D", "#FF6E67", "#5AF78E", "#F4F99D", "#CAA9FA", "#FF92D0", "#9AEDFE", "#E6E6E6" },
	},
}

config.initial_rows = 35
config.initial_cols = 110
config.color_scheme = depending_on_appearance({
	light = "PaperColor Light (base16)", --"Gruvbox light, hard (base16)", -- "Tokyo Night Moon", -- "Vs Code Light+ (Gogh)", -- 3024 (light) (terminal.sexy)", --One Light (Gogh)", --Vs Code Light+ (Gogh)", -- Catppuccin Latte',
	dark = "Gruvbox dark, hard (base16)", -- "Papercolor Dark (Gogh)", --"Tokyo Night", -- "Vs Code Dark+ (Gogh)", --3024 (dark) (terminal.sexy)", -- Catppuccin Mocha",
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
	{
		key = "Enter",
		mods = "CMD|SHIFT",
		action = wezterm.action.SpawnCommandInNewWindow({
			args = { "bash" },
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
	{ key = "V", mods = "CTRL|SHIFT", action = act.SendKey({ key = "v", mods = "CTRL" }) },
	{ key = "v", mods = "CTRL", action = act({ PasteFrom = "Clipboard" }) },

	-- { key = "c", mods = "CTRL", action = act.CopyTo("Clipboard") },
	-- { key = "c", mods = "SUPER", action = act.SendKey({ key = "c", mods = "CTRL" }) },
	-- -- Close the current tab
	{ key = "w", mods = "CTRL", action = act({ CloseCurrentTab = { confirm = true } }) },

	-- Search with Crtl+F
	-- { key = "f", mods = "CTRL", action = act.Search("CurrentSelectionOrEmptyString") },

	-- Show tab navigator
	{ key = "p", mods = "SUPER", action = act.ShowTabNavigator },
	-- Show launcher menu
	{ key = "P", mods = "SUPER|SHIFT", action = act.ShowLauncher },
	-- Spawn a new tab
	{ key = "t", mods = "CTRL", action = act({ SpawnTab = "CurrentPaneDomain" }) },

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
	{ key = "Tab", mods = "CTRL", action = act.ActivateLastTab },
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
}

config.pane_focus_follows_mouse = false
config.quick_select_patterns = {
	"(?<=[$] ).{1,100}",
	'(?<=")[a-z][^"]+',
}

config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
return config
