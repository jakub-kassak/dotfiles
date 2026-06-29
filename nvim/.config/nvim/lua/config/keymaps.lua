-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
-- use `vim.keymap.set` instead
local map = vim.keymap.set
map("n", "<leader>k", "<cmd>WeztermSpawn lazydocker<CR>", { desc = "Toggle LazyDocker", noremap = true, silent = true })

vim.keymap.set("n", ";", ":", {
  noremap = true,
}) -- Press ; to enter command mode
vim.keymap.set("n", ":", ";", {
  noremap = true,
}) -- Press : to repeat f/t/F/T

local function create_term_buf(_type, size)
  vim.o.splitbelow = true
  vim.o.splitright = true

  if _type == "v" then
    vim.cmd("vnew")
  else
    vim.cmd("new")
  end

  vim.cmd("resize " .. size)
end

-- Define a build and run function
local function find_git_root()
  local cwd = vim.fn.getcwd()
  local root_dir = cwd
  while root_dir ~= "/" do
    if vim.fn.isdirectory(root_dir .. "/.git") == 1 then
      vim.notify("Root directory found: " .. root_dir, vim.log.levels.INFO)
      return root_dir
    end
    root_dir = vim.fn.fnamemodify(root_dir, ":h")
  end
  vim.notify("Root directory found: " .. root_dir, vim.log.levels.INFO)
  return cwd -- Fallback to current working directory
end

function BuildAndRun()
  local file = vim.fn.expand("%")
  local project_root = find_git_root()
  local build_dir = project_root .. "/.build"
  local output_file = build_dir .. "/" .. vim.fn.expand("%:t:r")
  local _flag = "-Wall -Wextra -std=c++11 -O2"

  local prog = nil
  if vim.fn.executable("clang++") == 1 then
    prog = "clang++"
  elseif vim.fn.executable("g++") == 1 then
    prog = "g++"
  else
    vim.api.nvim_err_writeln("No compiler found!")
    return
  end

  create_term_buf("v", 100)
  vim.cmd(string.format("term %s %s %s -o %s && %s", prog, _flag, file, output_file, output_file))
  vim.cmd("startinsert")
end

-- Neovim Lua configuration
local dap = require("dap")

function BuildAndDebug()
  local file = vim.fn.expand("%")
  local project_root = find_git_root()
  local build_dir = project_root .. "/.build"
  local output_file = build_dir .. "/" .. vim.fn.expand("%:t:r")

  -- Build the file using clang++
  vim.cmd("!clang++ -Wall -Wextra -std=c++11 -O2 " .. file .. " -o " .. output_file)

  -- Configure and start the debugger
  dap.configurations.cpp = {
    {
      name = "Launch",
      type = "codelldb",
      request = "launch",
      program = output_file,
      cwd = vim.fn.getcwd(),
      stopAtEntry = false,
    },
  }
  dap.run(vim.deepcopy(dap.configurations.cpp[1]))
end

vim.api.nvim_set_keymap("n", "<silent><F9>", ":lua BuildAndDebug()<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<silent><F10>", ":lua BuildAndRun()<CR>", { noremap = true, silent = true })

-- Direct Surround keymaps in visual mode (using mini.surround)
local map = vim.keymap.set
map("x", "(", "gsa)", { remap = true, desc = "Surround with ()" })
map("x", ")", "gsa(", { remap = true, desc = "Surround with ( )" })
map("x", "[", "gsa]", { remap = true, desc = "Surround with []" })
map("x", "]", "gsa[", { remap = true, desc = "Surround with [ ]" })
map("x", "{", "gsa}", { remap = true, desc = "Surround with {}" })
map("x", "}", "gsa{", { remap = true, desc = "Surround with { }" })
map("x", '"', 'gsa"', { remap = true, desc = "Surround with double quotes" })
map("x", "'", "gsa'", { remap = true, desc = "Surround with single quotes" })
