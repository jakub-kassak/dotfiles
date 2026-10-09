local M = {}

local context_lines = 3

local function warn(message)
  vim.notify('Difftastic hunks: ' .. message, vim.log.levels.WARN)
end

local function clamp(value, lower, upper)
  return math.max(lower, math.min(value, upper))
end

local function hunk_anchor(hunk, line_count)
  return clamp(hunk.added.start, 1, math.max(line_count, 1))
end

local function hunk_intersects(hunk, first_line, last_line, line_count)
  if hunk.added.count == 0 then
    local anchor = hunk_anchor(hunk, line_count)
    return anchor >= first_line and anchor <= last_line
  end

  local hunk_last = hunk.added.start + hunk.added.count - 1
  return hunk.added.start <= last_line and hunk_last >= first_line
end

local function selected_hunks(hunks, first_line, last_line, line_count)
  local selected, seen = {}, {}

  for _, hunk in ipairs(hunks) do
    if hunk_intersects(hunk, first_line, last_line, line_count) then
      local key = table.concat({
        hunk.added.start,
        hunk.added.count,
        hunk.removed.start,
        hunk.removed.count,
      }, ':')
      if not seen[key] then
        seen[key] = true
        table.insert(selected, hunk)
      end
    end
  end

  table.sort(selected, function(left, right)
    if left.added.start ~= right.added.start then return left.added.start < right.added.start end
    if left.removed.start ~= right.removed.start then return left.removed.start < right.removed.start end
    if left.added.count ~= right.added.count then return left.added.count < right.added.count end
    return left.removed.count < right.removed.count
  end)

  return selected
end

local function visual_line_range()
  local mode = vim.fn.mode()
  if mode:find('[vV\22]') then
    local first_line, last_line = vim.fn.line('v'), vim.fn.line('.')
    return math.min(first_line, last_line), math.max(first_line, last_line)
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  return line, line
end

local function split_lines(text)
  if text == '' then return {} end

  local lines = vim.split(text, '\n', { plain = true })
  if text:sub(-1) == '\n' then table.remove(lines) end
  return lines
end

local function hunk_lines(lines, range)
  local line_count = #lines
  if line_count == 0 then return {} end

  local first_line, last_line
  if range.count > 0 then
    first_line = math.max(1, range.start - context_lines)
    last_line = math.min(line_count, range.start + range.count - 1 + context_lines)
  else
    local anchor = clamp(range.start, 1, line_count + 1)
    first_line = math.max(1, anchor - context_lines)
    last_line = math.min(line_count, anchor + context_lines - 1)
  end

  local result = {}
  for line = first_line, last_line do
    table.insert(result, lines[line])
  end
  return result
end

local function write_file(path, lines)
  local file, err = io.open(path, 'wb')
  if not file then return nil, err end

  if #lines > 0 then file:write(table.concat(lines, '\n'), '\n') end
  file:close()
  return true
end

local function write_text(path, text)
  local file, err = io.open(path, 'wb')
  if not file then return nil, err end

  file:write(text)
  file:close()
  return true
end

local function cleanup(paths)
  for _, path in ipairs(paths) do
    pcall(os.remove, path)
  end
end

local function buffer_text(buffer, lines)
  local line_ending = vim.bo[buffer].fileformat == 'dos' and '\r\n'
    or vim.bo[buffer].fileformat == 'mac' and '\r'
    or '\n'
  local text = table.concat(lines, line_ending)
  if vim.bo[buffer].endofline then text = text .. line_ending end
  return text
end

local function parse_hunks(diff)
  local hunks = {}

  for line in diff:gmatch('[^\n]+') do
    local removed_start, removed_count, added_start, added_count = line:match(
      '^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@'
    )
    if removed_start then
      table.insert(hunks, {
        removed = {
          start = tonumber(removed_start),
          count = removed_count == '' and 1 or tonumber(removed_count),
        },
        added = {
          start = tonumber(added_start),
          count = added_count == '' and 1 or tonumber(added_count),
        },
      })
    end
  end

  return hunks
end

local function discover_hunks(root, head_text, current_text, extension, callback)
  local head_path = vim.fn.tempname() .. extension
  local buffer_path = vim.fn.tempname() .. extension
  local paths = { head_path, buffer_path }
  local head_ok, head_err = write_text(head_path, head_text)
  local buffer_ok, buffer_err = write_text(buffer_path, current_text)
  if not head_ok or not buffer_ok then
    cleanup(paths)
    callback(nil, head_err or buffer_err)
    return
  end

  vim.system({
    'git', '-C', root, 'diff', '--no-index', '--no-color', '--no-ext-diff', '--unified=0', '--', head_path, buffer_path,
  }, { text = true }, function(result)
    cleanup(paths)
    vim.schedule(function()
      if result.code == 0 then
        callback({})
      elseif result.code == 1 then
        callback(parse_hunks(result.stdout))
      else
        callback(nil, result.stderr)
      end
    end)
  end)
end

local function difft_command(old_path, new_path)
  return table.concat({
    'difft',
    '--color=always',
    '--display=side-by-side',
    '--',
    vim.fn.shellescape(old_path),
    vim.fn.shellescape(new_path),
  }, ' ')
end

local function build_script(hunks, head_lines, buffer_lines, extension)
  local paths, commands = {}, {}

  for index, hunk in ipairs(hunks) do
    local old_path = vim.fn.tempname() .. extension
    local new_path = vim.fn.tempname() .. extension
    paths[#paths + 1] = old_path
    paths[#paths + 1] = new_path

    local old_ok, old_err = write_file(old_path, hunk_lines(head_lines, hunk.removed))
    local new_ok, new_err = write_file(new_path, hunk_lines(buffer_lines, hunk.added))
    if not old_ok or not new_ok then
      cleanup(paths)
      return nil, old_err or new_err
    end

    local heading = ('Hunk %d/%d  HEAD -%d,%d  Buffer +%d,%d'):format(
      index,
      #hunks,
      hunk.removed.start,
      hunk.removed.count,
      hunk.added.start,
      hunk.added.count
    )
    commands[#commands + 1] = "printf '\\n\\033[1m%s\\033[0m\\n\\n' " .. vim.fn.shellescape(heading)
    commands[#commands + 1] = difft_command(old_path, new_path)
  end

  local script_path = vim.fn.tempname()
  paths[#paths + 1] = script_path
  local script, err = io.open(script_path, 'wb')
  if not script then
    cleanup(paths)
    return nil, err
  end

  local quoted_paths = {}
  for _, path in ipairs(paths) do
    quoted_paths[#quoted_paths + 1] = vim.fn.shellescape(path)
  end
  script:write('#!/bin/sh\n')
  script:write('cleanup() { rm -f -- ' .. table.concat(quoted_paths, ' ') .. '; }\n')
  script:write('trap cleanup EXIT HUP INT TERM\n')
  script:write(table.concat(commands, '\n'))
  script:write("\nprintf '\\nPress q to close.\\n'\nsh -i\n")
  script:close()

  return script_path, paths
end

local function build_file_script(head_text, current_text, extension)
  local head_path = vim.fn.tempname() .. extension
  local buffer_path = vim.fn.tempname() .. extension
  local paths = { head_path, buffer_path }
  local head_ok, head_err = write_text(head_path, head_text)
  local buffer_ok, buffer_err = write_text(buffer_path, current_text)
  if not head_ok or not buffer_ok then
    cleanup(paths)
    return nil, head_err or buffer_err
  end

  local script_path = vim.fn.tempname()
  paths[#paths + 1] = script_path
  local script, err = io.open(script_path, 'wb')
  if not script then
    cleanup(paths)
    return nil, err
  end

  local quoted_paths = {}
  for _, temp_path in ipairs(paths) do
    quoted_paths[#quoted_paths + 1] = vim.fn.shellescape(temp_path)
  end
  script:write('#!/bin/sh\n')
  script:write('cleanup() { rm -f -- ' .. table.concat(quoted_paths, ' ') .. '; }\n')
  script:write('trap cleanup EXIT HUP INT TERM\n')
  script:write(difft_command(head_path, buffer_path))
  script:write("\nprintf '\\nPress q to close.\\n'\nsh -i\n")
  script:close()

  return script_path, paths
end

local function float_size()
  local columns, lines = vim.o.columns, vim.o.lines
  local width = math.min(math.floor(columns * 0.92), 160)
  local height = math.min(math.floor(lines * 0.78), 46)

  if columns >= 90 then width = math.max(width, 88) end
  if lines >= 20 then height = math.max(height, 18) end

  return math.max(1, math.min(width, columns - 2)), math.max(1, math.min(height, lines - 2))
end

local function restore_source(source_win, source_buf, source_cursor)
  if not vim.api.nvim_win_is_valid(source_win) then return end
  vim.api.nvim_set_current_win(source_win)
  if vim.api.nvim_win_get_buf(source_win) ~= source_buf then return end

  local line_count = vim.api.nvim_buf_line_count(source_buf)
  local line = clamp(source_cursor[1], 1, math.max(line_count, 1))
  local line_text = vim.api.nvim_buf_get_lines(source_buf, line - 1, line, false)[1] or ''
  vim.api.nvim_win_set_cursor(source_win, { line, math.min(source_cursor[2], #line_text) })
end

local function open_terminal(script_path, cleanup_paths, source_win, source_buf, source_cursor, title)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].bufhidden = 'wipe'
  local width, height = float_size()
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' ' .. title .. ' ',
    title_pos = 'center',
  })
  vim.wo[window].winblend = 0

  local closed, job_id = false, nil
  local function close()
    if closed then return end
    closed = true
    if job_id and job_id > 0 then pcall(vim.fn.jobstop, job_id) end
    if vim.api.nvim_win_is_valid(window) then pcall(vim.api.nvim_win_close, window, true) end
    cleanup(cleanup_paths)
    restore_source(source_win, source_buf, source_cursor)
  end

  vim.keymap.set({ 't', 'n' }, 'q', close, { buffer = buffer, nowait = true, silent = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(window),
    once = true,
    callback = close,
  })

  job_id = vim.fn.termopen({ 'sh', script_path }, {
    on_exit = function()
      vim.schedule(close)
    end,
  })
  if job_id <= 0 then
    close()
    warn('could not start difftastic terminal')
  end
end

local function with_head_comparison(on_ready)
  if vim.fn.executable('difft') == 0 then
    warn('difft executable not found')
    return
  end
  if vim.fn.executable('git') == 0 then
    warn('git executable not found')
    return
  end

  local source_win = vim.api.nvim_get_current_win()
  local source_buf = vim.api.nvim_get_current_buf()
  local source_cursor = vim.api.nvim_win_get_cursor(source_win)
  local path = vim.api.nvim_buf_get_name(source_buf)
  if path == '' or vim.bo[source_buf].buftype ~= '' then
    warn('current buffer is not a tracked file')
    return
  end

  local buffer_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
  local current_text = buffer_text(source_buf, buffer_lines)

  local directory = vim.fs.dirname(path)
  vim.system({ 'git', '-C', directory, 'rev-parse', '--show-toplevel' }, { text = true }, function(root_result)
    vim.schedule(function()
      if root_result.code ~= 0 then
        warn('could not find the file\'s git repository')
        return
      end

      local root = vim.trim(root_result.stdout)
      vim.system({ 'git', '-C', root, 'ls-files', '-z', '--error-unmatch', '--full-name', '--', path }, {}, function(file_result)
        vim.schedule(function()
          if file_result.code ~= 0 or file_result.stdout == '' then
            warn('current file is not tracked by git')
            return
          end

          local relative_path = file_result.stdout:gsub('\0$', '')
          vim.system({ 'git', '-C', root, 'show', 'HEAD:' .. relative_path }, {}, function(head_result)
            vim.schedule(function()
              if head_result.code ~= 0 then
                warn('could not read the file from HEAD')
                return
              end

              local extension = vim.fn.fnamemodify(path, ':e')
              local suffix = extension == '' and '' or '.' .. extension
              on_ready({
                root = root,
                relative_path = relative_path,
                head_text = head_result.stdout,
                buffer_lines = buffer_lines,
                current_text = current_text,
                suffix = suffix,
                source_win = source_win,
                source_buf = source_buf,
                source_cursor = source_cursor,
              })
            end)
          end)
        end)
      end)
    end)
  end)
end

function M.open()
  local first_line, last_line = visual_line_range()
  with_head_comparison(function(comparison)
    discover_hunks(
      comparison.root,
      comparison.head_text,
      comparison.current_text,
      comparison.suffix,
      function(hunks, err)
        if not hunks then
          warn('could not compare the file with HEAD: ' .. (err or 'unknown error'))
          return
        end
        if #hunks == 0 then
          warn('no differences from HEAD')
          return
        end

        hunks = selected_hunks(hunks, first_line, last_line, #comparison.buffer_lines)
        if #hunks == 0 then
          warn('no git hunk intersects the selection')
          return
        end

        local script_path, cleanup_paths = build_script(
          hunks,
          split_lines(comparison.head_text),
          comparison.buffer_lines,
          comparison.suffix
        )
        if not script_path then
          warn('could not create temporary difftastic files: ' .. (cleanup_paths or 'unknown error'))
          return
        end

        local title = ('Difftastic: %s (%d hunk%s)'):format(
          comparison.relative_path,
          #hunks,
          #hunks == 1 and '' or 's'
        )
        open_terminal(
          script_path,
          cleanup_paths,
          comparison.source_win,
          comparison.source_buf,
          comparison.source_cursor,
          title
        )
      end
    )
  end)
end

function M.open_file()
  with_head_comparison(function(comparison)
    discover_hunks(
      comparison.root,
      comparison.head_text,
      comparison.current_text,
      comparison.suffix,
      function(hunks, err)
        if not hunks then
          warn('could not compare the file with HEAD: ' .. (err or 'unknown error'))
          return
        end
        if #hunks == 0 then
          warn('no differences from HEAD')
          return
        end

        local script_path, cleanup_paths = build_file_script(
          comparison.head_text,
          comparison.current_text,
          comparison.suffix
        )
        if not script_path then
          warn('could not create temporary difftastic files: ' .. (cleanup_paths or 'unknown error'))
          return
        end

        local title = ('Difftastic: %s (whole file)'):format(comparison.relative_path)
        open_terminal(
          script_path,
          cleanup_paths,
          comparison.source_win,
          comparison.source_buf,
          comparison.source_cursor,
          title
        )
      end
    )
  end)
end

vim.keymap.set({ 'n', 'v' }, '<leader>hd', M.open, { desc = 'Difftastic [d]iff hunk' })
vim.keymap.set('n', '<leader>hD', M.open_file, { desc = 'Difftastic [D]iff file' })

return M
