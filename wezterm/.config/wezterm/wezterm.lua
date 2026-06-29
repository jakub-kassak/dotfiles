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
config.font = wezterm.font("JetBrainsMono Nerd Font")

local act = wezterm.action
config.keys = {
        -- Toggle dark/light mode
        {
                key = "d",
                mods = "CMD",
                action = wezterm.action_callback(function(window, pane)
                        local overrides = window:get_config_overrides() or {}
                        local current_scheme = overrides.color_scheme or window:effective_config().color_scheme
                        local home = os.getenv("HOME")
                        if current_scheme == "Builtin Solarized Light" then
                                overrides.color_scheme = "Builtin Solarized Dark"
                                os.execute("touch " .. home .. "/.kvim_dark")
                        else
                                overrides.color_scheme = "Builtin Solarized Light"
                                os.execute("rm -f " .. home .. "/.kvim_dark")
                        end
                        window:set_config_overrides(overrides)
                end),
        },
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
                action = wezterm.action_callback(function(win, pane)
                        pane:move_to_new_window()
                end),
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


        -- close current pane
        { key = "w", mods = "CTRL", action = act({ CloseCurrentPane = { confirm = true } }) },
}

-- Allow using CTRL + OPT to trigger standard ALT (Meta) bindings, 
-- since pure OPT is reserved for special characters like 'ä'.
local keys = "abcdefghijklmnopqrstuvwxyz0123456789"
for i = 1, #keys do
        local char = keys:sub(i, i)
        table.insert(config.keys, {
                key = char,
                mods = 'CTRL|ALT',
                action = wezterm.action.SendKey({ key = char, mods = 'ALT' }),
        })
end

-- Also map arrows
-- Map CTRL + Arrows directly to ALT + Arrows for Zellij
table.insert(config.keys, { key = 'LeftArrow', mods = 'CTRL', action = wezterm.action.SendKey({ key = 'LeftArrow', mods = 'ALT' }) })
table.insert(config.keys, { key = 'RightArrow', mods = 'CTRL', action = wezterm.action.SendKey({ key = 'RightArrow', mods = 'ALT' }) })
table.insert(config.keys, { key = 'UpArrow', mods = 'CTRL', action = wezterm.action.SendKey({ key = 'UpArrow', mods = 'ALT' }) })
table.insert(config.keys, { key = 'DownArrow', mods = 'CTRL', action = wezterm.action.SendKey({ key = 'DownArrow', mods = 'ALT' }) })


-- Map CTRL+1..9 to send ALT+1..9 so Zellij can actually detect them
for i = 1, 9 do
        table.insert(config.keys, {
                key = tostring(i),
                mods = 'CTRL',
                action = wezterm.action.SendKey({ key = tostring(i), mods = 'ALT' }),
        })
end

config.pane_focus_follows_mouse = false
config.pane_focus_follows_mouse = false
config.quick_select_patterns = {
        "(?<=[$] ).{1,100}",
        '(?<=")[a-z][^"]+',
}

config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }

config.send_composed_key_when_left_alt_is_pressed = true
config.send_composed_key_when_right_alt_is_pressed = true

-- Selection is automatically copied to the clipboard by WezTerm on macOS.

return config
