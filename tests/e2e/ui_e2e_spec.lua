local h = require("tests.helpers")
local eq = h.eq
local H = require("tests.e2e.harness")

local T = {}

T.handshake_and_workspace = H.test("greeting", function(thread)
  local roles = {}
  local code_wins = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(thread.tabpage)) do
    local role = vim.w[win].acp_ui
    if role then
      roles[role] = true
    elseif vim.api.nvim_win_get_config(win).relative == "" then
      code_wins = code_wins + 1
    end
  end
  eq({ chat = true, input = true, sidebar = true, details = true }, roles, "ui windows")
  eq(1, code_wins, "one code window")
  H.wait_for(function()
    return thread.session and thread.session.ready
  end, "handshake")
  eq("idle", thread.status)
end, { wait_ready = false })

T.ui_windows_refuse_foreign_buffers = H.test("greeting", function(thread)
  local foreign = vim.api.nvim_create_buf(true, false)
  for _, role in ipairs({ "sidebar", "chat", "input" }) do
    local win = H.win(thread, role)
    eq(true, vim.wo[win].winfixbuf, role .. " has winfixbuf")
    local before = vim.api.nvim_win_get_buf(win)
    local ok = pcall(vim.api.nvim_win_set_buf, win, foreign)
    eq(false, ok, role .. " rejects a foreign buffer")
    eq(before, vim.api.nvim_win_get_buf(win), role .. " keeps its buffer")
  end
  vim.api.nvim_buf_delete(foreign, { force = true })
end)

T.file_open_lands_in_the_code_window = H.test("greeting", function(thread)
  -- The contract window pickers rely on: exactly one usable window (normal
  -- empty buffer, no winfixbuf) — the [No Name] code window.
  local usable = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(thread.tabpage)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].buftype == "" and not vim.wo[win].winfixbuf then
      table.insert(usable, win)
    end
  end
  eq(1, #usable, "exactly one pickable window")
  eq("", vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(usable[1])), "it is the [No Name] window")
  -- Opening a file there works and leaves every plugin window untouched.
  local target = vim.fn.tempname()
  vim.fn.writefile({ "hello" }, target)
  vim.api.nvim_win_call(usable[1], function()
    vim.cmd.edit(target)
  end)
  eq(vim.fn.resolve(target), vim.fn.resolve(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(usable[1]))))
  for _, role in ipairs({ "sidebar", "chat", "input" }) do
    local buf = vim.api.nvim_win_get_buf(H.win(thread, role))
    eq(true, vim.api.nvim_buf_get_name(buf):find("acp://", 1, true) ~= nil, role .. " untouched")
  end
  vim.fn.delete(target)
end)

T.prompt_streams_to_chat = H.test("greeting", function(thread)
  H.send(thread, "hi")
  H.wait_done(thread)
  eq(true, H.chat_has(thread, "You"), "user header")
  eq(true, H.chat_has(thread, "hi"), "user text")
  H.wait_for(function()
    return H.chat_has(thread, "Hello world")
  end, "streamed chunks merged into one line")
  eq(true, H.chat_has(thread, "── done"), "turn meta")
  eq("idle", thread.status)
end)

T.permission_flow = H.test("permission", function(thread)
  H.send(thread, "edit something")
  H.wait_for(function()
    return thread.status == "attention" and thread.session.pending_permission ~= nil
  end, "permission requested")
  eq(true, H.chat_has(thread, "[y] Allow"), "permission options rendered")
  H.feed(H.win(thread, "chat"), "y")
  H.wait_for(function()
    return thread.session.pending_permission == nil
  end, "permission answered")
  H.wait_done(thread)
  eq(true, H.chat_has(thread, "Done."), "turn continued after allow")
  eq("idle", thread.status)
end)

-- A thought is a first-class action in the transcript: collapsed to a header
-- while it streams, settled (and expandable) once the agent moves on.
T.thinking_collapses_to_a_header_and_expands = H.test("thinking", function(thread)
  H.send(thread, "think about it")
  H.wait_done(thread)
  local header
  for _, l in ipairs(H.chat_lines(thread)) do
    if l:find("thought", 1, true) then
      header = l
    end
  end
  eq(true, header ~= nil, "settled thought header: " .. table.concat(H.chat_lines(thread), "|"))
  eq(true, header:find("▸ 2 more", 1, true) ~= nil, "both thought lines folded away: " .. header)
  eq(false, H.chat_has(thread, "weighing the options"), "thought text hidden while collapsed")

  -- <CR> on the header unfolds the thought itself.
  local win = H.win(thread, "chat")
  for i, l in ipairs(H.chat_lines(thread)) do
    if l == header then
      vim.api.nvim_win_set_cursor(win, { i, 0 })
      break
    end
  end
  H.feed(win, "\r")
  eq(true, H.chat_has(thread, "weighing the options"), "expanded thought text")
  eq(true, H.chat_has(thread, "and the trade-offs"), "every chunk merged into one thought")
end)

T.tool_call_update_renders_in_place = H.test("tool_diff", function(thread)
  H.send(thread, "edit")
  H.wait_done(thread)
  local titles = 0
  for _, l in ipairs(H.chat_lines(thread)) do
    if l:find("Edit foo.lua", 1, true) then
      titles = titles + 1
    end
  end
  eq(1, titles, "tool_call + update render as one entry")
  local ns = vim.api.nvim_get_namespaces()["acp-chat"]
  local marks = vim.api.nvim_buf_get_extmarks(thread.chat_buf, ns, 0, -1, {})
  eq(true, #marks > 0, "chat extmarks present")
end)

T.context_counter_reaches_the_winbar = H.test("reports_usage", function(thread)
  -- Rendered, not raw: the raw winbar always carries the title chip's
  -- highlight items, and those are `%` too.
  local win = H.win(thread, "chat")
  local before = vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true }).str
  eq(nil, before:find("%%"), "no counter before the agent reports one")
  H.send(thread, "hi")
  H.wait_done(thread)
  eq({ used = 42000, size = 200000 }, thread.usage, "usage recorded on the thread")
  -- 42k of 200k is 21%; the winbar stores it %-escaped for statusline syntax.
  local winbar = vim.wo[win].winbar
  eq(true, winbar:find("◔ 21%%", 1, true) ~= nil, "winbar: " .. winbar)
end)

-- 'winbar' takes statusline syntax, so a bare % in a name (or in the context
-- counter) used to raise E539 and leave the winbar unset.
T.percent_in_a_thread_name_survives_the_winbar = H.test("greeting", function(thread)
  thread.usage = { used = 1, size = 2 }
  thread.name = "50% done"
  require("acp.ui.workspace").update_winbar(thread)
  local win = H.win(thread, "chat")
  local rendered = vim.api.nvim_eval_statusline(vim.wo[win].winbar, { winid = win, use_winbar = true }).str
  eq(true, rendered:find("50% done", 1, true) ~= nil, "rendered: " .. rendered)
  eq(true, rendered:find("◑ 50%", 1, true) ~= nil, "rendered: " .. rendered)
end)

T.plan_reaches_winbar_and_panel = H.test("planning", function(thread)
  H.send(thread, "plan it")
  H.wait_done(thread)
  eq(true, H.chat_has(thread, "◐ Write the parser"), "plan in the transcript")
  eq(true, vim.wo[H.win(thread, "chat")].winbar:find("▤ 1/3", 1, true) ~= nil, "step count in the winbar")
  -- gp opens the latest plan wherever you are in the conversation.
  H.feed(H.win(thread, "chat"), "gp")
  eq("editor", vim.api.nvim_win_get_config(0).relative, "plan panel is a float")
  eq({ " ✓ Read the spec", " ◐ Write the parser", " ○ Add tests" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  H.feed(0, "q")
end)

T.subagent_spawns_are_tracked_and_listed = H.test("delegating", function(thread)
  H.send(thread, "delegate it")
  H.wait_done(thread)
  -- Spawns get ◇ in the transcript instead of the generic tool glyph; the
  -- plain edit call is left alone and never tracked.
  eq(true, H.chat_has(thread, "◇ Task: audit the parser"), "first spawn iconed")
  eq(true, H.chat_has(thread, "◇ Explore the loader"), "second spawn iconed")
  eq(2, #thread.subagents, "the ordinary tool call was not tracked")
  -- One of the two is still going, so the winbar keeps its count.
  eq(true, vim.wo[H.win(thread, "chat")].winbar:find("◇ 1", 1, true) ~= nil, "running count in the winbar")

  H.feed(H.win(thread, "chat"), "gs")
  eq("editor", vim.api.nvim_win_get_config(0).relative, "subagent panel is a float")
  local rows = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  eq(true, rows[1]:find("✓ Task: audit the parser", 1, true) ~= nil, "row 1: " .. rows[1])
  eq(true, rows[1]:find("done ·", 1, true) ~= nil, "row 1: " .. rows[1])
  eq(true, rows[2]:find("◐ Explore the loader", 1, true) ~= nil, "row 2: " .. rows[2])
  eq(true, rows[2]:find("running ·", 1, true) ~= nil, "row 2: " .. rows[2])
  H.feed(0, "q")
end)

T.agent_edits_land_in_the_marked_window = H.test("follow_edit", function(thread)
  -- Split the code area, then mark the original half as the follow target.
  local marked = H.code_win(thread)
  vim.api.nvim_set_current_win(marked)
  vim.cmd("split")
  local other = vim.api.nvim_get_current_win()
  local untouched = vim.api.nvim_win_get_buf(other)
  vim.api.nvim_set_current_win(marked)

  require("acp").follow_here()
  eq(true, thread.follow, "marking turned follow on")
  eq(true, vim.wo[marked].winbar:find("following", 1, true) ~= nil, "winbar: " .. vim.wo[marked].winbar)

  H.send(thread, "edit the readme")
  H.wait_done(thread)

  local shown = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(marked))
  eq(true, shown:find("README.md", 1, true) ~= nil, "marked window shows the edited file: " .. shown)
  eq(3, vim.api.nvim_win_get_cursor(marked)[1], "cursor on the reported line")
  eq(untouched, vim.api.nvim_win_get_buf(other), "the other code window kept its buffer")
end)

T.in_flight_tool_call_shows_a_spinner = H.test("slow_tool", function(thread)
  local ns = vim.api.nvim_get_namespaces()["acp-chat-spin"]
  local function glyphs()
    return vim.api.nvim_buf_get_extmarks(thread.chat_buf, ns, 0, -1, { details = true })
  end
  H.send(thread, "run it")
  H.wait_for(function()
    return #glyphs() > 0
  end, "spinner next to the in-flight tool call")
  local marks = glyphs()
  local row, text = marks[1][2], marks[1][4].virt_text[1][1]
  local title = vim.api.nvim_buf_get_lines(thread.chat_buf, row, row + 1, false)[1]
  eq(true, title:find("Run the suite", 1, true) ~= nil, "spinner sits on the title line: " .. title)
  eq(true, vim.tbl_contains(require("acp.util").spinner, vim.trim(text)), "a spinner frame: " .. text)

  -- Ending the turn stops it, even though the agent never marked the call done.
  thread.session:interrupt()
  H.wait_done(thread)
  eq(0, #glyphs(), "spinner cleared at turn end")
end)

T.interrupt_marks_turn_interrupted = H.test("cancel_me", function(thread)
  H.send(thread, "go")
  H.wait_for(function()
    return H.chat_has(thread, "working...")
  end, "turn started")
  thread.session:interrupt()
  H.wait_done(thread)
  eq(true, H.chat_has(thread, "── interrupted"), "interrupted meta")
  eq("idle", thread.status)
end)

-- One case per window: <Esc> in normal mode stops the turn from wherever
-- you happen to be sitting.
for _, role in ipairs({ "chat", "input" }) do
  T["esc_in_the_" .. role .. "_interrupts"] = H.test("cancel_me", function(thread)
    H.send(thread, "go")
    H.wait_for(function()
      return H.chat_has(thread, "working...")
    end, "turn started")
    H.feed(H.win(thread, role), "<Esc>")
    H.wait_done(thread)
    eq(true, H.chat_has(thread, "── interrupted"), "interrupted meta")
    eq("idle", thread.status)
  end)
end

T.esc_while_typing_only_leaves_insert_mode = H.test("cancel_me", function(thread)
  H.send(thread, "go")
  H.wait_for(function()
    return H.chat_has(thread, "working...")
  end, "turn started")
  local win = H.win(thread, "input")
  vim.api.nvim_set_current_win(win)
  -- Esc out of insert mode must not stop the agent mid-thought.
  H.feed(win, "ihalf a message<Esc>")
  eq("n", vim.api.nvim_get_mode().mode, "back in normal mode")
  eq(true, thread.session.busy, "turn still running")
  eq({ "half a message" }, vim.api.nvim_buf_get_lines(thread.input_buf, 0, -1, false), "text kept")
  thread.session:interrupt()
  H.wait_done(thread)
end)

T.queue_while_busy = H.test("permission", function(thread)
  H.send(thread, "first")
  H.wait_for(function()
    return thread.session.pending_permission ~= nil
  end, "agent blocked on permission")
  H.send(thread, "second")
  H.wait_for(function()
    return (vim.wo[H.win(thread, "input")].winbar or ""):find("1 queued", 1, true) ~= nil
  end, "queue indicator in winbar")
  eq(true, vim.wo[H.win(thread, "input")].winbar:find("⧗", 1, true) ~= nil, "glyph indicator")
  H.feed(H.win(thread, "chat"), "y")
  H.wait_for(function()
    return H.chat_has(thread, "Second turn.")
  end, "queued prompt flushed as second turn")
  H.wait_done(thread)
end)

T.agent_crash_mid_turn = H.test("crash_mid_turn", function(thread)
  H.send(thread, "boom")
  H.wait_for(function()
    return thread.status == "error"
  end, "error status after crash")
  -- The in-flight prompt fails when the channel drops, before on_exit runs.
  eq(true, H.chat_has(thread, "agent process exited"), "crash reported in chat")
  local sidebar = require("acp.ui.sidebar")
  local lines = table.concat(vim.api.nvim_buf_get_lines(sidebar.buf, 0, -1, false), "\n")
  eq(true, lines:find("✗", 1, true) ~= nil, "sidebar shows failed status")
end)

T.attention_when_agent_asks_a_question = H.test("question", function(thread)
  H.send(thread, "hi")
  H.wait_done(thread)
  eq("attention", thread.status)
  eq("asked a question", thread.status_detail)
end)

return T
