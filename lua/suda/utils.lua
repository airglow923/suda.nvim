local M = {}

M.merge_table = function(...)
  local tbls = { ... }
  local ret = {}

  for _, tbl in pairs(tbls) do
    if type(tbl) ~= "table" then
      goto continue
    end

    for _, v in pairs(tbl) do
      table.insert(ret, v)
    end

    ::continue::
  end

  return ret
end

M.dump = function(o)
  if type(o) == "table" then
    local s = "{ "
    for k, v in pairs(o) do
      if type(k) ~= "number" then
        k = '"' .. k .. '"'
      end
      s = s .. "[" .. k .. "] = " .. M.dump(v) .. ","
    end
    return s .. "} "
  else
    return tostring(o)
  end
end

return M
