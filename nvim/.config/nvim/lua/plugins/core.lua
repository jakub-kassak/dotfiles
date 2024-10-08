local function find_command()
  if 1 == vim.fn.executable("rg") then
    -- return { "rg", "--files", "--color", "never", "-g", "!.ruff_cache", "-g", "!__pycache__", "-g", "!.git", "-.", "--no-ignore" }
    return { "rg", "--files", "-.", "-g", "!.git" }
  elseif 1 == vim.fn.executable("fd") then
    return { "fd", "--type", "f", "--color", "never", "-E", ".git" }
  elseif 1 == vim.fn.executable("fdfind") then
    return { "fdfind", "-I", "--type", "f", "--color", "never", "-E", ".git", "-H" }
  elseif 1 == vim.fn.executable("find") and vim.fn.has("win32") == 0 then
    return { "find", ".", "-type", "f" }
  elseif 1 == vim.fn.executable("where") then
    return { "where", "/r", ".", "*" }
  end
end

return {
  {
    "nvim-telescope/telescope.nvim",
    opts = {
      pickers = {
        find_files = {
          find_command = find_command,
          hidden = true,
        },
      },
    },
  },
  {
    "https://git.sr.ht/~nedia/auto-save.nvim",
    event = { "BufReadPre" },
    opts = {
      events = { "InsertLeave", "BufLeave" },
      silent = false,
      exclude_ft = { "neo-tree" },
    },
  },
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    build = ":Copilot auth",
    opts = {
      suggestion = { enabled = true },
      panel = { enabled = false },
      filetypes = {
        markdown = true,
        help = true,
        yaml = true,
      },
    },
  },
  {
    "willothy/wezterm.nvim",
    config = true,
  },
}
