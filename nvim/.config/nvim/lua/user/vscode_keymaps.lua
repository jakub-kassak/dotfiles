local keymap = vim.keymap.set
local opts = {
    noremap = true,
    silent = true
}

-- remap leader key
keymap("n", "<Space>", "", opts)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.keymap.set({"n", "x", "o"}, ";", ":", {
    noremap = true
}) -- Press ; to enter command mode
vim.keymap.set({"n", "x", "o"}, ":", ";", {
    noremap = true
}) -- Press : to repeat f/t/F/T

-- Case-insensitive searching UNLESS \C or one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Decrease update time
vim.opt.updatetime = 250

-- Decrease mapped sequence wait time
vim.opt.timeoutlen = 1000
vim.o.ttimeoutlen = 50 -- Lower value makes Esc more responsive

-- Preview substitutions live, as you type!
vim.opt.inccommand = "split"

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 10

-- yank to system clipboard
keymap({"n", "v"}, "<leader>y", '"+y', opts)

-- paste from system clipboard
keymap({"n", "v"}, "<leader>p", '"+p', opts)

-- better indent handling
keymap("v", "<", "<gv", opts)
keymap("v", ">", ">gv", opts)

-- move text up and down
keymap("v", "J", ":m .+1<CR>==", opts)
keymap("v", "K", ":m .-2<CR>==", opts)
keymap("x", "J", ":move '>+1<CR>gv-gv", opts)
keymap("x", "K", ":move '<-2<CR>gv-gv", opts)

-- paste preserves primal yanked piece
keymap("v", "p", '"_dP', opts)

-- removes highlighting after escaping vim search
keymap("n", "<Esc>", "<Esc>:noh<CR>", opts)

-- call vscode commands from neovim
keymap({"n", "v"}, "<C-/>", "<cmd>lua require('vscode').action('workbench.action.terminal.toggleTerminal')<CR>")
keymap({"n", "v"}, "<leader>bb", "<cmd>lua require('vscode').action('editor.debug.action.toggleBreakpoint')<CR>")
-- keymap({ "n", "v" }, "<leader>d", "<cmd>lua require('vscode').action('editor.action.showHover')<CR>")
keymap({"n", "v"}, "<leader>a", "<cmd>lua require('vscode').action('editor.action.quickFix')<CR>")
keymap({"n", "v"}, "<leader>cd", "<cmd>lua require('vscode').action('workbench.actions.view.problems')<CR>")
keymap({"n", "v"}, "<leader>cn", "<cmd>lua require('vscode').action('notifications.clearAll')<CR>")
keymap({"n", "v"}, "<leader>ff", "<cmd>lua require('vscode').action('workbench.action.quickOpen')<CR>")
keymap({"n", "v"}, "<leader>cp", "<cmd>lua require('vscode').action('workbench.action.showCommands')<CR>")
keymap({"n", "v"}, "<leader>pr", "<cmd>lua require('vscode').action('code-runner.run')<CR>")
keymap({"n", "v"}, "<leader>gg", "<cmd>lua require('vscode').action('lazygit-vscode.toggle')<CR>")
keymap({"n", "v"}, "<leader>/",
    "<cmd>lua require('vscode').action('workbench.action.showAllEditorsByMostRecentlyUsed')<CR>")
keymap({"n", "v"}, "<leader>.", "<cmd>lua require('vscode').action('workbench.action.quickOpen')<CR>")
keymap({"n", "v"}, "<C-h>", "<cmd>lua require('vscode').action('workbench.action.focusLeftGroup')<CR>")
keymap({"n", "v"}, "<C-l>", "<cmd>lua require('vscode').action('workbench.action.focusRightGroup')<CR>")
keymap({"n", "v"}, "<C-k>", "<cmd>lua require('vscode').action('workbench.action.focusAboveGroup')<CR>")
keymap({"n", "v"}, "<C-j>", "<cmd>lua require('vscode').action('workbench.action.focusBelowGroup')<CR>")
keymap({"n", "v"}, "<leader>bo", "<cmd>lua require('vscode').action('workbench.action.closeOtherEditors')<CR>")
keymap({"n", "v"}, "<leader>d", "<cmd>lua require('vscode').action('workbench.debug.action.toggleRepl')<CR>") -- open debug console
keymap({"n", "v"}, "<leader>cr", "<cmd>lua require('vscode').action('editor.action.rename')<CR>") -- open debug console
keymap("n", "[d", "<cmd>lua require('vscode').action('editor.action.marker.next')<CR>", opts) -- next error]")
keymap("n", "]d", "<cmd>lua require('vscode').action('editor.action.marker.prev')<CR>", opts) -- previous error
keymap("n", "<leader>w", "<cmd>lua require('vscode').action('editor.action.formatDocument')<CR>", opts) -- close current editor

--
-- jupyter
keymap("n", "<leader>jc", "<cmd>lua require('vscode').action('notebook.cell.execute')<CR>", {
    desc = "Run Current Cell"
})
keymap("n", "<leader>ja", "<cmd>lua require('vscode').action('jupyter.runcurrentcellandaddbelow')<CR>", {
    desc = "Run Current Cell and Add Below"
})
keymap("n", "<leader>jd", "<cmd>lua require('vscode').action('jupyter.runAndDebugCell')<CR>", {
    desc = "Run and Debug Cell"
})
keymap("n", "<leader>jb", "<cmd>lua require('vscode').action('jupyter.insertCellBelow')<CR>", {
    desc = "Insert Cell Below"
})
keymap("n", "<leader>ju", "<cmd>lua require('vscode').action('jupyter.insertCellAbove')<CR>", {
    desc = "Insert Cell Above"
})
keymap("n", "<leader>jx", "<cmd>lua require('vscode').action('jupyter.deleteCells')<CR>", {
    desc = "Delete Cells"
})
keymap("n", "<leader>jj", "<cmd>lua require('vscode').action('jupyter.changeCellToCode')<CR>", {
    desc = "Change Cell to Code"
})
keymap("n", "<leader>jm", "<cmd>lua require('vscode').action('jupyter.changeCellToMarkdown')<CR>", {
    desc = "Change Cell to Markdown"
})
-- call VSCodeNotify('jupyter.runcurrentcell', 'Run Current Cell')
-- harpoon keymaps
keymap({"n", "v"}, "<leader>ha", "<cmd>lua require('vscode').action('vscode-harpoon.addEditor')<CR>")
keymap({"n", "v"}, "<leader>ho", "<cmd>lua require('vscode').action('vscode-harpoon.editorQuickPick')<CR>")
keymap({"n", "v"}, "<leader>he", "<cmd>lua require('vscode').action('vscode-harpoon.editEditors')<CR>")
keymap({"n", "v"}, "<leader>h1", "<cmd>lua require('vscode').action('vscode-harpoon.gotoEditor1')<CR>")
keymap({"n", "v"}, "<leader>h2", "<cmd>lua require('vscode').action('vscode-harpoon.gotoEditor2')<CR>")
keymap({"n", "v"}, "<leader>h3", "<cmd>lua require('vscode').action('vscode-harpoon.gotoEditor3')<CR>")
keymap({"n", "v"}, "<leader>h4", "<cmd>lua require('vscode').action('vscode-harpoon.gotoEditor4')<CR>")
keymap({"n", "v"}, "<leader>h5", "<cmd>lua require('vscode').action('vscode-harpoon.gotoEditor5')<CR>")
keymap({"n", "v"}, "<leader>h6", "<cmd>lua require('vscode').action('vscode-harpoon.gotoEditor6')<CR>")
keymap({"n", "v"}, "<leader>h7", "<cmd>lua require('vscode').action('vscode-harpoon.gotoEditor7')<CR>")
keymap({"n", "v"}, "<leader>h8", "<cmd>lua require('vscode').action('vscode-harpoon.gotoEditor8')<CR>")
keymap({"n", "v"}, "<leader>h9", "<cmd>lua require('vscode').action('vscode-harpoon.gotoEditor9')<CR>")

-- project manager keymaps
keymap({"n", "v"}, "<leader>pa", "<cmd>lua require('vscode').action('projectManager.saveProject')<CR>")
keymap({"n", "v"}, "<leader>po", "<cmd>lua require('vscode').action('projectManager.listProjectsNewWindow')<CR>")
keymap({"n", "v"}, "<leader>pe", "<cmd>lua require('vscode').action('projectManager.editProjects')<CR>")
keymap("v", "(", "S(", {
    desc = "Surround with parantheses",
    remap = true
})
keymap("v", "{", "S{", {
    desc = "Surround with braces",
    remap = true
})

-- [[ Install `lazy.nvim` plugin manager ]]
--    See `:help lazy.nvim.txt` or https://github.com/folke/lazy.nvim for more info
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({"git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath})
    if vim.v.shell_error ~= 0 then
        error("Error cloning lazy.nvim:\n" .. out)
    end
end ---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({ --     {
--     "ggandor/leap.nvim",
--     enabled = true,
--     keys = {{
--         "s",
--         mode = {"n", "x", "o"},
--         desc = "Leap Forward to"
--     }, {
--         "S",
--         mode = {"n", "x", "o"},
--         desc = "Leap Backward to"
--     }, {
--         "gs",
--         mode = {"n", "x", "o"},
--         desc = "Leap from Windows"
--     }},
--     config = function(_, opts)
--         local leap = require("leap")
--         for k, v in pairs(opts) do
--             leap.opts[k] = v
--         end
--         -- leap.add_default_mappings(true)
--         vim.keymap.set({"n", "x", "o"}, "s", "<Plug>(leap-anywhere)")
--         -- vim.keymap.set('x', 's', '<Plug>(leap)')
--         -- vim.keymap.set('o', 's', '<Plug>(leap-forward)')
--         -- vim.keymap.set('o', 'S', '<Plug>(leap-backward)')
--         -- -- Safely delete mappings if they exist
--         -- local function safe_del(mode, key)
--         --     local success, _ = pcall(vim.keymap.del, mode, key)
--         --     if not success then
--         --         print("Mapping not found for " .. key)
--         --     end
--         -- end
--         -- safe_del({"x", "o"}, "x")
--         -- safe_del({"x", "o"}, "X")
--     end,
--     event = "VeryLazy"
-- }, 
{
    "kylechui/nvim-surround",
    event = "VeryLazy",
    config = function()
        require("nvim-surround").setup()
    end
}})
