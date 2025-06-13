local configs = require("suda.configs")
local callbacks = require("suda.callbacks")

if configs.user_opts.suda_smart_edit then
  local augroup_suda_smart_edit =
    vim.api.nvim_create_augroup("suda_smart_edit", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup_suda_smart_edit,
    pattern = "*",
    callback = callbacks.suda_BufEnter,
    nested = true,
  })
end

local augroup_suda_plugin =
  vim.api.nvim_create_augroup("suda_plugin", { clear = true })

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = augroup_suda_plugin,
  pattern = "suda://*",
  callback = callbacks.suda_BufReadCmd,
})

vim.api.nvim_create_autocmd("FileReadCmd", {
  group = augroup_suda_plugin,
  pattern = "suda://*",
  callback = callbacks.suda_FileReadCmd,
})

vim.api.nvim_create_autocmd("BufWriteCmd", {
  group = augroup_suda_plugin,
  pattern = "suda://*",
  callback = callbacks.suda_BufWriteCmd,
})

vim.api.nvim_create_autocmd("FileWriteCmd", {
  group = augroup_suda_plugin,
  pattern = "suda://*",
  callback = callbacks.suda_FileWriteCmd,
})

local function read(args)
  local args = vim.fn.empty(args) and vim.fn.expand("%:p") or args
  local cmd = vim.fn.printf("edit suda://%s", vim.fn.fnameescape(args))
  vim.fn.execute(cmd)
end

vim.api.nvim_create_user_command("SudaRead", function(params)
  read(params.args)
end, { bang = true, nargs = "?", complete = "file" })

local function write(args)
  local args = vim.fn.empty(args) and vim.fn.expand("%:p") or args
  local cmd = vim.fn.printf("write suda://%s", vim.fn.fnameescape(args))
  vim.fn.execute(cmd)
end

vim.api.nvim_create_user_command("SudaWrite", function(params)
  write(params.args)
end, { bang = true, nargs = "?", complete = "file" })
