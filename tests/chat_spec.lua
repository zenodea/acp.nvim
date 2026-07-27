local h = require("tests.helpers")
local eq = h.eq

h.stub("acp.persist.store", { save_debounced = function() end })
local chat = require("acp.ui.chat")

local n = 0

---A chat buffer in the current window with a few entries rendered.
local function open_chat()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.append(thread, "user", "hello world")
  chat.append(thread, "agent", "claude · opus")
  chat.append(thread, "tool", "Edit file.lua\nsome diff line", "tc1", "edit")
  vim.api.nvim_win_set_buf(0, buf)
  return thread, buf
end

local function move(cmd)
  vim.cmd("normal! " .. cmd)
  vim.cmd("doautocmd CursorMoved")
  return vim.api.nvim_win_get_cursor(0)[1]
end

local T = {}

function T.cursor_snaps_over_blank_lines()
  open_chat()
  -- Layout: 1 blank, 2 "❯ You", 3 blank, 4 body, 5 blank, 6 header, 7 blank, 8 tool
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.cmd("doautocmd CursorMoved")
  eq(4, move("j"), "down over blank")
  eq(6, move("j"))
  eq(8, move("j"))
  eq(6, move("k"), "up over blank")
  eq(4, move("k"))
end

function T.cursor_falls_forward_at_buffer_start()
  open_chat()
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  vim.cmd("doautocmd CursorMoved")
  eq(2, move("gg"), "gg lands on first content line")
end

function T.edit_tool_entry_uses_pencil_glyph()
  local thread = open_chat()
  local line = vim.api.nvim_buf_get_lines(thread.chat_buf, 7, 8, false)[1]
  -- U+F040 (nerd-font pencil) is EF 81 80; a lost glyph degrades to spaces.
  eq({ 0xEF, 0x81, 0x80 }, { line:byte(1, 3) }, "edit icon bytes")
end

function T.read_tool_entry_uses_magnifier_glyph()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.append(thread, "tool", "Read file.lua", "tc-read", "read")
  local line = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
  -- U+F002 (nerd-font magnifying glass) is EF 80 82.
  eq({ 0xEF, 0x80, 0x82 }, { line:byte(1, 3) }, "read icon bytes")
end

function T.intraline_diff_marks_changed_span_only()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.append(thread, "tool", "Edit x\n- local foo = 1\n+ local foo = 2", "tc", "edit")
  chat.toggle_entry(thread, 1) -- tools start collapsed; expand to render body
  local ns = vim.api.nvim_get_namespaces()["acp-chat"]
  local found = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local d = m[4]
    if d.hl_group == "AcpDiffDeleteText" or d.hl_group == "AcpDiffAddText" then
      table.insert(found, { d.hl_group, m[2], m[3], d.end_col })
    end
  end
  table.sort(found, function(a, b)
    return a[2] < b[2]
  end)
  -- Lines: 0 "", 1 icon+title, 2 "  - local foo = 1", 3 "  + local foo = 2".
  -- Only the "1"/"2" (col 16) differ; "local foo = " is common prefix.
  eq({
    { "AcpDiffDeleteText", 2, 16, 17 },
    { "AcpDiffAddText", 3, 16, 17 },
  }, found)
end

function T.gd_jumps_to_the_tool_call_location()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local tab = vim.api.nvim_get_current_tabpage()
  thread.tabpage = tab
  thread.tab_valid = function()
    return true
  end
  local target = vim.fn.tempname()
  vim.fn.writefile({ "one", "two", "three" }, target)
  local buf = chat.ensure_buf(thread)
  chat.append(thread, "tool", "Edit " .. target, "tc-loc", "edit")
  chat.set_loc(thread, "tc-loc", { path = target, line = 2 })
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  chat.goto_at_cursor(thread)
  local win = vim.api.nvim_get_current_win()
  local shown = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
  eq(vim.fn.resolve(target), vim.fn.resolve(shown), "code window shows the file")
  eq(2, vim.api.nvim_win_get_cursor(win)[1], "cursor on the edited line")
  vim.fn.delete(target)
end

function T.detail_float_shows_untruncated_tool_content()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  local big = {}
  for i = 1, 60 do
    big[i] = "line " .. i
  end
  -- The float renders straight from the live call, headed by its status.
  thread.session = {
    tool_calls = {
      tc = {
        title = "Write big.lua",
        kind = "edit",
        status = "completed",
        content = { { type = "diff", oldText = "", newText = table.concat(big, "\n") } },
      },
    },
    tool_call = function(self, id)
      return self.tool_calls[id]
    end,
  }
  chat.append(thread, "tool", "Write big.lua", "tc", "edit")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  chat.detail_at_cursor(thread)
  eq("editor", vim.api.nvim_win_get_config(0).relative, "detail opens in a float")
  local shown = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  eq("Write big.lua · completed", shown[1])
  local all = table.concat(shown, "\n")
  eq(true, all:find("+ line 60", 1, true) ~= nil, "last diff line present")
  eq(true, all:find("more lines", 1, true) == nil, "no truncation marker")
  vim.cmd("normal q")
  eq("", vim.api.nvim_win_get_config(0).relative, "q closes the float")
end

function T.detail_float_falls_back_to_entry_text()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.append(thread, "tool", "Old call\n+ persisted line", "gone", "edit")
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  chat.detail_at_cursor(thread) -- no session: renders the persisted text
  local all = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  eq(true, all:find("persisted line", 1, true) ~= nil)
  vim.cmd("normal q")
end

function T.plan_active_step_is_highlighted()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.append(thread, "plan", "Plan:\n  ✓ done\n  ◐ active\n  ○ todo", "plan")
  local ns = vim.api.nvim_get_namespaces()["acp-chat"]
  local active = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    if m[4].line_hl_group == "AcpPlanActive" then
      table.insert(active, m[2])
    end
  end
  -- Lines: 0 "", 1 "Plan:", 2 done, 3 active, 4 todo — only line 3 accented.
  eq({ 3 }, active)
end

---Spinner glyphs currently drawn in `buf`, by 0-based line.
---@param buf integer
local function spinners(buf)
  local ns = vim.api.nvim_get_namespaces()["acp-chat-spin"]
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    out[m[2]] = m[4].virt_text[1][1]
  end
  return out
end

---Drive the shared spinner timer one tick without waiting on real time.
local function tick()
  vim.wait(200, function()
    return false
  end)
end

function T.in_flight_tool_call_spins_in_place_of_its_icon()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.append(thread, "tool", "Edit file.lua", "tc", "edit")
  chat.set_status(thread, "tc", "in_progress")
  tick()
  -- Lines: 0 blank, 1 the title — the spinner overlays the icon at col 0.
  local ns = vim.api.nvim_get_namespaces()["acp-chat-spin"]
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  eq(1, #marks, "one spinner")
  eq({ 1, 0 }, { marks[1][2], marks[1][3] }, "on the title line, over the icon")
  eq("overlay", marks[1][4].virt_text_pos, "covers the icon instead of trailing the title")
  local text = marks[1][4].virt_text[1][1]
  eq(true, vim.tbl_contains(require("acp.util").spinner, vim.trim(text)), "a spinner frame: " .. text)
  -- Padded to the icon's width, so the title does not shift while spinning.
  local icons = require("acp.config").options.ui.icons
  eq(vim.fn.strdisplaywidth(icons.tool_kinds.edit), vim.fn.strdisplaywidth(text), "same width as the icon it covers")
  -- It animates rather than sitting on one frame.
  vim.wait(600, function()
    return spinners(buf)[1] ~= text
  end)
  eq(true, spinners(buf)[1] ~= text, "frame advanced")
end

function T.spinner_stops_when_the_call_completes()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.append(thread, "tool", "Edit file.lua", "tc", "edit")
  chat.set_status(thread, "tc", "in_progress")
  tick()
  eq(1, vim.tbl_count(spinners(buf)), "spinning while in flight")
  chat.set_status(thread, "tc", "completed")
  eq(0, vim.tbl_count(spinners(buf)), "glyph gone once completed")
  tick()
  eq(0, vim.tbl_count(spinners(buf)), "and it does not come back")
end

function T.stop_spinners_clears_calls_the_agent_left_hanging()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.append(thread, "tool", "Read a.lua", "t1", "read")
  chat.append(thread, "tool", "Read b.lua", "t2", "read")
  chat.set_status(thread, "t1", "in_progress")
  chat.set_status(thread, "t2", "pending")
  tick()
  eq(2, vim.tbl_count(spinners(buf)), "both in flight")
  chat.stop_spinners(thread)
  eq(0, vim.tbl_count(spinners(buf)))
end

function T.completed_tool_call_never_spins()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.append(thread, "tool", "Edit file.lua", "tc", "edit")
  chat.set_status(thread, "tc", "completed")
  chat.set_status(thread, "unknown-id", "in_progress") -- ignored, not a crash
  tick()
  eq(0, vim.tbl_count(spinners(buf)))
end

function T.a_streaming_thought_spins_under_a_thinking_header()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.stream(thread, "thinking", "weighing the options\nand the trade-offs")
  tick()
  -- Collapsed to its header, which says the thought is still coming.
  local shown = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(2, #shown, "blank separator + header")
  eq(true, shown[2]:find("thinking…", 1, true) ~= nil, "header: " .. shown[2])
  eq(true, shown[2]:find("▸ 2 more", 1, true) ~= nil, "hidden-line count: " .. shown[2])
  local spun = spinners(buf)
  eq(1, vim.tbl_count(spun), "spinning while the thought streams")
  eq(true, vim.tbl_contains(require("acp.util").spinner, vim.trim(spun[1] or "")), "a spinner frame")
  local icons = require("acp.config").options.ui.icons
  -- Covers the icon and its trailing space, so the header does not shift.
  eq(vim.fn.strdisplaywidth(icons.thinking .. " "), vim.fn.strdisplaywidth(spun[1]), "same width as the icon it covers")
end

function T.a_finished_thought_reports_how_long_it_took()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.stream(thread, "thinking", "weighing the options")
  thread.transcript[1].started = os.time() - 12
  tick()
  -- Anything else landing in the transcript ends the thought.
  chat.append(thread, "text", "here is the answer")
  eq(0, vim.tbl_count(spinners(buf)), "spinner gone once the agent moves on")
  local elapsed = thread.transcript[1].elapsed
  eq(true, elapsed >= 12, "duration recorded on the entry: " .. tostring(elapsed))
  local header = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
  eq(true, header:find("thought for " .. elapsed .. "s", 1, true) ~= nil, "header: " .. header)
end

function T.expanding_a_thought_shows_the_whole_text()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  chat.stream(thread, "thinking", "first thought\nsecond thought")
  chat.close_stream(thread)
  chat.toggle_entry(thread, 1)
  local shown = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  eq(4, #shown, "blank + header + both thought lines")
  eq("  first thought", shown[3])
  eq("  second thought", shown[4])
  eq(nil, shown[2]:find("▸", 1, true), "expanded: no more-marker")
end

function T.expanding_a_tool_call_shows_the_whole_diff()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local buf = chat.ensure_buf(thread)
  local big = {}
  for i = 1, 300 do
    big[i] = "line " .. i
  end
  local events = require("acp.agent.events")
  local call = {
    title = "Write big.lua",
    kind = "edit",
    status = "completed",
    content = { { type = "diff", oldText = "", newText = table.concat(big, "\n") } },
  }
  chat.append(thread, "tool", events.tool_text(call), "tc", "edit")
  -- Collapsed by default: one title line carrying the hidden-line count.
  eq(2, vim.api.nvim_buf_line_count(buf), "collapsed to the title")
  eq(true, vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]:find("▸ 300 more", 1, true) ~= nil)

  chat.toggle_entry(thread, 1)
  local shown = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Blank separator + title + all 300 diff lines, nothing elided.
  eq(302, #shown, "every diff line rendered")
  eq("  + line 300", shown[302])
  eq(nil, table.concat(shown, "\n"):find("more lines", 1, true), "no truncation marker")
end

function T.terminal_output_keeps_only_its_tail_inline()
  n = n + 1
  local thread = h.thread("chat-test-" .. n)
  local events = require("acp.agent.events")
  local terminal = require("acp.agent.terminal")
  local id = terminal.create(
    { command = "printf", args = { "a\\nb\\nc\\nd\\ne\\nf\\n" } },
    vim.fn.getcwd(),
    function() end
  )
  vim.wait(2000, function()
    return #terminal.render_lines(id, 100) >= 7
  end)
  require("acp.config").options.ui.terminal_max_lines = 3

  local lines = events.tool_content_lines({ { type = "terminal", terminalId = id } })
  -- Unbounded and still growing, so the inline view keeps the tail only.
  eq(true, #lines <= 5, "tail capped: " .. #lines .. " lines")
  eq(true, lines[1]:find("earlier lines", 1, true) ~= nil, "earlier-lines marker: " .. lines[1])
  -- The float lifts the cap.
  local full = events.tool_content_lines({ { type = "terminal", terminalId = id } }, true)
  eq(true, #full > #lines, "float shows more")
  eq(nil, table.concat(full, "\n"):find("earlier lines", 1, true), "nothing elided in the float")
  terminal.release(id)
  require("acp.config").setup({})
end

function T.toggle_expands_collapsed_tool_entry()
  local thread, buf = open_chat()
  local before = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(0, { 8, 0 })
  chat.toggle_at_cursor(thread)
  eq(before + 1, vim.api.nvim_buf_line_count(buf), "tool body revealed")
end

return T
