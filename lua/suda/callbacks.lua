local utils = require("suda.utils")
local configs = require("suda.configs")

local M = {}

local function escape_patterns(expr)
  return vim.fn.escape(expr, "^$~.*[]\\")
end

local function strip_prefix(expr)
  return vim.fn.substitute(expr, "\\v^(suda://)+", "", "")
end

local function echomsg_exception()
  vim.cmd.redraw()

  for _, line in ipairs(vim.fn.split(vim.api.nvim_get_vvar("exception"), "\n")) do
    local txt = vim.fn.printf("[sudo] %s", line)
    vim.api.nvim_echo({ { txt, "ErrorMsg" } }, false, {})
  end
end

local function enhance_cmd(opts, cmd)
  local ret = cmd
  local exe = configs.user_opts.executable

  if exe == "sudo" then
    ret = utils.merge_table(opts, { "--" }, cmd)
  end

  local escaped = vim.fn.map(ret, function(_, v)
    return vim.fn.shellescape(v)
  end)

  return vim.fn.join(utils.merge_table({ exe }, escaped), " ")
end

local function suda_systemlist(cmd, ...)
  local varargs = { ... }
  local real_cmd = cmd

  if vim.fn.has("win32") == 1 or configs.user_opts.no_pass then
    real_cmd = enhance_cmd({}, cmd)
  else
    real_cmd = enhance_cmd({ "-p", "", "-n" }, cmd)
  end

  if vim.api.nvim_get_option_value("verbose", {}) == 1 then
    local txt = vim.fn.printf("[suda] %s", real_cmd)
    vim.api.nvim_echo({ { txt } }, true, {})
  end

  local ret = (varargs[1] ~= nil) and vim.fn.systemlist(real_cmd, varargs[1])
    or vim.fn.systemlist(real_cmd)

  if vim.api.nvim_get_vvar("shell_error") == 0 then
    return ret
  end

  local pw_needed = true

  if configs.user_opts.executable == "sudo" then
    local pwless_cmd = enhance_cmd({ "-n" }, { "true" })
    ret = vim.fn.systemlist(pwless_cmd)

    if vim.api.nvim_get_vvar("shell_error") == 0 then
      real_cmd = enhance_cmd({}, cmd)
      pw_needed = false
    end
  end

  local password = ""

  if pw_needed then
    pcall(function()
      vim.fn.inputsave()
      vim.cmd.redraw()
      password = vim.fn.inputsecret(configs.user_opts.prompt)
    end)

    pcall(vim.fn.inputrestore)

    real_cmd = enhance_cmd({ "-p", "", "-S" }, cmd)
  end

  return vim.fn.systemlist(
    real_cmd,
    password .. "\n" .. ((varargs[1] ~= nil) and varargs[1] or "")
  )
end

local function suda_system(cmd, ...)
  local output = suda_systemlist(utils.merge_table({ cmd }, { ... }))

  return vim.fn.join(
    vim.fn.map(output, function(_, v)
      return vim.fn.substitute(v, "\n", "", "g")
    end),
    "\n"
  )
end

local function suda_read(expr, ...)
  local varargs = { ... }
  local path = vim.fn.fnamemodify(strip_prefix(vim.fn.expand(expr)), ":p")
  local options = vim.fn.extend({
    cmdarg = vim.api.nvim_get_vvar("cmdarg"),
    range = "",
  }, varargs[1] ~= nil and varargs[1] or {})

  if vim.fn.filereadable(path) == 1 then
    local cmd = vim.fn.printf(
      "%sread %s %s",
      options.range,
      options.cmdarg,
      vim.fn.fnameescape(path)
    )
    local output = vim.fn.execute(cmd)
    return vim.fn.substitute(output, "^\r\\?\n", "", "")
  end

  local tempfile = vim.fn.tempname()

  local _, ret = pcall(function()
    local cmd
    local result

    result = suda_systemlist({ "cat", vim.fn.fnamemodify(path, ":p") })

    if vim.api.nvim_get_vvar("shell_error") ~= 0 then
      error(result)
    end

    pcall(vim.fn.writefile, result, tempfile, "b")

    cmd = vim.fn.printf(
      "%sread %s %s",
      options.range,
      options.cmdarg,
      vim.fn.fnameescape(tempfile)
    )

    result = vim.api.execute(cmd)
    result = vim.fn.substitute(
      result,
      escape_patterns(tempfile),
      vim.fn.fnamemodify(path, ":~"),
      "g"
    )

    return vim.fn.substitute(result, "^\r\\?\n", "", "")
  end)

  pcall(vim.fn.delete, tempfile)

  return ret
end

local function suda_write(expr, ...)
  local varargs = { ... }
  local path = vim.fn.fnamemodify(strip_prefix(vim.fn.expand(expr)), ":p")
  local options = vim.fn.extend({
    cmdarg = vim.api.nvim_get_vvar("cmdarg"),
    cmdbang = vim.api.nvim_get_vvar("cmdbang"),
    range = "",
  }, varargs[1] ~= nil and varargs[1] or {})
  local tempfile = vim.fn.tempname()

  local _, ret = pcall(function()
    local cmd = vim.fn.printf(
      "%swrite%s %s %s",
      options.range,
      options.cmdbang ~= 0 and "!" or "",
      options.cmdarg,
      vim.fn.fnameescape(tempfile)
    )
    local echo_message = vim.fn.execute(cmd)
    local result

    if vim.fn.has("win32") == 1 then
      cmd = vim.fn.exepath("tee")
      result = suda_system(
        cmd,
        path,
        vim.fn.join(vim.fn.readfile(tempfile, "b"), "\n")
      )
    else
      result = suda_system("dd", "if=" .. tempfile, "of=" .. path, "bs=1048576")
    end

    if vim.api.nvim_get_vvar("shell_error") ~= 0 then
      error(result)
    end

    echo_message = vim.fn.substitute(
      echo_message,
      escape_patterns(tempfile),
      vim.fn.fnamemodify(path, ":~"),
      "g"
    )

    if vim.fn.empty(vim.fn.getftype(path)) == 0 then
      echo_message = vim.fn.substitute(echo_message, "\\[New\\] ", "", "g")
    end

    return vim.fn.substitute(result, "^\r\\?\n", "", "")
  end)

  pcall(vim.fn.delete, tempfile)

  return ret
end

local function suda_BufEnter()
  if vim.api.nvim_buf_get_var(0, "suda_smart_edit_checked") == 1 then
    return
  end

  vim.api.nvim_buf_set_var(0, "suda_smart_edit_checked", true)

  local bufname = vim.fn.expand("<afile>")

  if
    vim.fn.empty(
        vim.api.nvim_get_option_value("buftype", { buf = vim.fn.bufnr() })
      )
      == 0
    or vim.fn.empty(bufname) == 1
    or vim.fn.match(bufname, "^[a-z]\\+://*") ~= -1
    or vim.fn.isdirectory(bufname) == 1
  then
    return
  end

  if
    vim.fn.filereadable(bufname) == 1 and vim.fn.filewritable(bufname) == 1
  then
    return
  end

  if vim.fn.empty(vim.fn.getftype(bufname)) == 1 then
    local parent = vim.fn.fnamemodify(bufname, ":p")

    while parent ~= vim.fn.fnamemodify(parent, ":h") do
      parent = vim.fn.fnamemodify(parent, ":h")

      if vim.fn.filewritable(parent) == 2 then
        return
      end

      if
        vim.fn.filereadable(parent) == 0 and vim.fn.isdirectory(parent) == 1
      then
        break
      end
    end
  end

  local cmd = vim.fn.printf(
    "keepalt keepjumps edit suda://%s",
    vim.fn.fnamemodify(bufname, ":p")
  )
  vim.api.execute(cmd)

  local bufnr = vim.fn.str2nr(vim.fn.expand("<abuf>"))
  vim.cmd.bwipeout(bufnr)
end

local function suda_BufReadCmd()
  vim.cmd.doautocmd({ args = { "<nomodeline>", "BufReadPre" } })

  local ul = vim.api.nvim_get_option_value("undolevels", {})

  vim.api.nvim_set_option_value("undolevels", -1, {})

  local status, _ = pcall(function()
    vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
    vim.api.nvim_set_option_value("undofile", false, { scope = "local" })

    local echo_message = suda_read("<afile>", { range = 1 })
    vim.api.execute("0delete _")

    vim.api.nvim_set_option_value("buftype", "acwrite", { scope = "local" })
    vim.api.nvim_set_option_value("modified", false, { scope = "local" })
    vim.cmd.filetype("detect")
    vim.cmd.redraw()

    vim.api.nvim_echo({ { echo_message } }, false, {})
  end)

  if not status then
    echomsg_exception()
  end

  pcall(function()
    vim.api.nvim_set_option_value("undolevels", ul, {})
    vim.cmd.doautocmd({ args = { "<nomodeline>", "BufReadPost" } })
  end)
end

local function suda_FileReadCmd()
  vim.cmd.doautocmd({ args = { "<nomodeline>", "FileReadPre" } })

  local status, _ = pcall(function()
    local range

    if
      vim.regex("^0r\\%[ead]\\>"):match_str(vim.fn.histget("cmd", -1)) ~= nil
    then
      range = "0"
    else
      range = "'["
    end

    vim.cmd.redraw()

    local echo_message = suda_read("<afile>", { range = range })
    vim.api.nvim_echo({ { echo_message } }, false, {})
  end)

  if not status then
    echomsg_exception()
  end

  pcall(vim.cmd.doautocmd, { args = { "<nomodeline>", "FileReadPost" } })
end

local function suda_BufWriteCmd()
  vim.cmd.doautocmd({ args = { "<nomodeline>", "BufWritePre" } })

  local status, _ = pcall(function()
    local lhs = vim.fn.expand("%:p")
    local rhs = vim.fn.expand("<afile>")

    if lhs == rhs or lhs == vim.fn.substitute(rhs, "^suda://", "", "") then
      vim.api.nvim_set_option_value("modified", false, { scope = "local" })
    end

    vim.cmd.redraw()

    local echo_message = suda_write("<afile>", { range = "'[,']" })
    vim.api.nvim_echo({ { echo_message } }, false, {})
  end)

  if not status then
    echomsg_exception()
  end

  pcall(vim.cmd.doautocmd, { args = { "<nomodeline>", "BufWritePost" } })
end

local function suda_FileWriteCmd()
  vim.cmd.doautocmd({ args = { "<nomodeline>", "FileWritePre" } })

  local status, _ = pcall(function()
    vim.cmd.redraw()

    local echo_message = suda_write("<afile>", { range = "'[,']" })
    vim.api.nvim_echo({ { echo_message } }, false, {})
  end)

  if not status then
    echomsg_exception()
  end

  pcall(vim.cmd.doautocmd, { args = { "<nomodeline>", "FileWritePost" } })
end

local augroup_suda_internal =
  vim.api.nvim_create_augroup("suda_internal", { clear = true })

vim.api.nvim_create_autocmd({
  "BufReadPre",
  "BufReadPost",
  "FileReadPre",
  "FileReadPost",
  "BufWritePre",
  "BufWritePost",
  "FileWritePre",
  "FileWritePost",
}, {
  group = augroup_suda_internal,
  pattern = "suda://*",
  callback = function() end,
})

M.suda_BufEnter = suda_BufEnter
M.suda_BufReadCmd = suda_BufReadCmd
M.suda_FileReadCmd = suda_FileReadCmd
M.suda_BufWriteCmd = suda_BufWriteCmd
M.suda_FileWriteCmd = suda_FileWriteCmd

return M
