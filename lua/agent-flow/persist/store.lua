local M = {}

local dirty = false
local timer_armed = false

---@return string
local function state_dir()
  return vim.fn.stdpath("data") .. "/agent-flow"
end

---@return string
local function state_file()
  local registry = require("agent-flow.core.registry")
  local key = require("agent-flow.util").project_key(registry.root or vim.fn.getcwd())
  return state_dir() .. "/" .. key .. ".json"
end

---Write current registry state to disk.
function M.save()
  if not require("agent-flow.config").options.persist.enabled then
    return
  end
  local registry = require("agent-flow.core.registry")
  local threads = {}
  for _, t in ipairs(registry.threads) do
    table.insert(threads, t:to_state())
  end
  local state = {
    version = 1,
    root = registry.root,
    last_active = registry.last_active,
    threads = threads,
  }
  local ok, encoded = pcall(vim.json.encode, state)
  if not ok then
    return
  end
  vim.fn.mkdir(state_dir(), "p")
  local f = io.open(state_file(), "w")
  if f then
    f:write(encoded)
    f:close()
  end
  dirty = false
end

---Debounced save; safe to call from event streams.
function M.save_debounced()
  dirty = true
  if timer_armed then
    return
  end
  timer_armed = true
  vim.defer_fn(function()
    timer_armed = false
    if dirty then
      M.save()
    end
  end, 500)
end

---Load persisted threads into the registry (called once from setup).
function M.load()
  if not require("agent-flow.config").options.persist.enabled then
    return
  end
  local f = io.open(state_file(), "r")
  if not f then
    return
  end
  local content = f:read("*a")
  f:close()
  local ok, state = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  if not ok or type(state) ~= "table" or type(state.threads) ~= "table" then
    return
  end
  local registry = require("agent-flow.core.registry")
  local Thread = require("agent-flow.core.thread")
  for _, data in ipairs(state.threads) do
    -- Drop threads whose worktree/cwd vanished since last session.
    if vim.fn.isdirectory(data.cwd or "") == 1 then
      table.insert(registry.threads, Thread.from_state(data))
    end
  end
  registry.last_active = state.last_active
end

return M
