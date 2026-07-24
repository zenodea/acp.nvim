local M = {}

local dirty = false
local timer_armed = false

---@return string
local function state_dir()
  return vim.fn.stdpath("data") .. "/acp"
end

---@return string
local function state_file()
  local registry = require("acp.core.registry")
  local key = require("acp.util").project_key(registry.root or vim.fn.getcwd())
  return state_dir() .. "/" .. key .. ".json"
end

---Write current registry state to disk.
function M.save()
  if not require("acp.config").options.persist.enabled then
    return
  end
  local registry = require("acp.core.registry")
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
  require("acp.util").write_json(state_file(), state)
  dirty = false
end

---Debounced save; safe to call from event streams. The window is generous:
---durability is covered by the forced save on VimLeavePre and on delete,
---and each save re-encodes every thread transcript.
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
  end, 2500)
end

---Load persisted threads into the registry (called once from setup).
function M.load()
  if not require("acp.config").options.persist.enabled then
    return
  end
  local state = require("acp.util").read_json(state_file())
  if not state or type(state.threads) ~= "table" then
    return
  end
  local registry = require("acp.core.registry")
  local Thread = require("acp.core.thread")
  for _, data in ipairs(state.threads) do
    -- Drop threads whose worktree/cwd vanished since last session.
    if vim.fn.isdirectory(data.cwd or "") == 1 then
      table.insert(registry.threads, Thread.from_state(data))
    end
  end
  registry.last_active = state.last_active
end

return M
