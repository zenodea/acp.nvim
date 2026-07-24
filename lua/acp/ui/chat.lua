local M = {}

local ns = vim.api.nvim_create_namespace("acp-chat")
local ns_pad = vim.api.nvim_create_namespace("acp-chat-pad")

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
  state[thread.id] = state[thread.id] or { ranges = {}, by_id = {}, open = false, collapsed = {}, prev_count = 1 }
  return state[thread.id]
end

---Icons carry their own trailing spacing when it matters (wide nerd-font
---glyphs may need two spaces); plain icons get a single space appended.
---@param icon string
---@return string
local function icon_prefix(icon)
  return icon .. (icon:match("%s$") and "" or " ")
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
---@param entry TranscriptEntry
---@param collapsed boolean|nil
---@return string[]
local function entry_lines(icons, entry, collapsed)
  local kind, text = entry.kind, entry.text
  local body = vim.split(text, "\n", { plain = true })
  -- Every entry starts with one blank line, so completed actions are always
  -- followed by an empty line once the next entry lands.
  if kind == "user" then
    local lines = { "", icon_prefix(icons.user) .. "You", "" }
    vim.list_extend(lines, body)
    return lines
  elseif kind == "agent" then
    -- Turn header: "❯ provider · model" (text carries "provider · model").
    return { "", icon_prefix(icons.user) .. text }
  end

  local prefix
  if kind == "tool" then
    prefix = (icons.tool_kinds or {})[entry.tool] or icons.tool
  else
    prefix = ({ thinking = icons.thinking, error = "✗", permission = icons.permission })[kind]
  end
  local content
  if prefix then
    content = {}
    for i, l in ipairs(body) do
      content[i] = (i == 1 and icon_prefix(prefix) or "  ") .. l
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

---Keep one phantom blank line below the last entry so the transcript never
---touches the separator to the input window.
---@param buf integer
local function update_pad(buf)
  local last = vim.api.nvim_buf_line_count(buf)
  pcall(vim.api.nvim_buf_set_extmark, buf, ns_pad, last - 1, 0, {
    id = 1,
    virt_lines = { { { " ", "Normal" } } },
  })
end

local kind_hl = {
  thinking = "AcpChatThinking",
  meta = "AcpChatMeta",
  plan = "AcpChatMeta",
  error = "AcpChatError",
  permission = "AcpChatPermission",
}

---Byte spans of the changed region between two strings after stripping the
---common prefix/suffix, snapped outward to UTF-8 character boundaries.
---@param a string
---@param b string
---@return integer p common-prefix length
---@return integer ea end of a's changed span (byte index)
---@return integer eb end of b's changed span (byte index)
local function changed_span(a, b)
  local la, lb = #a, #b
  local maxp = math.min(la, lb)
  local p = 0
  while p < maxp and a:byte(p + 1) == b:byte(p + 1) do
    p = p + 1
  end
  while p > 0 and (a:byte(p + 1) or 0) >= 0x80 and (a:byte(p + 1) or 0) < 0xC0 do
    p = p - 1
  end
  local s = 0
  while s < maxp - p and a:byte(la - s) == b:byte(lb - s) do
    s = s + 1
  end
  while s > 0 and a:byte(la - s + 1) >= 0x80 and a:byte(la - s + 1) < 0xC0 do
    s = s - 1
  end
  return p, la - s, lb - s
end

---Accent the changed span of paired -/+ lines: a run of N deletions
---directly followed by N additions pairs index-wise, and only the part
---that actually differs gets the *Text highlight on top of the line one.
---@param buf integer
---@param start integer 0-based first line of the entry
---@param lines string[]
local function apply_intraline_hl(buf, start, lines)
  local i = 1
  while i <= #lines do
    local del_start = i
    while i <= #lines and lines[i]:match("^%s*%- ") do
      i = i + 1
    end
    local dels = i - del_start
    local add_start = i
    while i <= #lines and lines[i]:match("^%s*%+ ") do
      i = i + 1
    end
    if dels > 0 and (i - add_start) == dels then
      for k = 0, dels - 1 do
        local dl, al = lines[del_start + k], lines[add_start + k]
        local d_indent, a_indent = dl:match("^(%s*)"), al:match("^(%s*)")
        local db, ab = dl:sub(#d_indent + 3), al:sub(#a_indent + 3)
        local p, ea, eb = changed_span(db, ab)
        if ea > p then
          local col = #d_indent + 2 + p
          vim.api.nvim_buf_set_extmark(buf, ns, start + del_start + k - 1, col, {
            end_col = #d_indent + 2 + ea,
            hl_group = "AcpDiffDeleteText",
            priority = 110,
          })
        end
        if eb > p then
          local col = #a_indent + 2 + p
          vim.api.nvim_buf_set_extmark(buf, ns, start + add_start + k - 1, col, {
            end_col = #a_indent + 2 + eb,
            hl_group = "AcpDiffAddText",
            priority = 110,
          })
        end
      end
    end
    if i == del_start then
      i = i + 1 -- neither a - nor a + line: step past it
    end
  end
end

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
    elseif l:match("^%s*⋯%s*$") then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = "AcpDiffSep", priority = 95 })
    elseif kind == "plan" and l:match("^%s*◐") then
      -- The in-progress step stands out from the dimmed rest of the plan.
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = "AcpPlanActive", priority = 95 })
    elseif hl then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = hl, priority = 90 })
    end
  end
  if kind == "tool" then
    apply_intraline_hl(buf, start, lines)
  end
end

---Render a transcript entry appended at the end of the buffer.
---@param thread Thread
---@param buf integer
---@param entry TranscriptEntry
local function push_render(thread, buf, entry)
  local s = st(thread)
  local icons = require("acp.config").options.ui.icons
  local lines = entry_lines(icons, entry, is_collapsed(s, entry.kind, #s.ranges + 1))
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
  update_pad(buf)
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
  local lines = entry_lines(icons, entry, is_collapsed(s, entry.kind, index))
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
  update_pad(buf)
end

---@type table<integer, integer> win -> last snapped line (for direction)
local last_pos = {}

---Blank lines are separators, not content: keep the cursor on content lines,
---snapping in the direction it was moving (same feel as the sidebar).
local function snap()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local pos = vim.api.nvim_win_get_cursor(win)
  local lnum = pos[1]
  local function blank(l)
    local text = vim.api.nvim_buf_get_lines(buf, l - 1, l, false)[1]
    return text == nil or text == ""
  end
  if not blank(lnum) then
    last_pos[win] = lnum
    return
  end
  local prev = last_pos[win]
  local down = prev ~= nil and lnum > prev
  local total = vim.api.nvim_buf_line_count(buf)
  local step = down and 1 or -1
  local target
  for l = lnum + step, down and total or 1, step do
    if not blank(l) then
      target = l
      break
    end
  end
  if not target then -- nothing further that way: search back the other way
    for l = lnum - step, down and 1 or total, -step do
      if not blank(l) then
        target = l
        break
      end
    end
  end
  if target then
    local text = vim.api.nvim_buf_get_lines(buf, target - 1, target, false)[1] or ""
    pcall(vim.api.nvim_win_set_cursor, win, { target, math.min(pos[2], math.max(#text - 1, 0)) })
    last_pos[win] = target
  end
end

---Stick-to-bottom scrolling: a window follows the stream only while its
---cursor sits at the (previous) bottom. Scrolling up detaches it; sending a
---message (force) or pressing G re-attaches it.
---@param thread Thread
---@param buf integer
---@param force boolean|nil scroll every window regardless of position
local function autoscroll(thread, buf, force)
  local s = st(thread)
  local last = vim.api.nvim_buf_line_count(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
    if ok and (force or cursor[1] >= s.prev_count) then
      pcall(vim.api.nvim_win_set_cursor, win, { last, 0 })
    end
  end
  s.prev_count = last
end

---@param thread Thread
---@return integer bufnr
function M.ensure_buf(thread)
  if thread.chat_buf and vim.api.nvim_buf_is_valid(thread.chat_buf) then
    return thread.chat_buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  -- Slug last: path-shortening statuslines keep the final component, so
  -- the buffer displays as the thread name instead of a truncated UUID.
  local name = "acp://chat/" .. thread.slug
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
  map("gq", function()
    require("acp.agent.session").get(thread):edit_queue()
  end, "Edit queued prompts")
  map("gf", function()
    local session = require("acp.agent.session").get(thread)
    thread.follow = not session:follow_enabled()
    vim.notify("acp: follow mode " .. (thread.follow and "on" or "off"))
  end, "Toggle follow mode")
  map("<CR>", function()
    M.toggle_at_cursor(thread)
  end, "Expand/collapse entry")
  map("gd", function()
    M.goto_at_cursor(thread)
  end, "Go to the entry's code location")

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    desc = "Keep the cursor on content lines",
    callback = snap,
  })

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

---Transcript index of the entry under the cursor (chat window).
---@param thread Thread
---@return integer|nil
local function entry_at_cursor(thread)
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  for index, range in ipairs(st(thread).ranges) do
    if lnum >= range.start and lnum < range.start + range.count then
      return index
    end
  end
end

---Toggle collapse of the entry under the cursor (chat window).
---@param thread Thread
function M.toggle_at_cursor(thread)
  local index = entry_at_cursor(thread)
  if index then
    M.toggle_entry(thread, index)
    pcall(vim.api.nvim_win_set_cursor, 0, { st(thread).ranges[index].start + 2, 0 })
  end
end

---Jump to the code location of the tool call under the cursor (gd).
---@param thread Thread
function M.goto_at_cursor(thread)
  local index = entry_at_cursor(thread)
  local entry = index and thread.transcript[index]
  local loc = entry and entry.loc
  if not loc then
    vim.notify("acp: no code location on this entry", vim.log.levels.INFO)
    return
  end
  local win = require("acp.ui.workspace").reveal(thread, loc.path, loc.line)
  if win then
    vim.api.nvim_set_current_win(win)
  end
end

---Record the code location of the entry registered under `id`, so gd can
---jump to it (persisted with the transcript).
---@param thread Thread
---@param id string
---@param loc {path: string, line: integer|nil}|nil
function M.set_loc(thread, id, loc)
  if not loc or not loc.path then
    return
  end
  local index = st(thread).by_id[id]
  local entry = index and thread.transcript[index]
  if entry then
    entry.loc = { path = loc.path, line = loc.line }
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
---@param tool_kind string|nil ACP tool kind (read/edit/execute/...) for icons
function M.append(thread, kind, text, id, tool_kind)
  local entry = { kind = kind, text = text, id = id, tool = tool_kind }
  table.insert(thread.transcript, entry)
  local buf = M.ensure_buf(thread)
  local s = st(thread)
  -- ensure_buf may have just replayed the full transcript (including this entry)
  if #s.ranges < #thread.transcript then
    push_render(thread, buf, entry)
  end
  s.open = false
  -- Sending a message re-attaches every window to the bottom.
  autoscroll(thread, buf, kind == "user")
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
  autoscroll(thread, buf)
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
  autoscroll(thread, M.ensure_buf(thread))
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
  autoscroll(thread, buf, true)
end

return M
