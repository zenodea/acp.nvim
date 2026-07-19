local M = {}

---@type Thread[]
M.threads = {}
---@type string|nil id of the most recently opened thread
M.last_active = nil
---@type string project root (git root or cwd at setup)
M.root = nil

---@type table<string, fun(...)[]>
local listeners = {}

---Subscribe to registry events: "status", "threads" (list changed), "any".
---@param event string
---@param fn fun(...)
function M.on(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end

---@param event string
function M.emit(event, ...)
  for _, ev in ipairs({ event, "any" }) do
    for _, fn in ipairs(listeners[ev] or {}) do
      local ok, err = pcall(fn, ...)
      if not ok then
        vim.schedule(function()
          vim.notify("agent-flow listener error: " .. tostring(err), vim.log.levels.ERROR)
        end)
      end
    end
  end
end

---@param thread Thread
function M.add(thread)
  table.insert(M.threads, thread)
  M.emit("threads")
end

---@param thread Thread
function M.remove(thread)
  for i, t in ipairs(M.threads) do
    if t.id == thread.id then
      table.remove(M.threads, i)
      break
    end
  end
  if M.last_active == thread.id then
    M.last_active = nil
  end
  M.emit("threads")
end

---@param id string
---@return Thread|nil
function M.get(id)
  for _, t in ipairs(M.threads) do
    if t.id == id then
      return t
    end
  end
end

---@param tabpage integer
---@return Thread|nil
function M.find_by_tab(tabpage)
  for _, t in ipairs(M.threads) do
    if t.tabpage == tabpage then
      return t
    end
  end
end

---@param slug string
---@return Thread|nil
function M.find_by_slug(slug)
  for _, t in ipairs(M.threads) do
    if t.slug == slug then
      return t
    end
  end
end

---@return Thread|nil
function M.last_active_thread()
  if M.last_active then
    local t = M.get(M.last_active)
    if t then
      return t
    end
  end
  return M.threads[1]
end

---Counts per status, for the statusline component.
---@return table<ThreadStatus, integer>
function M.status_counts()
  local counts = { working = 0, attention = 0, idle = 0, error = 0 }
  for _, t in ipairs(M.threads) do
    counts[t.status] = (counts[t.status] or 0) + 1
  end
  return counts
end

return M
