-- haskell-dap.lua
--
-- Haskell debugging via hdb (haskell-debugger) — the GHC 9.14 native debugger.
-- https://well-typed.github.io/haskell-debugger/
--
-- Requires: hdb installed via `cabal install haskell-debugger`
--           (see https://discourse.haskell.org/t/the-haskell-debugger-for-ghc-9-14/13499)

local dap = require 'dap'

-- Enable verbose DAP logging (append to ~/.local/state/nvim/dap.log)
vim.fn.setenv('DAP_LOG_FILE', vim.fn.stdpath 'state' .. '/dap.log')

-- Adapter: hdb runs as a TCP DAP server, nvim-dap launches it and connects.
-- --internal-interpreter avoids the runInTerminal request that nvim-dap can't handle.
dap.adapters['haskell-debugger'] = {
  type = 'server',
  port = '${port}',
  executable = {
    command = vim.fn.expand '~/.local/bin/hdb',
    args = { 'server', '--port', '${port}', '--internal-interpreter' },
  },
}

-- Persist breakpoints per project: save on VimLeave, restore on BufRead.
-- Stored in <project_root>/.nvim/dap-breakpoints.json

local dap_breakpoints = require 'dap.breakpoints'

local function get_bp_file()
  local root = vim.fn.getcwd()
  local dir = root .. '/.nvim'
  return dir .. '/dap-breakpoints.json'
end

local function save_breakpoints()
  local bps = dap_breakpoints.get()
  if vim.tbl_isempty(bps) then return end

  local entries = {}
  for bufnr, buf_bps in pairs(bps) do
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path and path ~= '' then
      for _, bp in ipairs(buf_bps) do
        table.insert(entries, {
          file = path,
          line = bp.line,
          condition = bp.condition,
          hitCondition = bp.hitCondition,
          logMessage = bp.logMessage,
        })
      end
    end
  end

  if #entries == 0 then return end

  local bp_file = get_bp_file()
  vim.fn.mkdir(vim.fn.fnamemodify(bp_file, ':h'), 'p')
  local f = io.open(bp_file, 'w')
  if f then
    f:write(vim.json.encode(entries))
    f:close()
  end
end

local function load_breakpoints()
  local bp_file = get_bp_file()
  local f = io.open(bp_file, 'r')
  if not f then return end

  local content = f:read '*a'
  f:close()
  if not content or content == '' then return end

  local ok, entries = pcall(vim.json.decode, content)
  if not ok or not entries then return end

  for _, entry in ipairs(entries) do
    local bufnr = vim.fn.bufadd(entry.file)
    if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
      dap_breakpoints.set({
        condition = entry.condition,
        hitCondition = entry.hitCondition,
        logMessage = entry.logMessage,
      }, bufnr, entry.line)
    end
  end
end

vim.api.nvim_create_autocmd('VimLeavePre', { callback = save_breakpoints, desc = 'DAP: Save breakpoints' })
vim.api.nvim_create_autocmd('BufReadPost', { callback = load_breakpoints, desc = 'DAP: Load breakpoints' })

local attribution_api = '/workspaces/AgentDojo/attribution-api'

dap.configurations.haskell = {
  {
    type = 'haskell-debugger',
    request = 'launch',
    name = 'hdb: benchmark-runner (post_hoc_qwen_mini)',
    projectRoot = attribution_api,
    entryFile = 'benchmark/Main.hs',
    entryPoint = 'main',
    entryArgs = {
      'run',
      '-j',
      '16',
      '--reset',
      '-v',
      '/workspaces/AgentDojo/config_gandalf/post_hoc_qwen_mini.yaml',
    },
    extraGhcArgs = {},
  },
  {
    type = 'haskell-debugger',
    request = 'launch',
    name = 'hdb: current file (main)',
    projectRoot = '${workspaceFolder}',
    entryFile = '${file}',
    entryPoint = 'main',
    entryArgs = {},
    extraGhcArgs = {},
  },
}
