local M = {}

M.default_opts = {
  smart_edit = false,
  no_pass = false,
  prompt = "Password: ",
}

M.user_opts = {}

M.setup = function(opts)
  M.user_opts = vim.tbl_deep_extend("force", M.default_opts, opts or {})
end

return M
