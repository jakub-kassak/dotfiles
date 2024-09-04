-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
-- use `vim.keymap.set` instead
local map = vim.keymap.set
map("n", "<leader>k", "<cmd>WeztermSpawn lazydocker<CR>", { desc = "Toggle LazyDocker", noremap = true, silent = true })
