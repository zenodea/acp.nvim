local M = {}

local ns = vim.api.nvim_create_namespace("claude-agents-sidebar")

---@type integer|nil shared threads buffer, shown in one window per thread tab
M.buf = nil
---@type table<integer, string> 1-based line -> thread id
local line_map = {}

---@return integer
function M.ensure_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "claude-agents://threads")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "claude-agents-threads"
  vim.bo[buf].modifiable = false
  M.buf = buf

  local api = function()
    return require("claude-agents")
  end
  local function thread_at_cursor()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local id = line_map[lnum]
    return id and require("claude-agents.core.registry").get(id) or nil
  end
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, desc = desc, nowait = true })
  end

  map("<CR>", function()
    local t = thread_at_cursor()
    if t then
      api().open_thread(t)
    end
  end, "Open thread")
  map("n", function()
    api().new()
  end, "New thread")
  map("d", function()
    local t = thread_at_cursor()
    if t then
      api().delete(t)
    end
  end, "Delete thread")
  map("r", function()
    local t = thread_at_cursor()
    if t then
      api().rename(t)
    end
  end, "Rename thread")

  M.render()
  return buf
end

function M.render()
  local buf = M.ensure_buf()
  local registry = require("claude-agents.core.registry")
  local cfg = require("claude-agents.config").options.ui
  local hls = require("claude-agents.ui.highlights")

  local lines = { " Claude Agents", "" }
  local marks = { { 0, "ClaudeAgentsSidebarTitle" } }
  line_map = {}

  if #registry.threads == 0 then
    table.insert(lines, "  no threads yet")
    table.insert(marks, { #lines - 1, "ClaudeAgentsSidebarHint" })
  end

  for _, t in ipairs(registry.threads) do
    local icon = cfg.icons[t.status] or "·"
    table.insert(lines, string.format(" %s %s", icon, t.name))
    line_map[#lines] = t.id
    table.insert(marks, { #lines - 1, hls.status_group(t.status), #icon + 2 })
    if t.worktree then
      table.insert(lines, "     " .. t.worktree.branch)
      line_map[#lines] = t.id
      table.insert(marks, { #lines - 1, "ClaudeAgentsSidebarBranch" })
    end
    if t.status_detail and (t.status == "attention" or t.status == "error") then
      table.insert(lines, "     " .. t.status_detail)
      line_map[#lines] = t.id
      table.insert(marks, { #lines - 1, "ClaudeAgentsSidebarHint" })
    end
  end

  vim.list_extend(lines, { "", " n new · ⏎ open", " d delete · r rename" })
  table.insert(marks, { #lines - 2, "ClaudeAgentsSidebarHint" })
  table.insert(marks, { #lines - 1, "ClaudeAgentsSidebarHint" })

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local lnum, group, end_col = m[1], m[2], m[3]
    if end_col then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = end_col, hl_group = group })
    else
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = group })
    end
  end
end

return M
