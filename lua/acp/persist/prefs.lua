local M = {}

---Global (cross-project) preferences, e.g. the favourite model per agent.
---Stored in stdpath("data")/acp/prefs.json.

---@type table|nil
local cache = nil

---@return string
local function prefs_file()
  return vim.fn.stdpath("data") .. "/acp/prefs.json"
end

---@return table
local function load()
  if cache then
    return cache
  end
  cache = require("acp.util").read_json(prefs_file()) or {}
  cache.favourite_models = cache.favourite_models or {}
  return cache
end

local function save()
  require("acp.util").write_json(prefs_file(), cache)
end

---Favourite value of a config option (keyed per agent), e.g. the model id.
---@param agent string
---@param config_id string
---@return string|boolean|nil
function M.get_favourite(agent, config_id)
  local favs = load().favourite_models[agent]
  return favs and favs[config_id]
end

---@param agent string
---@param config_id string
---@param value string|boolean
function M.set_favourite(agent, config_id, value)
  local prefs = load()
  prefs.favourite_models[agent] = prefs.favourite_models[agent] or {}
  if prefs.favourite_models[agent][config_id] == value then
    return
  end
  prefs.favourite_models[agent][config_id] = value
  save()
end

return M
