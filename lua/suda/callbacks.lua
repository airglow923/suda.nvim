local M = {}

if vim.g.suda_no_pass == nil then
  vim.api.nvim_set_var("suda_no_pass", false)
end

if vim.g.suda_prompt == nil then
  vim.api.nvim_set_var("suda_prompt", "Password: ")
end

local function escape_patterns(expr)
  return vim.fn.escape(expr, "^$~.*[]\\")
end

local function strip_prefix(expr)
  return vim.fn.substitute(expr, "\v^(suda://)+", "", "")
end

local function echomsg_exception()
  vim.cmd.redraw()

  for _, line in ipairs(vim.fn.split(vim.api.nvim_get_vvar("exception"), "\n")) do
    local txt = vim.fn.printf("[sudo] %s", line)
    vim.api.nvim_echo({ { txt, "ErrorMsg" } }, false, {})
  end
end

local function SudaSystem(cmd, ...)
  local varargs = { ... }

  if vim.fn.has("win32") or vim.api.nvim_get_var("suda_no_pass") then
    cmd = vim.fn.printf("sudo %s", cmd)
  else
    cmd = vim.fn.printf("sudo -p '' -n %s", cmd)
  end

  if vim.api.nvim_get_option_value("verbose", {}) then
    local txt = vim.fn.printf("[sudo] %s", cmd)
    vim.api.nvim_echo({ { txt } }, true, {})
  end

  local result = (varargs[0] ~= nil) and vim.fn.system(cmd, varargs[1])
    or vim.fn.system(cmd)

  if vim.api.nvim_get_vvar("shell_error") == 0 then
    return result
  end

  local password

  pcall(function()
    vim.fn.inputsave()
    vim.cmd.redraw()
    password = vim.fn.inputsecret(vim.api.nvim_get_var("suda_prompt"))
  end)

  pcall(vim.fn.inputrestore)

  cmd = vim.fn.printf("sudo -p '' -S %s", cmd)
  password =
    vim.fn.printf("%s\n%s", password, (varargs[0] ~= nil) and varargs[1] or "")

  return vim.fn.system({ cmd, password })
end

local function SudaRead(expr, ...)
  local varargs = { ... }
  local path = vim.fn.fnamemodify(strip_prefix(vim.fn.expand(expr)), ":p")
  local options = vim.fn.extend({
    cmdarg = vim.api.nvim_get_vvar("cmdarg"),
    range = "",
  }, { (varargs[0] ~= nil) and varargs[1] or {} })

  if vim.fn.filereadable(path) then
    local cmd =
      vim.fn.printf("%sread %s %s", options.range, options.cmdarg, path)
    local output = vim.api.nvim_exec2(cmd)
    return vim.fn.substitute(output, "^\r\\?\n", "", "")
  end

  local tempfile = vim.fn.tempname()

  local _, ret = pcall(function()
    local redirect
    local cmd
    local result

    if
      vim.regex("%s"):match_str(vim.api.nvim_get_option_value("shellredir", {}))
      ~= nil
    then
      redirect = vim.fn.printf(
        vim.api.nvim_get_option_value("shellredir", {}),
        vim.fn.shellescape(tempfile)
      )
    else
      redirect = vim.api.nvim_get_option_value("shellredir", {})
        .. vim.fn.shellescape(tempfile)
    end

    cmd = vim.fn.printf(
      "cat %s %s",
      vim.fn.shellescape(vim.fn.fnamemodify(path, ":p")),
      redirect
    )
    result = SudaSystem(cmd)

    if vim.api.nvim_get_vvar("shell_error") ~= 0 then
      error(result)
    end

    cmd = vim.fn.printf("%sread %s %s", options.range, options.cmdarg, tempfile)
    result = vim.api.nvim_exec2(cmd)
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

local function SudaWrite(expr, ...)
  local varargs = { ... }
  local path = vim.fn.fnamemodify(strip_prefix(vim.fn.expand(expr)), ":p")
  local options = vim.fn.extend({
    cmdarg = vim.api.nvim_get_vvar("cmdarg"),
    cmdbang = vim.api.nvim_get_vvar("cmdbang"),
    range = "",
  }, { (varargs[0] ~= nil) and varargs[1] or {} })
  local tempfile = vim.fn.tempname()

  local _, ret = pcall(function()
    local cmd = vim.fn.printf(
      "%swrite%s %s %s",
      options.range,
      options.cmdbang and "!" or "",
      options.cmdarg,
      tempfile
    )
    local echo_message = vim.api.nvim_exec2(cmd)
    local result

    if vim.fn.has("win32") then
      cmd = vim.fn.exepath("tee")
      result = SudaSystem(
        vim.fn.printf(
          "%s %s",
          vim.fn.shellescape(cmd),
          vim.fn.shellescape(path)
        ),
        vim.fn.join(vim.fn.readfile(tempfile, "b"), "\n")
      )
    else
      result = SudaSystem(
        vim.fn.printf(
          "dd if=%s of=%s bs=1048576",
          vim.fn.shellescape(tempfile),
          vim.fn.shellescape(path)
        )
      )
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

    if not vim.fn.empty(vim.fn.getftype(path)) then
      echo_message = vim.fn.substitute(echo_message, "\\[New\\] ", "", "g")
    end

    return vim.fn.substitute(result, "^\r\\?\n", "", "")
  end)

  pcall(vim.fn.delete, tempfile)

  return ret
end

local function SudaBufEnter()
  if vim.api.nvim_buf_get_var(0, "suda_smart_edit_checked") then
    return
  end

  vim.api.nvim_buf_set_var(0, "suda_smart_edit_checked", true)

  local bufname = vim.fn.expand("<afile>")

  if
    not vim.fn.empty(
      vim.api.nvim_get_option_value("buftype", { buf = vim.fn.bufnr() })
    )
    or vim.fn.empty(bufname)
    or vim.fn.match(bufname, "^[a-z]\\+://*") ~= -1
    or vim.fn.isdirectory(bufname)
  then
    return
  end

  if vim.fn.filereadable(bufname) and vim.fn.filewritable(bufname) then
    return
  end

  if vim.fn.empty(vim.fn.getftype(bufname)) then
    local parent = vim.fn.fnamemodify(bufname, ":p")

    while parent ~= vim.fn.fnamemodify(parent, ":h") do
      parent = vim.fn.fnamemodify(parent, ":h")

      if vim.fn.filewritable(parent) == 2 then
        return
      end

      if not vim.fn.filereadable(parent) and vim.fn.isdirectory(parent) then
        break
      end
    end
  end

  local cmd = vim.fn.printf(
    "keepalt keepjumps edit suda://%s",
    vim.fn.fnamemodify(bufname, ":p")
  )
  vim.api.nvim_exec2(cmd)

  local bufnr = vim.fn.str2nr(vim.fn.expand("<abuf>"))
  -- TODO: remove after check
  -- vim.api.nvim_exec2(vim.fn.printf("%dbwipeout", bufnr))
  vim.cmd.bwipeout(bufnr)
end

local function SudaBufReadCmd()
  vim.cmd.doautocmd({ args = { "<nomodeline>", "BufReadPre" } })

  local ul = vim.api.nvim_get_option_value("undolevels", {})

  vim.api.nvim_set_option_value("undolevels", -1, {})

  local status, _ = pcall(function()
    vim.api.nvim_exec2("0delete _")
    vim.api.nvim_set_option_value("buftype", "acwrite", { scope = "local" })
    vim.api.nvim_set_option_value("backup", false, { scope = "local" })
    vim.api.nvim_set_option_value("swapfile", false, { scope = "local" })
    vim.api.nvim_set_option_value("undofile", false, { scope = "local" })
    vim.api.nvim_set_option_value("modified", false, { scope = "local" })
    vim.cmd.filetype("detect")
    vim.cmd.redraw()

    local echo_message = SudaRead("<afile>", { range = 1 })
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

local function SudaFileReadCmd()
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

    local echo_message = SudaRead("<afile>", { range = range })
    vim.api.nvim_echo({ { echo_message } }, false, {})
  end)

  if not status then
    echomsg_exception()
  end

  pcall(vim.cmd.doautocmd, { args = { "<nomodeline>", "FileReadPost" } })
end

local function SudaBufWriteCmd()
  vim.cmd.doautocmd({ args = { "<nomodeline>", "BufWritePre" } })

  local status, _ = pcall(function()
    local lhs = vim.fn.expand("%:p")
    local rhs = vim.fn.expand("<afile>")

    if lhs == rhs or lhs == vim.fn.substitute(rhs, "^suda://", "", "") then
      vim.api.nvim_set_option_value("modified", false, { scope = "local" })
    end

    vim.cmd.redraw()

    local echo_message = SudaWrite("<afile>", { range = "'[,']" })
    vim.api.nvim_echo({ { echo_message } }, false, {})
  end)

  if not status then
    echomsg_exception()
  end

  pcall(vim.cmd.doautocmd, { args = { "<nomodeline>", "BufWritePost" } })
end

local function SudaFileWriteCmd()
  vim.cmd.doautocmd({ args = { "<nomodeline>", "FileWritePre" } })

  local status, _ = pcall(function()
    vim.cmd.redraw()

    local echo_message = SudaWrite("<afile>", { range = "'[,']" })
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

M.SudaBufEnter = SudaBufEnter
M.SudaBufReadCmd = SudaBufReadCmd
M.SudaFileReadCmd = SudaFileReadCmd
M.SudaBufWriteCmd = SudaBufWriteCmd
M.SudaFileWriteCmd = SudaFileWriteCmd

return M
