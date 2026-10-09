-- Open `file://` URIs (incl. `#L<line>` / `#L<start>-L<end>`) inside Neovim,
-- and delegate every other scheme to the default vim.ui.open handler.

do
  local default_open = vim.ui.open
  local decode = (vim.uri and vim.uri.decode) or function(s) return s end

  vim.ui.open = function(uri)
    if type(uri) ~= 'string' or uri:sub(1, 7) ~= 'file://' then
      return default_open(uri)
    end

    local rest = uri:sub(8) -- "/path[#frag]"
    local path, line1, line2 = rest, nil, nil

    local hash_pos = rest:find '#L', 1, true
    if hash_pos then
      path = rest:sub(1, hash_pos - 1)
      local frag = rest:sub(hash_pos + 2) -- after "#L"
      line1, line2 = frag:match '^(%d+)%-L?(%d+)$'
      if not line1 then
        line1 = frag:match '^(%d+)$'
      end
    end

    local esc = vim.fn.fnameescape(decode(path))

    -- If we are inside a floating window, jump to the main window first
    -- and close the float so the file opens in the regular buffer.
    local cur_win = vim.api.nvim_get_current_win()
    local main_win = cur_win
    if vim.api.nvim_win_get_config(cur_win).relative ~= '' then
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(w).relative == '' then
          main_win = w
          break
        end
      end
      vim.api.nvim_win_close(cur_win, false)
      vim.api.nvim_set_current_win(main_win)
    end

    vim.cmd.edit(esc)

    if line1 then
      vim.api.nvim_win_set_cursor(main_win, { tonumber(line1), 0 })
      if line2 then
        vim.cmd('normal! ' .. tonumber(line2) .. 'Gv' .. tonumber(line1) .. 'G')
      end
    end
  end
end
