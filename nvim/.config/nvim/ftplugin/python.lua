local mypy_timer = nil

vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = "*.py",
  callback = function(args)
    if mypy_timer then
      mypy_timer:stop()
    end
    mypy_timer = vim.defer_fn(function()
      vim.system({ "uv", "run", "mypy", args.file }, { text = true }, function(obj)
        vim.schedule(function()
          if obj.code == 0 then
            vim.cmd("cclose")
            return
          end
          vim.fn.setqflist({}, " ", {
            title = "mypy",
            efm = "%f:%l: %m",
            lines = vim.split(obj.stdout, "\n", { trimempty = true }),
          })
          vim.cmd("copen")
        end)
      end)
    end, 300)
  end,
})
