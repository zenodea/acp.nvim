local M = {}

---Deep-equality assertion with a readable failure message.
function M.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(
      string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

---A fresh thread table sufficient for chat/session modules.
---@param id string
function M.thread(id)
  return { id = id, slug = id, transcript = {} }
end

---Stub a module in package.loaded, returning it.
function M.stub(name, value)
  package.loaded[name] = value
  return value
end

return M
