local M = {}
M.is_search = function()
  local t = vim.fn.getcmdtype()
  return t == '/' or t == '?'
end
return M
