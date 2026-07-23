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
  cache = { favourite_models = {} }
  local f = io.open(prefs_file(), "r")
  if f then
    local content = f:read("*a")
    f:close()
    local ok, decoded = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
    if ok and type(decoded) == "table" then
      decoded.favourite_models = decoded.favourite_models or {}
      cache = decoded
    end
  end
  return cache
end

local function save()
  local ok, encoded = pcall(vim.json.encode, cache)
  if not ok then
    return
  end
  vim.fn.mkdir(vim.fn.stdpath("data") .. "/acp", "p")
  local f = io.open(prefs_file(), "w")
  if f then
    f:write(encoded)
    f:close()
  end
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
