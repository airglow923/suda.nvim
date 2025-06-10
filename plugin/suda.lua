if vim.g.suda_loaded then
  return
end

vim.api.nvim_set_var("suda_loaded", true)

local M = {}

function M.setup(opts)
  require("suda").setup(opts)
end

return M
