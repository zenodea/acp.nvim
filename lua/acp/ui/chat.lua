local M = {}

local ns = vim.api.nvim_create_namespace("acp-chat")

---Per-thread render state: line range of every transcript entry (so entries
---can be re-rendered in place for streaming chunks and tool-call updates).
---@type table<string, {ranges: {start: integer, count: integer}[], by_id: table<string, integer>, open: boolean}>
local state = {}

---Kinds that can be collapsed/expanded with <CR>, and which of those start
---collapsed. The first line stays visible with a "▸ N more" marker.
local collapsible = { tool = true, thinking = true, permission = true, meta = true, plan = true, error = true }
local default_collapsed = { tool = true, thinking = true }

---@param thread Thread
local function st(thread)
  state[thread.id] = state[thread.id] or { ranges = {}, by_id = {}, open = false, collapsed = {} }
  return state[thread.id]
end

---@param s table chat state
---@param kind string
---@param index integer
---@return boolean
local function is_collapsed(s, kind, index)
  local c = s.collapsed[index]
  if c == nil then
    return default_collapsed[kind] == true
  end
  return c
end

---@param icons table
---@param kind string
---@param text string
---@param collapsed boolean|nil
---@return string[]
local function entry_lines(icons, kind, text, collapsed)
  local body = vim.split(text, "\n", { plain = true })
  -- Every entry starts with one blank line, so completed actions are always
  -- followed by an empty line once the next entry lands.
  if kind == "user" then
    local lines = { "", icons.user .. " You", "" }
    vim.list_extend(lines, body)
    return lines
  elseif kind == "agent" then
    -- Turn header: "❯ provider · model" (text carries "provider · model").
    return { "", icons.user .. " " .. text }
  end

  local prefix = ({ tool = icons.tool, thinking = icons.thinking, error = "✗", permission = icons.permission })[kind]
  local content
  if prefix then
    content = {}
    for i, l in ipairs(body) do
      content[i] = (i == 1 and prefix .. " " or "  ") .. l
    end
  else -- text / meta / plan
    content = body
  end

  if collapsed and collapsible[kind] and #content > 1 then
    return { "", content[1] .. "  ▸ " .. (#content - 1) .. " more" }
  end
  local lines = { "" }
  vim.list_extend(lines, content)
  return lines
end

local kind_hl = {
  thinking = "AcpChatThinking",
  meta = "AcpChatMeta",
  plan = "AcpChatMeta",
  error = "AcpChatError",
  permission = "AcpChatPermission",
}

---@param buf integer
---@param start integer 0-based first line of the entry
---@param lines string[]
---@param kind string
local function apply_hl(buf, start, lines, kind)
  if kind == "user" or kind == "agent" then
    local group = kind == "user" and "AcpChatUser" or "AcpChatAgent"
    vim.api.nvim_buf_set_extmark(buf, ns, start + 1, 0, { line_hl_group = group, priority = 90 })
    return
  end
  local hl = kind_hl[kind]
  for i, l in ipairs(lines) do
    local lnum = start + i - 1
    if kind == "tool" and i == 2 then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = "AcpChatTool", priority = 90 })
    elseif l:match("^%s*%+ ") then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = "AcpDiffAdd", priority = 95 })
    elseif l:match("^%s*%- ") then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = "AcpDiffDelete", priority = 95 })
    elseif hl then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = hl, priority = 90 })
    end
  end
end

---Render a transcript entry appended at the end of the buffer.
---@param thread Thread
---@param buf integer
---@param entry TranscriptEntry
local function push_render(thread, buf, entry)
  local s = st(thread)
  local icons = require("acp.config").options.ui.icons
  local lines = entry_lines(icons, entry.kind, entry.text, is_collapsed(s, entry.kind, #s.ranges + 1))
  local start
  vim.bo[buf].modifiable = true
  if #s.ranges == 0 then
    start = 0
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  else
    local last = s.ranges[#s.ranges]
    start = last.start + last.count
    vim.api.nvim_buf_set_lines(buf, start, start, false, lines)
  end
  vim.bo[buf].modifiable = false
  apply_hl(buf, start, lines, entry.kind)
  table.insert(s.ranges, { start = start, count = #lines })
  if entry.id then
    s.by_id[entry.id] = #s.ranges
  end
end

---Re-render entry `index` in place (its text changed).
---@param thread Thread
---@param index integer
local function rerender(thread, index)
  local buf = thread.chat_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local s = st(thread)
  local range = s.ranges[index]
  local entry = thread.transcript[index]
  if not range or not entry then
    return
  end
  local icons = require("acp.config").options.ui.icons
  local lines = entry_lines(icons, entry.kind, entry.text, is_collapsed(s, entry.kind, index))
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, range.start, range.start + range.count, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, range.start, range.start + #lines)
  apply_hl(buf, range.start, lines, entry.kind)
  local delta = #lines - range.count
  range.count = #lines
  if delta ~= 0 then
    for i = index + 1, #s.ranges do
      s.ranges[i].start = s.ranges[i].start + delta
    end
  end
end

---@param buf integer
local function autoscroll(buf)
  local last = vim.api.nvim_buf_line_count(buf)
  local current_win = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if win ~= current_win then
      pcall(vim.api.nvim_win_set_cursor, win, { last, 0 })
    end
  end
end

---@param thread Thread
---@return integer bufnr
function M.ensure_buf(thread)
  if thread.chat_buf and vim.api.nvim_buf_is_valid(thread.chat_buf) then
    return thread.chat_buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local name = "acp://chat/" .. thread.slug .. "/" .. thread.id
  require("acp.util").wipe_named_buf(name)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  thread.chat_buf = buf

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, desc = desc, nowait = true })
  end
  map("i", function()
    require("acp.ui.input").focus(thread)
  end, "Focus message input")
  map("<C-c>", function()
    if thread.session then
      thread.session:interrupt()
    end
  end, "Interrupt agent")
  map("gm", function()
    require("acp.agent.session").get(thread):select_config()
  end, "Session config (mode/model)")
  map("gf", function()
    local session = require("acp.agent.session").get(thread)
    thread.follow = not session:follow_enabled()
    vim.notify("acp: follow mode " .. (thread.follow and "on" or "off"))
  end, "Toggle follow mode")
  map("<CR>", function()
    M.toggle_at_cursor(thread)
  end, "Expand/collapse entry")

  -- The transcript is reached from the chat input (or sidebar), never
  -- directly from a code window: bounce those entries to the input.
  vim.api.nvim_create_autocmd("WinEnter", {
    buffer = buf,
    callback = function()
      local prev = vim.fn.win_getid(vim.fn.winnr("#"))
      if prev == 0 or not vim.api.nvim_win_is_valid(prev) or vim.w[prev].acp_ui ~= nil then
        return
      end
      local tab = vim.api.nvim_get_current_tabpage()
      local input_win = require("acp.ui.workspace").find_ui_win(tab, "input")
      if input_win then
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(input_win) then
            vim.api.nvim_set_current_win(input_win)
          end
        end)
      end
    end,
  })

  M.replay(thread)
  return buf
end

---Toggle collapse of the entry under the cursor (chat window).
---@param thread Thread
function M.toggle_at_cursor(thread)
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local s = st(thread)
  for index, range in ipairs(s.ranges) do
    if lnum >= range.start and lnum < range.start + range.count then
      M.toggle_entry(thread, index)
      pcall(vim.api.nvim_win_set_cursor, 0, { s.ranges[index].start + 2, 0 })
      return
    end
  end
end

---Toggle collapse of transcript entry `index`.
---@param thread Thread
---@param index integer
function M.toggle_entry(thread, index)
  local entry = thread.transcript[index]
  if not entry or not collapsible[entry.kind] then
    return
  end
  local s = st(thread)
  s.collapsed[index] = not is_collapsed(s, entry.kind, index)
  rerender(thread, index)
end

---Append a new transcript entry and render it.
---@param thread Thread
---@param kind string
---@param text string
---@param id string|nil stable id (e.g. toolCallId) for later updates
function M.append(thread, kind, text, id)
  local entry = { kind = kind, text = text, id = id }
  table.insert(thread.transcript, entry)
  local buf = M.ensure_buf(thread)
  local s = st(thread)
  -- ensure_buf may have just replayed the full transcript (including this entry)
  if #s.ranges < #thread.transcript then
    push_render(thread, buf, entry)
  end
  s.open = false
  autoscroll(buf)
  require("acp.persist.store").save_debounced()
end

---Append a streamed chunk: merges into the last entry when it is an open
---stream of the same kind, otherwise starts a new entry.
---@param thread Thread
---@param kind string
---@param chunk string
function M.stream(thread, kind, chunk)
  local buf = M.ensure_buf(thread)
  local s = st(thread)
  local last = #thread.transcript
  if s.open and last > 0 and thread.transcript[last].kind == kind then
    thread.transcript[last].text = thread.transcript[last].text .. chunk
    rerender(thread, last)
  else
    M.append(thread, kind, chunk)
  end
  s.open = true
  autoscroll(buf)
end

---Close the current stream: the next stream() starts a fresh entry.
---@param thread Thread
function M.close_stream(thread)
  st(thread).open = false
end

---Update the entry registered under `id` (tool-call updates), if any.
---@param thread Thread
---@param id string
---@param text string
---@return boolean found
function M.update_by_id(thread, id, text)
  local s = st(thread)
  local index = s.by_id[id]
  if not index or not thread.transcript[index] then
    return false
  end
  thread.transcript[index].text = text
  rerender(thread, index)
  autoscroll(M.ensure_buf(thread))
  require("acp.persist.store").save_debounced()
  return true
end

---Re-render the whole transcript into the chat buffer (used on restore).
---@param thread Thread
function M.replay(thread)
  local buf = thread.chat_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local s = st(thread)
  s.ranges = {}
  s.by_id = {}
  s.open = false
  s.collapsed = {}
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, entry in ipairs(thread.transcript) do
    push_render(thread, buf, entry)
  end
  autoscroll(buf)
end

return M
