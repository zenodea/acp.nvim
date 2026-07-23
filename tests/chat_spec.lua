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

function T.toggle_expands_collapsed_tool_entry()
  local thread, buf = open_chat()
  local before = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(0, { 8, 0 })
  chat.toggle_at_cursor(thread)
  eq(before + 1, vim.api.nvim_buf_line_count(buf), "tool body revealed")
end

return T
