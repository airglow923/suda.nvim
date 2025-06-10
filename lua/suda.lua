local M = {}

function M.setup(opts)
  require("suda.configs").setup(opts)
  require("suda.autocmd")
end

return M
