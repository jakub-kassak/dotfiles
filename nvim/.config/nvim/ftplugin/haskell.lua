local ht = require('haskell-tools')
local bufnr = vim.api.nvim_get_current_buf()

local function set_keymap(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, buffer = bufnr, desc = desc })
end

-- haskell-language-server relies heavily on codeLenses,
-- so auto-refresh (see advanced configuration) is enabled by default
set_keymap('n', '<leader>ca', vim.lsp.codelens.run, '[C]ode Lens [A]ction')

-- Hoogle search for the type signature of the snippet under the cursor
set_keymap('n', '<leader>hs', ht.hoogle.hoogle_signature, '[H]oogle [S]ignature')

-- Evaluate all code snippets
set_keymap('n', '<leader>ea', ht.lsp.buf_eval_all, '[E]valuate [A]ll snippets')

-- Toggle a GHCi repl for the current package
set_keymap('n', '<leader>rr', ht.repl.toggle, '[R]EPL toggle for package')

-- Toggle a GHCi repl for the current buffer
set_keymap('n', '<leader>rf', function()
  ht.repl.toggle(vim.api.nvim_buf_get_name(0))
end, '[R]EPL toggle for [F]ile (buffer)')

set_keymap('n', '<leader>rq', ht.repl.quit, '[R]EPL [Q]uit')

-- Register groups in which-key if it is available
local wk_ok, wk = pcall(require, "which-key")
if wk_ok then
  wk.add({
    { "<leader>r", group = "[R]EPL (GHCi)", buffer = bufnr },
    { "<leader>e", group = "[E]valuate", buffer = bufnr },
  })
end
