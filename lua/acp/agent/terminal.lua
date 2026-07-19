---ACP terminal capability: the agent runs commands in terminals we provide,
---so their output can be embedded live in tool calls.
local M = {}

---@class AcpTerminal
---@field job integer
---@field output string combined stdout+stderr
---@field truncated boolean
---@field limit integer|nil outputByteLimit
---@field exit {exitCode: integer|nil, signal: string|nil}|nil
---@field waiters fun(exit: table)[] pending terminal/wait_for_exit responders
---@field on_update fun()|nil

---@type table<string, AcpTerminal>
local terminals = {}
local next_id = 0

---@param term AcpTerminal
---@param chunk string
local function push_output(term, chunk)
  term.output = term.output .. chunk
  if term.limit and #term.output > term.limit then
    -- Spec: truncate from the beginning, keeping the most recent output.
    term.output = term.output:sub(#term.output - term.limit + 1)
    term.truncated = true
  end
  if term.on_update then
    pcall(term.on_update)
  end
end

---@param params table terminal/create params
---@param cwd string fallback working directory
---@param on_update fun()|nil called on new output / exit
---@return string|nil terminal_id, string|nil err
function M.create(params, cwd, on_update)
  local cmd = { params.command }
  vim.list_extend(cmd, params.args or {})
  local env
  for _, pair in ipairs(params.env or {}) do
    env = env or {}
    env[pair.name] = pair.value
  end

  local term = {
    output = "",
    truncated = false,
    limit = params.outputByteLimit,
    exit = nil,
    waiters = {},
    on_update = on_update,
  }

  local function collect(_, data, _)
    if not data then
      return
    end
    local chunk = table.concat(data, "\n")
    if chunk ~= "" then
      push_output(term, chunk)
    end
  end

  local job = vim.fn.jobstart(cmd, {
    cwd = (params.cwd and params.cwd ~= "" and params.cwd) or cwd,
    env = env,
    on_stdout = collect,
    on_stderr = collect,
    on_exit = function(_, code, _)
      term.exit = { exitCode = code }
      local waiters = term.waiters
      term.waiters = {}
      for _, respond in ipairs(waiters) do
        pcall(respond, term.exit)
      end
      if term.on_update then
        pcall(term.on_update)
      end
    end,
  })
  if job <= 0 then
    return nil, "failed to spawn: " .. table.concat(cmd, " ")
  end
  term.job = job

  next_id = next_id + 1
  local id = "term_" .. next_id
  terminals[id] = term
  return id, nil
end

---@param id string
---@return table|nil result for terminal/output
function M.output(id)
  local term = terminals[id]
  if not term then
    return nil
  end
  return { output = term.output, truncated = term.truncated, exitStatus = term.exit }
end

---@param id string
---@param respond fun(exit: table)
---@return boolean known
function M.wait_for_exit(id, respond)
  local term = terminals[id]
  if not term then
    return false
  end
  if term.exit then
    respond(term.exit)
  else
    table.insert(term.waiters, respond)
  end
  return true
end

---@param id string
---@return boolean known
function M.kill(id)
  local term = terminals[id]
  if not term then
    return false
  end
  pcall(vim.fn.jobstop, term.job)
  return true
end

---@param id string
---@return boolean known
function M.release(id)
  local term = terminals[id]
  if not term then
    return false
  end
  pcall(vim.fn.jobstop, term.job)
  terminals[id] = nil
  return true
end

---Rendered tail of a terminal's output for the chat panel.
---@param id string
---@param max_lines integer
---@return string[]
function M.render_lines(id, max_lines)
  local term = terminals[id]
  if not term then
    return {}
  end
  local all = vim.split(term.output:gsub("\n+$", ""), "\n", { plain = true })
  local lines = {}
  local from = math.max(1, #all - max_lines + 1)
  if from > 1 then
    table.insert(lines, string.format("  … (%d earlier lines)", from - 1))
  end
  for i = from, #all do
    if all[i] ~= "" or #lines > 0 then
      table.insert(lines, "  " .. all[i])
    end
  end
  if term.exit then
    table.insert(lines, string.format("  ⏻ exit %s", tostring(term.exit.exitCode)))
  end
  return lines
end

return M
