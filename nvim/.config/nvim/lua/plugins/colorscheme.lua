return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      document_highlight = {
        enabled = false,
      },
    },
  },
  {
    "folke/tokyonight.nvim",
    lazy = true,
    opts = { style = "moon" },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "tokyonight",
    },
  },
  -- { "navarasu/onedark.nvim" },
  -- { "nyoom-engineering/oxocarbon.nvim" },
  -- {
  --   "catppuccin/nvim",
  --   lazy = true,
  --   name = "catppuccin",
  --   opts = {
  --     integrations = {
  --       aerial = true,
  --       alpha = true,
  --       cmp = true,
  --       dashboard = true,
  --       flash = true,
  --       grug_far = true,
  --       gitsigns = true,
  --       headlines = true,
  --       illuminate = true,
  --       indent_blankline = { enabled = true },
  --       leap = true,
  --       lsp_trouble = true,
  --       mason = true,
  --       markdown = true,
  --       mini = true,
  --       native_lsp = {
  --         enabled = true,
  --         underlines = {
  --           errors = { "undercurl" },
  --           hints = { "undercurl" },
  --           warnings = { "undercurl" },
  --           information = { "undercurl" },
  --         },
  --       },
  --       navic = { enabled = true, custom_bg = "lualine" },
  --       neotest = true,
  --       neotree = true,
  --       noice = true,
  --       notify = true,
  --       semantic_tokens = true,
  --       telescope = true,
  --       treesitter = true,
  --       treesitter_context = true,
  --       which_key = true,
  --     },
  --   },
  -- },
  -- {
  --   "askfiy/visual_studio_code",
  --   -- priority = 100,
  --   lazy = true,
  --   config = function()
  --     -- vim.cmd([[colorscheme visual_studio_code]])
  --     require("visual_studio_code").setup({
  --       -- `dark` or `light`
  --       mode = "light",
  --       -- Whether to load all color schemes
  --       preset = false,
  --       -- Whether to enable background transparency
  --       transparent = false,
  --       -- Whether to apply the adapted plugin
  --       expands = {
  --         hop = true,
  --         dbui = true,
  --         lazy = true,
  --         aerial = true,
  --         null_ls = true,
  --         nvim_cmp = true,
  --         gitsigns = true,
  --         which_key = true,
  --         nvim_tree = true,
  --         lspconfig = true,
  --         telescope = true,
  --         bufferline = true,
  --         nvim_navic = true,
  --         nvim_notify = true,
  --         vim_illuminate = true,
  --         nvim_treesitter = true,
  --         nvim_ts_rainbow = true,
  --         nvim_scrollview = true,
  --         nvim_ts_rainbow2 = true,
  --         indent_blankline = true,
  --         vim_visual_multi = true,
  --       },
  --       hooks = {
  --         before = function(conf, colors, utils) end,
  --         after = function(conf, colors, utils) end,
  --       },
  --     })
  --   end,
  -- },
}
