---Subagent tracking and its panel (gs).
---
---ACP has no first-class notion of a subagent: an agent that delegates work
---reports it as an ordinary tool call. Calls whose title matches one of the
---configured `subagent_patterns` are treated as spawns — they get their own
---icon in the transcript and are collected per thread so the panel can list
---them with their status and how long they ran.
---
---The list is live-run state (like the session itself), not conversation
---history: it is kept on the thread but never persisted, since a restored
---"running" subagent could only ever be a lie.
local M = {}

local ns = vim.api.nvim_create_namespace("acp-subagents")

---Most recent spawns kept per thread.
local MAX = 50

local icons = { pending = "○", in_progress = "◐", completed = "✓", failed = "✗" }
local labels = { pending = "queued", in_progress = "running", completed = "done", failed = "failed" }
local groups = {
  pending = "AcpChatMeta",
  in_progress = "AcpStatusWorking",
  completed = "AcpStatusIdle",
  failed = "AcpStatusError",
}

---Does this tool-call title look like an agent delegating work?
---@param title string|nil
---@return boolean
function M.is_subagent(title)
  if type(title) ~= "string" then
    return false
  end
  for _, pattern in ipairs(require("acp.config").options.subagent_patterns or {}) do
    if title:match(pattern) then
      return true
    end
  end
  return false
end

---@param thread Thread
---@param id string toolCallId
---@return table|nil
local function find(thread, id)
  for _, entry in ipairs(thread.subagents or {}) do
    if entry.id == id then
      return entry
    end
  end
end

---Record a spawn, or a status change on one already tracked. Tool calls that
---never looked like a subagent are ignored, so this is safe to call for
---every tool call.
---@param thread Thread
---@param id string toolCallId
---@param title string|nil
---@param status string|nil
---@return boolean tracked whether `id` is a subagent
function M.track(thread, id, title, status)
  local entry = find(thread, id)
  if not entry then
    if not M.is_subagent(title) then
      return false
    end
    thread.subagents = thread.subagents or {}
    entry = { id = id, started = os.time() }
    table.insert(thread.subagents, entry)
    if #thread.subagents > MAX then
      table.remove(thread.subagents, 1)
    end
  end
  entry.title = title or entry.title
  entry.status = status or entry.status or "pending"
  -- Freeze the runtime at the first terminal status; later updates (content
  -- arriving after completion) must not stretch it.
  if (entry.status == "completed" or entry.status == "failed") and not entry.ended then
    entry.ended = os.time()
  end
  return true
end

---How many of the thread's subagents have not finished.
---@param thread Thread
---@return integer
function M.running(thread)
  local n = 0
  for _, entry in ipairs(thread.subagents or {}) do
    if entry.status == "pending" or entry.status == "in_progress" then
      n = n + 1
    end
  end
  return n
end

---@param entry table
---@return string
local function duration(entry)
  local secs = (entry.ended or os.time()) - (entry.started or os.time())
  if secs < 60 then
    return secs .. "s"
  end
  return ("%dm%02ds"):format(math.floor(secs / 60), secs % 60)
end

---Open the thread's subagents in a float. The rows are a snapshot: reopen
---to re-read the clock. q or :q closes it.
---@param thread Thread
function M.open(thread)
  local entries = thread.subagents or {}
  if #entries == 0 then
    vim.notify("acp: no subagents spawned in this thread", vim.log.levels.INFO)
    return
  end
  local util = require("acp.util")

  -- Title column padded to the widest entry so the status column lines up.
  local rows, width = {}, 0
  for i, entry in ipairs(entries) do
    local status = entry.status or "pending"
    local title = util.shorten(entry.title or "subagent", 48)
    rows[i] = {
      head = (" %s "):format(icons[status] or icons.pending),
      title = title,
      meta = ("%s · %s"):format(labels[status] or status, duration(entry)),
      group = groups[status] or "AcpChatMeta",
    }
    width = math.max(width, vim.fn.strdisplaywidth(title))
  end

  local lines = {}
  for i, row in ipairs(rows) do
    row.body = row.title .. string.rep(" ", width - vim.fn.strdisplaywidth(row.title)) .. "  "
    lines[i] = row.head .. row.body .. row.meta
  end

  local buf = util.scratch_buf(nil, { bufhidden = "wipe" })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local running = M.running(thread)
  local win = util.centered_float(buf, {
    lines = #lines,
    title = (" subagents — %d of %d running · q closes "):format(running, #entries),
  })
  vim.wo[win].wrap = false
  -- Colour the status glyph and dim the trailing meta, leaving the title
  -- plain — the same restraint as the sidebar's thread rows.
  for i, row in ipairs(rows) do
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 1, { end_col = #row.head - 1, hl_group = row.group })
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, #row.head + #row.body, {
      end_col = #lines[i],
      hl_group = "AcpChatMeta",
    })
  end
  vim.keymap.set("n", "q", function()
    pcall(vim.api.nvim_win_close, win, true)
  end, { buffer = buf, nowait = true, desc = "Close the subagent panel" })
end

return M
