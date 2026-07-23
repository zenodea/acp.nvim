local M = {}

local ns = vim.api.nvim_create_namespace("acp-sidebar")

---@type integer|nil shared threads buffer, shown in one window per thread tab
M.buf = nil
---@type table<integer, string> 1-based line -> thread id
local line_map = {}
---@type integer[] sorted 1-based lines holding a thread *name* (cursor targets)
local name_lines = {}
---@type table<integer, boolean>
local name_set = {}
---@type table<integer, integer> win -> last snapped line (for direction)
local last_pos = {}

---Snap the cursor of the current window to the nearest thread-name line,
---searching in the direction the cursor was moving.
function M.snap()
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= M.buf or #name_lines == 0 then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(win)[1]
  if name_set[lnum] then
    last_pos[win] = lnum
    return
  end
  local prev = last_pos[win]
  local target
  if prev and lnum > prev then -- moving down: next name line at/after cursor
    for _, l in ipairs(name_lines) do
      if l >= lnum then
        target = l
        break
      end
    end
    target = target or name_lines[#name_lines]
  else -- moving up (or unknown): previous name line at/before cursor
    for i = #name_lines, 1, -1 do
      if name_lines[i] <= lnum then
        target = name_lines[i]
        break
      end
    end
    target = target or name_lines[1]
  end
  pcall(vim.api.nvim_win_set_cursor, win, { target, 0 })
  last_pos[win] = target
end

---Place the cursor of every sidebar window on `thread_id`'s name line.
---Sidebar windows keep per-tab cursor positions; without this, switching
---threads lands you on whatever line that tab's sidebar last had.
---@param thread_id string
function M.reveal(thread_id)
  if not M.buf then
    return
  end
  local line
  for _, l in ipairs(name_lines) do
    if line_map[l] == thread_id then
      line = l
      break
    end
  end
  if not line then
    return
  end
  for _, win in ipairs(vim.fn.win_findbuf(M.buf)) do
    pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
    last_pos[win] = line
  end
end

---@return integer
function M.ensure_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "acp://threads")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "acp-threads"
  vim.bo[buf].modifiable = false
  M.buf = buf

  local api = function()
    return require("acp")
  end
  local function thread_at_cursor()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    local id = line_map[lnum]
    return id and require("acp.core.registry").get(id) or nil
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

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    desc = "Keep the cursor on thread lines",
    callback = M.snap,
  })

  M.render()
  return buf
end

function M.render()
  local buf = M.ensure_buf()
  local registry = require("acp.core.registry")
  local options = require("acp.config").options
  local cfg = options.ui
  local hls = require("acp.ui.highlights")

  local lines = { " ACP", "" }
  local marks = { { 0, "AcpSidebarTitle" } }
  line_map = {}
  name_lines = {}
  name_set = {}

  if #registry.threads == 0 then
    table.insert(lines, "  no threads yet")
    table.insert(marks, { #lines - 1, "AcpSidebarHint" })
  end

  for _, t in ipairs(registry.threads) do
    local icon = cfg.icons[t.status] or "·"
    local agent_def = options.agents[t.agent or options.default_agent]
    local agent_icon = agent_def and agent_def.icon
    -- Double space: several agent glyphs render double-width, which visually
    -- swallows a single space before the name.
    local label = agent_icon and (agent_icon .. "  " .. t.name) or t.name
    table.insert(lines, string.format(" %s %s", icon, label))
    line_map[#lines] = t.id
    table.insert(name_lines, #lines)
    name_set[#lines] = true
    table.insert(marks, { #lines - 1, hls.status_group(t.status), #icon + 2 })
    if t.worktree then
      table.insert(lines, "     " .. t.worktree.branch)
      line_map[#lines] = t.id
      table.insert(marks, { #lines - 1, "AcpSidebarBranch" })
    end
    if t.status_detail and (t.status == "attention" or t.status == "error") then
      table.insert(lines, "     " .. t.status_detail)
      line_map[#lines] = t.id
      table.insert(marks, { #lines - 1, "AcpSidebarHint" })
    end
  end

  vim.list_extend(lines, { "", " n new · ⏎ open", " d delete · r rename" })
  table.insert(marks, { #lines - 2, "AcpSidebarHint" })
  table.insert(marks, { #lines - 1, "AcpSidebarHint" })

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

  -- Content shifted: re-snap every window currently showing the sidebar.
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    last_pos[win] = nil
    vim.api.nvim_win_call(win, M.snap)
  end
end

return M
