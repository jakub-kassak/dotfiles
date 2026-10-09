vim.g.haskell_tools = {
  hls = {
    default_settings = {
      haskell = {
        plugin = {
          inlayHints = {
            globalOn = true,
            config = {
              typeHints = true,
              parameterNames = true,
            }
          }
        }
      }
    }
  }
}

-- Keymap: <leader>hr → :Hls restart
vim.keymap.set('n', '<leader>hr', function()
  vim.cmd.e()
  vim.cmd.Hls('restart')
end, { desc = 'Hls [r]estart (reload + restart)' })

-- Which-key registration
require('which-key').add {
  { '<leader>hr', desc = 'Hls [r]estart (reload + restart)', mode = 'n' },
}
