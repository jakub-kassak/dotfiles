local wezterm = require('wezterm')
local act = wezterm.action
local M = {}

-- Match paths with extensions, absolute paths and path:line:column references.
local path_pattern = [=[(?<![\w:/.@+~-])(?:(?:~?/|\.{1,2}/)?(?:[\w.@+~-]+/)+[\w.@+~-]+|(?:~?/|\.{1,2}/)[\w.@+~-]+|[\w@+~-][\w.@+~-]*\.[A-Za-z0-9_-]+)(?::\d+(?::\d+)?|#L\d+(?:-L?\d+)?|\|\d+(?:\s+col\s+\d+(?:-\d+)?)?\|?)?]=]

local function run(...)
  return wezterm.run_child_process({
    '/opt/homebrew/bin/python3', wezterm.config_dir .. '/nvim_open.py', ...,
  })
end

local function notify(window, message)
  window:toast_notification('Open in Neovim', message, nil, 5000)
end

function M.open(window, pane, path)
  local ok, output, err = run('list')
  if not ok then
    notify(window, err)
    return
  end
  local choices, servers = {}, {}
  for _, instance in ipairs(wezterm.json_parse(output)) do
    -- Ignore servers belonging to another WezTerm GUI or a closed pane.
    local target = wezterm.mux.get_pane(tonumber(instance.pane))
    if target then
      servers[instance.server] = target
      table.insert(choices, {
        id = instance.server,
        label = string.format('%s — %s (PID %d)', instance.cwd, target:get_title(), instance.pid),
      })
    end
  end
  if #choices == 0 then
    notify(window, 'No running Neovim instance found in this WezTerm session')
    return
  end
  local cwd = pane:get_current_working_dir()
  local source_cwd = cwd and cwd.file_path or wezterm.home_dir
  local function open_in(win, server)
    if not server then return end
    local opened, _, error_text = run('open', server, path, source_cwd)
    if not opened then
      notify(win, error_text)
      return
    end
    local target = servers[server]
    target:tab():activate()
    target:activate()
    target:window():gui_window():focus()
  end
  if #choices == 1 then
    open_in(window, choices[1].id)
  else
    window:perform_action(act.InputSelector({
      title = 'Open ' .. path .. ' in Neovim',
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(win, _, id) open_in(win, id) end),
    }), pane)
  end
end

function M.apply(config)
  config.hyperlink_rules = wezterm.default_hyperlink_rules()
  table.insert(config.hyperlink_rules, { regex = path_pattern, format = 'nvim-path:$0' })
  wezterm.on('open-uri', function(window, pane, uri)
    if uri:match('^nvim%-path:') or uri:match('^file://') then
      M.open(window, pane, uri)
      return false
    end
  end)

  -- Explicit mouse-reporting variants work inside Neovim and multiplexers too.
  config.mouse_bindings = config.mouse_bindings or {}
  for _, reporting in ipairs({ false, true }) do
    for _, mods in ipairs({ 'CTRL', 'CTRL|SHIFT' }) do
      table.insert(config.mouse_bindings, {
        event = { Down = { streak = 1, button = 'Left' } },
        mods = mods, mouse_reporting = reporting, action = act.Nop,
      })
      table.insert(config.mouse_bindings, {
        event = { Up = { streak = 1, button = 'Left' } },
        mods = mods, mouse_reporting = reporting, action = act.OpenLinkAtMouseCursor,
      })
    end
  end
  table.insert(config.keys, {
    key = 'O', mods = 'CTRL|SHIFT',
    action = act.QuickSelectArgs({
      label = 'open in Neovim',
      patterns = { path_pattern },
      action = wezterm.action_callback(function(window, pane)
        local path = window:get_selection_text_for_pane(pane)
        if path ~= '' then M.open(window, pane, path) end
      end),
    }),
  })
end

return M
