---A fake ACP agent for end-to-end tests, run as a subprocess via
---`nvim --clean -l fake_agent.lua <scenario>`. Speaks newline-delimited
---JSON-RPC on stdio and replays the named scenario from scenarios.lua.
---Fully synchronous — every message is a reaction to the editor, so test
---ordering is deterministic.

local here = vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
local scenarios = dofile(here .. "/scenarios.lua")
local scn = scenarios[_G.arg and _G.arg[1] or ""]
if not scn then
  io.stderr:write("fake_agent: unknown scenario " .. tostring(_G.arg and _G.arg[1]) .. "\n")
  os.exit(64)
end

---stdout to the editor is a pipe (fully buffered): always write + flush.
---Never print() — under -l it goes through nvim's message layer, not stdout.
---@param t table
local function send(t)
  t.jsonrpc = "2.0"
  io.stdout:write(vim.json.encode(t) .. "\n")
  io.stdout:flush()
end

---@return table
local function recv()
  local line = io.read("*l")
  if line == nil then
    os.exit(0) -- editor closed stdin
  end
  local ok, msg = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
  return ok and type(msg) == "table" and msg or {}
end

local function update(u)
  send({ method = "session/update", params = { sessionId = "s1", update = u } })
end

local next_id = 100
local nprompt = 0

---@param steps table[]
---@return string stopReason
local function play(steps)
  local stop = "end_turn"
  for _, step in ipairs(steps) do
    if step.chunk then
      update({ sessionUpdate = "agent_message_chunk", content = { type = "text", text = step.chunk } })
    elseif step.tool_call then
      local u = vim.tbl_extend("force", { sessionUpdate = "tool_call" }, step.tool_call)
      update(u)
    elseif step.tool_update then
      local u = vim.tbl_extend("force", { sessionUpdate = "tool_call_update" }, step.tool_update)
      update(u)
    elseif step.plan then
      update({ sessionUpdate = "plan", entries = step.plan })
    elseif step.permission then
      next_id = next_id + 1
      send({
        id = next_id,
        method = "session/request_permission",
        params = {
          sessionId = "s1",
          toolCall = { title = step.permission.title or "tool" },
          options = step.permission.options,
        },
      })
      local r
      repeat
        r = recv()
      until r.id == next_id or r.method == "session/cancel"
      local outcome = r.result and r.result.outcome
      if r.method == "session/cancel" or (outcome and outcome.outcome == "cancelled") then
        return "cancelled"
      end
    elseif step.wait_cancel then
      local r
      repeat
        r = recv()
      until r.method == "session/cancel"
      return "cancelled"
    elseif step.exit then
      io.stdout:flush()
      os.exit(step.exit)
    end
    if step.stop then
      stop = step.stop
    end
  end
  return stop
end

while true do
  local msg = recv()
  if msg.method == "initialize" then
    send({ id = msg.id, result = { protocolVersion = 1, agentCapabilities = scn.caps or {} } })
  elseif msg.method == "session/new" then
    send({ id = msg.id, result = { sessionId = "s1" } })
  elseif msg.method == "session/prompt" then
    nprompt = nprompt + 1
    local steps = scn.turns[math.min(nprompt, #scn.turns)]
    send({ id = msg.id, result = { stopReason = play(steps) } })
  elseif msg.id and msg.method then
    send({ id = msg.id, error = { code = -32601, message = "not supported: " .. msg.method } })
  end
  -- notifications outside a turn (e.g. a late session/cancel) are ignored
end
