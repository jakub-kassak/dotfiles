-- Copilot.
return {
  -- {
  --   "zbirenbaum/copilot.lua",
  --   cmd = "Copilot",
  --   build = ":Copilot auth",
  --   opts = {
  --     suggestion = {
  --       enabled = true,
  --       auto_trigger = false,
  --       hide_during_completion = true,
  --       debounce = 75,
  --       keymap = {
  --         accept = "<M-l>",
  --         accept_word = false,
  --         accept_line = false,
  --         next = "<M-]>",
  --         prev = "<M-[>",
  --         dismiss = "<C-]>",
  --       },
  --     },
  --     panel = { enabled = false },
  --     filetypes = {
  --       markdown = true,
  --       help = true,
  --       yaml = true,
  --     },
  --   },
  -- },
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    opts = {
      -- I don't find the panel useful.
      panel = { enabled = false },
      suggestion = {
        auto_trigger = true,
        -- Use alt to interact with Copilot.
        keymap = {
          -- Disable the built-in mapping, we'll configure it in nvim-cmp.
          accept = false,
          accept_word = "<C-Tab>",
          accept_line = false,
          next = "<C-]>",
          prev = "<C-[>",
          dismiss = "<C-/>",
        },
      },
      filetypes = { markdown = true },
    },
    config = function(_, opts)
      local cmp = require("cmp")
      local copilot = require("copilot.suggestion")
      local luasnip = require("luasnip")

      require("copilot").setup(opts)

      local function set_trigger(trigger)
        vim.b.copilot_suggestion_auto_trigger = trigger
        vim.b.copilot_suggestion_hidden = not trigger
      end

      -- -- Hide suggestions when the completion menu is open.
      -- cmp.event:on("menu_opened", function()
      --   if copilot.is_visible() then
      --     copilot.dismiss()
      --   end
      --   set_trigger(false)
      -- end)

      -- Disable suggestions when inside a snippet.
      cmp.event:on("menu_closed", function()
        set_trigger(not luasnip.expand_or_locally_jumpable())
      end)
      vim.api.nvim_create_autocmd("User", {
        pattern = { "LuasnipInsertNodeEnter", "LuasnipInsertNodeLeave" },
        callback = function()
          set_trigger(not luasnip.expand_or_locally_jumpable())
        end,
      })
    end,
  },
}
