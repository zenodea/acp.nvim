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

---Unified-diff lines for a single `diff` content item.
---Uses `vim.diff` so only changed regions (plus a few context lines) render,
---rather than the whole old block followed by the whole new block.
---@param old string
---@param new string
---@param context integer unchanged lines kept around each hunk
---@return string[]
local function diff_lines(old, new, context)
  local old_lines = util.lines(old or "")
  local new_lines = util.lines(new or "")
  -- A brand-new file (no old text) has nothing to diff against.
  if old == nil or old == "" then
    return vim.tbl_map(function(l)
      return "+ " .. l
    end, new_lines)
  end
  local indices = vim.diff(old, new, { result_type = "indices" })
  if type(indices) ~= "table" or #indices == 0 then
    return {} -- identical text; nothing changed
  end
  local out = {}
  local last_old = 0 -- last old-line index already emitted (for context runs)
  for _, hunk in ipairs(indices) do
    local oa, oc, na, nc = hunk[1], hunk[2], hunk[3], hunk[4]
    -- Leading context: unchanged old lines just before this hunk.
    -- `oa` is the first changed old line (or the line after, when oc == 0).
    local ctx_start = math.max(last_old + 1, (oc > 0 and oa or oa + 1) - context)
    local ctx_end = (oc > 0 and oa or oa + 1) - 1
    for i = ctx_start, ctx_end do
      table.insert(out, "  " .. old_lines[i])
    end
    for i = oa, oa + oc - 1 do
      table.insert(out, "- " .. old_lines[i])
    end
    for i = na, na + nc - 1 do
      table.insert(out, "+ " .. new_lines[i])
    end
    -- Trailing context after the change.
    local tail_from = oc > 0 and (oa + oc) or (oa + 1)
    for i = tail_from, math.min(#old_lines, tail_from + context - 1) do
      table.insert(out, "  " .. old_lines[i])
    end
    last_old = math.min(#old_lines, tail_from + context - 1)
  end
  return out
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
      vim.list_extend(lines, diff_lines(item.oldText, item.newText, cfg.diff_context or 3))
    elseif item.type == "terminal" and item.terminalId then
      vim.list_extend(lines, require("acp.agent.terminal").render_lines(item.terminalId, cfg.diff_max_lines))
    elseif item.type == "content" then
      local text = M.content_text(item.content)
      if text ~= "" then
        push("  ", text)
      end
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
