-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

vim.pack.add {
  { src = 'https://github.com/nvim-neo-tree/neo-tree.nvim', version = vim.version.range '*' },
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/MunifTanjim/nui.nvim',
}

vim.keymap.set('n', '\\', '<Cmd>Neotree toggle<CR>', { desc = 'NeoTree toggle', silent = true })
vim.keymap.set('n', '<D-E>', '<Cmd>Neotree toggle<CR>', { desc = 'NeoTree toggle', silent = true })

require('neo-tree').setup {
  -- Clean up stale neo-tree buffers left in a restored session file
  auto_clean_after_session_restore = true,
  filesystem = {
    window = {
      mappings = {
        ['\\'] = 'close_window',
      },
    },
  },
}

-- Close all neo-tree windows before the session is saved so persistence.nvim
-- never records a neo-tree buffer (which causes E95 on restore).
vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    pcall(function() require('neo-tree.sources.manager').close_all() end)
  end,
})
