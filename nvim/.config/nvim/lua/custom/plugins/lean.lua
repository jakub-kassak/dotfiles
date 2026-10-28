-- Lean owns its language server: elan selects the project's pinned toolchain.
-- Include elan even when Neovim was launched outside a fresh terminal.
local elan_bin = vim.fn.expand '~/.elan/bin'
if vim.fn.isdirectory(elan_bin) == 1 and not vim.tbl_contains(vim.split(vim.env.PATH or '', ':', { plain = true }), elan_bin) then
  vim.env.PATH = elan_bin .. ':' .. (vim.env.PATH or '')
end

vim.g.lean_config = {
  mappings = true,
  infoview = { autoopen = true, orientation = 'auto' },
}

vim.pack.add { 'https://github.com/Julian/lean.nvim' }
