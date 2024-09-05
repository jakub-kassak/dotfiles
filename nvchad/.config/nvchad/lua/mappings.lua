require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

map({ "n", "t" }, "<A-l>", function()
  require("nvchad.term").toggle {
    pos = "float",
    id = "floatTerm",
    float_opts = {
      width = 0.99,
      height = 0.95,
      row = 0,
      col = 0,
    },
    cmd = "lazygit; exit",
  }
end, { desc = "Lazygit", noremap = true, silent = true })
