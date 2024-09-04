-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
-- In case you don't want to use `:LazyExtras`,
-- then you need to set the option below.
vim.opt.background = "dark" -- set this to dark or light
-- vim.g.python3_host_prog = "/opt/homebrew/anaconda3/envs/nvim/bin/python"
-- Disable highlighting of the current line
-- vim.o.cursorline = false

vim.g.lazygit_floating_window_scaling_factor = 0.999
vim.g.lazygit_config = false

vim.cmd("highlight MyCursor guifg=#ffffff guibg=#ff0000")
vim.o.guicursor = "n-v:block-MyCursor,i:ver25,c:block,ci:ver25"

vim.g.root_spec = { { ".git", "lua" }, "cwd" }
