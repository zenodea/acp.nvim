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
  eq({ chat = true, input = true, sidebar = true }, roles, "ui windows")
  eq(1, code_wins, "one code window")
  H.wait_for(function()
    return thread.session and thread.session.ready
  end, "handshake")
  eq("idle", thread.status)
end, { wait_ready = false })

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
