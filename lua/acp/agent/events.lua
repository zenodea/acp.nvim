local util = require("acp.util")

---Rendering helpers for ACP `session/update` payloads.
local M = {}

local status_suffix = {
  pending = " …",
  in_progress = " …",
  completed = "",
  failed = " ✗",
}

---Extract plain text from an ACP content block.
---@param content table|nil
---@return string
function M.content_text(content)
  if type(content) ~= "table" then
    return ""
  end
  if content.type == "text" then
    return content.text or ""
  end
  if content.type == "resource_link" then
    return content.uri or content.name or ""
  end
  return ""
end

---Lines for a tool call's content items (diffs).
---@param content table[]|nil
---@return string[]
function M.tool_content_lines(content)
  local cfg = require("acp.config").options.ui
  if not cfg.show_diffs or type(content) ~= "table" then
    return {}
  end
  local lines = {}
  local function push(prefix, text)
    for _, l in ipairs(util.lines(text or "")) do
      table.insert(lines, prefix .. l)
    end
  end
  for _, item in ipairs(content) do
    if item.type == "diff" then
      if item.oldText and item.oldText ~= "" then
        push("- ", item.oldText)
      end
      push("+ ", item.newText)
    elseif item.type == "terminal" and item.terminalId then
      vim.list_extend(lines, require("acp.agent.terminal").render_lines(item.terminalId, cfg.diff_max_lines))
    end
  end
  if #lines > cfg.diff_max_lines then
    local total = #lines
    lines = vim.list_slice(lines, 1, cfg.diff_max_lines)
    table.insert(lines, string.format("… (%d more lines)", total - cfg.diff_max_lines))
  end
  return lines
end

---One rendered text block for a tool call (first line = title + status).
---@param call table merged tool_call / tool_call_update fields
---@return string
function M.tool_text(call)
  local title = call.title or call.kind or "tool"
  local head = util.shorten(title, 70) .. (status_suffix[call.status or "pending"] or "")
  local lines = { head }
  vim.list_extend(lines, M.tool_content_lines(call.content))
  return table.concat(lines, "\n")
end

---Rendered text for a plan update.
---@param entries table[]
---@return string
function M.plan_text(entries)
  local icons = { pending = "○", in_progress = "◐", completed = "●" }
  local lines = { "Plan:" }
  for _, e in ipairs(entries or {}) do
    table.insert(lines, string.format("  %s %s", icons[e.status] or "○", e.content or ""))
  end
  return table.concat(lines, "\n")
end

return M
