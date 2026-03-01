-- bootstrap lazy.nvim, LazyVim and your plugins
-- require("user.vscode_keymaps")
if vim.g.vscode then
  -- VSCode Neovim
  require("user.vscode_keymaps")
else
  -- Ordinary Neovim
  require("config.lazy")
end
