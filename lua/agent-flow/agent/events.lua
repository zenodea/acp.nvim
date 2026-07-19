local util = require("agent-flow.util")

local M = {}

---@param line string
---@return table|nil event
function M.decode(line)
  local ok, event = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
  if not ok or type(event) ~= "table" then
    return nil
  end
  return event
end

---One-line human summary of a tool_use content block.
---@param name string
---@param input table
---@return string
function M.tool_summary(name, input)
  input = input or {}
  local detail
  if name == "Bash" then
    detail = input.command
  elseif name == "Read" or name == "Write" then
    detail = input.file_path
  elseif name == "Edit" or name == "MultiEdit" then
    detail = input.file_path
  elseif name == "Grep" then
    detail = input.pattern
  elseif name == "Glob" then
    detail = input.pattern
  elseif name == "WebFetch" or name == "WebSearch" then
    detail = input.url or input.query
  elseif name == "Task" or name == "Agent" then
    detail = input.description or input.prompt
  elseif name == "TodoWrite" then
    detail = "update todo list"
  else
    local ok, encoded = pcall(vim.json.encode, input)
    detail = ok and encoded or ""
  end
  detail = detail and util.shorten(detail, 70) or ""
  if detail ~= "" then
    return string.format("%s: %s", name, detail)
  end
  return name
end

---Render an Edit/Write tool_use input as diff-ish lines (truncated).
---@param name string
---@param input table
---@return string[] lines
function M.tool_diff(name, input)
  local cfg = require("agent-flow.config").options.ui
  local lines = {}
  local function push(prefix, text)
    for _, l in ipairs(util.lines(text or "")) do
      table.insert(lines, prefix .. l)
    end
  end
  if name == "Edit" then
    push("- ", input.old_string)
    push("+ ", input.new_string)
  elseif name == "MultiEdit" then
    for _, edit in ipairs(input.edits or {}) do
      push("- ", edit.old_string)
      push("+ ", edit.new_string)
    end
  elseif name == "Write" then
    push("+ ", input.content)
  end
  if #lines > cfg.diff_max_lines then
    local total = #lines
    lines = vim.list_slice(lines, 1, cfg.diff_max_lines)
    table.insert(lines, string.format("… (%d more lines)", total - cfg.diff_max_lines))
  end
  return lines
end

return M
