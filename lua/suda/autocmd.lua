local callbacks = require("callbacks")

if vim.api.nvim_get_var("suda_did_setup") then
  return
end

vim.api.nvim_set_var("suda_did_setup", true)

if vim.api.nvim_get_var("suda_smart_edit") then
  local augroup_suda_smart_edit =
    vim.api.nvim_create_augroup("suda_smart_edit", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup_suda_smart_edit,
    pattern = "*",
    callback = callbacks.SudaBufEnter,
    nested = true,
  })
end

local augroup_suda_plugin =
  vim.api.nvim_create_augroup("suda_plugin", { clear = true })

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = augroup_suda_plugin,
  pattern = "suda://*",
  callback = callbacks.SudaBufReadCmd,
})

vim.api.nvim_create_autocmd("FileReadCmd", {
  group = augroup_suda_plugin,
  pattern = "suda://*",
  callback = callbacks.SudaFileReadCmd,
})

vim.api.nvim_create_autocmd("BufWriteCmd", {
  group = augroup_suda_plugin,
  pattern = "suda://*",
  callback = callbacks.SudaBufWriteCmd,
})

vim.api.nvim_create_autocmd("FileWriteCmd", {
  group = augroup_suda_plugin,
  pattern = "suda://*",
  callback = callbacks.SudaFileWriteCmd,
})

local function read(args)
  local args = vim.fn.empty(args) and vim.fn.expand("%:p") or args
  vim.fn.execute(vim.fn.printf("edit suda://%s", args))
end

vim.api.nvim_create_user_command("SudaRead", function(params)
  read(params.args)
end, { bang = true, nargs = "?", complete = "file" })

local function write(args)
  local args = vim.fn.empty(args) and vim.fn.expand("%:p") or args
  vim.fn.execute(vim.fn.printf("write suda://%s", args))
end

vim.api.nvim_create_user_command("SudaWrite", function(params)
  write(params.args)
end, { bang = true, nargs = "?", complete = "file" })
