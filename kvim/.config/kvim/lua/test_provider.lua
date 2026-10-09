local M = {}
function M.new() return setmetatable({}, { __index = M }) end
function M:enabled() return true end
function M:get_completions(ctx, callback)
  _G.LAST_CTX = ctx
  callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} })
end
return M
