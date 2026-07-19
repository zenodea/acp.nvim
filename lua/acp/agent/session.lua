local rpc_mod = require("acp.agent.rpc")
local events = require("acp.agent.events")

---@class Session
---@field thread Thread
---@field rpc Rpc|nil
---@field ready boolean initialize + session/new (or load) completed
---@field starting boolean handshake in flight
---@field busy boolean a session/prompt turn is in flight
---@field queue string[] prompts waiting for the current turn
---@field start_waiters fun(ok: boolean)[] callbacks waiting on the handshake
---@field caps table agentCapabilities from initialize
---@field pending_permission {respond: fun(result: any, err: any), options: table[], title: string}|nil
---@field tool_calls table<string, table> live tool-call state by toolCallId
---@field last_assistant_text string
---@field loading boolean session/load replay in flight (updates ignored)
local Session = {}
Session.__index = Session

local M = {}

---@param thread Thread
---@return Session
function M.get(thread)
  if not thread.session then
    thread.session = setmetatable({
      thread = thread,
      rpc = nil,
      ready = false,
      starting = false,
      busy = false,
      queue = {},
      start_waiters = {},
      caps = {},
      pending_permission = nil,
      tool_calls = {},
      last_assistant_text = "",
      loading = false,
    }, Session)
  end
  return thread.session
end

local function chat()
  return require("acp.ui.chat")
end

---@return {cmd: string[], env: table|nil}|nil def, string|nil err
function Session:agent_def()
  local cfg = require("acp.config").options
  local name = self.thread.agent or cfg.default_agent
  local def = cfg.agents[name]
  if not def or type(def.cmd) ~= "table" then
    return nil, "no ACP agent configured under '" .. tostring(name) .. "'"
  end
  return def, nil
end

---@param ok boolean
function Session:finish_start(ok)
  self.starting = false
  self.ready = ok
  local waiters = self.start_waiters
  self.start_waiters = {}
  for _, cb in ipairs(waiters) do
    pcall(cb, ok)
  end
end

---@param err table|nil
---@param context string
function Session:fail_start(err, context)
  local msg = context .. ": " .. ((err and err.message) or "unknown error")
  if self.stderr_tail and self.stderr_tail ~= "" then
    msg = msg .. "\n" .. self.stderr_tail
  end
  chat().append(self.thread, "error", msg)
  self.thread:set_status("error", context)
  if self.rpc then
    self.rpc:kill()
    self.rpc = nil
  end
  self:finish_start(false)
end

---Create (or load) the ACP session after initialize.
function Session:open_session()
  local params = {
    cwd = self.thread.cwd,
    mcpServers = require("acp.config").options.mcp_servers or {},
  }
  if self.thread.session_id and self.caps.loadSession then
    self.loading = true
    -- The load replay becomes the transcript (it is the agent's source of
    -- truth and may include turns made outside this plugin). Keep a backup
    -- in case the load fails.
    local backup = self.thread.transcript
    self.thread.transcript = {}
    require("acp.ui.chat").replay(self.thread)
    local load_params = vim.tbl_extend("force", params, { sessionId = self.thread.session_id })
    self.rpc:request("session/load", load_params, function(result, err)
      self.loading = false
      chat().close_stream(self.thread)
      if err then
        -- Stale session on the agent side: fall back to a fresh one.
        self.thread.transcript = backup
        require("acp.ui.chat").replay(self.thread)
        self.thread.session_id = nil
        self:open_session()
        return
      end
      if result and result.modes then
        self:set_modes(result.modes)
      end
      require("acp.persist.store").save_debounced()
      self:finish_start(true)
    end)
    return
  end
  self.rpc:request("session/new", params, function(result, err)
    if err or not result or not result.sessionId then
      -- Offer the agent's auth methods once, then retry.
      if not self.auth_attempted and #(self.auth_methods or {}) > 0 then
        self:try_authenticate(err)
        return
      end
      self:fail_start(err, "session/new failed (is the agent authenticated?)")
      return
    end
    if self.thread.session_id then
      chat().append(self.thread, "meta", "(agent does not support resume — starting a fresh session)")
    end
    self.thread.session_id = result.sessionId
    self:set_modes(result.modes)
    require("acp.core.registry").emit("state")
    self:finish_start(true)
  end)
end

---Run the ACP authenticate flow: pick one of the agent's advertised auth
---methods, call `authenticate`, then retry opening the session.
---@param orig_err table|nil the session/new error that triggered this
function Session:try_authenticate(orig_err)
  self.auth_attempted = true
  local methods = self.auth_methods
  chat().append(
    self.thread,
    "meta",
    "(authentication required" .. ((orig_err and orig_err.message) and (": " .. orig_err.message) or "") .. ")"
  )
  local labels = {}
  for _, m in ipairs(methods) do
    labels[#labels + 1] = (m.name or m.id)
      .. ((m.description and m.description ~= "") and (" — " .. m.description) or "")
  end
  vim.ui.select(labels, { prompt = "Authenticate with:" }, function(_, idx)
    if not idx then
      self:fail_start(orig_err, "authentication cancelled")
      return
    end
    self.rpc:request("authenticate", { methodId = methods[idx].id }, function(_, aerr)
      if aerr then
        self:fail_start(aerr, "authentication failed")
        return
      end
      chat().append(self.thread, "meta", "(authenticated via " .. (methods[idx].name or methods[idx].id) .. ")")
      self:open_session()
    end)
  end)
end

---@param modes {currentModeId: string, availableModes: table[]}|nil
function Session:set_modes(modes)
  self.modes = modes
  require("acp.ui.workspace").update_winbar(self.thread)
end

---@param mode_id string|nil
---@return table|nil mode
function Session:find_mode(mode_id)
  for _, mode in ipairs((self.modes and self.modes.availableModes) or {}) do
    if mode.id == mode_id then
      return mode
    end
  end
end

---@param mode_id string
function Session:set_mode(mode_id)
  if not self.rpc or not self.rpc:alive() then
    return
  end
  self.rpc:request("session/set_mode", { sessionId = self.thread.session_id, modeId = mode_id }, function(_, err)
    if err then
      chat().append(self.thread, "error", "set mode failed: " .. (err.message or "?"))
      return
    end
    if self.modes then
      self.modes.currentModeId = mode_id
    end
    require("acp.ui.workspace").update_winbar(self.thread)
  end)
end

---Pick a session mode via vim.ui.select.
function Session:select_mode()
  local available = (self.modes and self.modes.availableModes) or {}
  if #available == 0 then
    vim.notify("acp: this agent exposes no session modes", vim.log.levels.INFO)
    return
  end
  local labels = {}
  for _, mode in ipairs(available) do
    local current = self.modes.currentModeId == mode.id and " (current)" or ""
    table.insert(labels, (mode.name or mode.id) .. current)
  end
  vim.ui.select(labels, { prompt = "Session mode:" }, function(_, idx)
    if idx then
      self:set_mode(available[idx].id)
    end
  end)
end

---@param cb fun(ok: boolean)
function Session:ensure_started(cb)
  if self.ready and self.rpc and self.rpc:alive() then
    cb(true)
    return
  end
  table.insert(self.start_waiters, cb)
  if self.starting then
    return
  end
  self.starting = true
  self.ready = false

  local def, err = self:agent_def()
  if not def then
    self:fail_start({ message = err }, "agent config")
    return
  end

  -- Guard every handler against events from a stale (killed/replaced)
  -- process: its async on_exit must not clobber a newer spawn's state.
  local rpc
  local function live()
    return self.rpc == rpc
  end
  local spawn_err
  rpc, spawn_err = rpc_mod.spawn({
    args = def.cmd,
    cwd = self.thread.cwd,
    env = def.env,
    handlers = {
      on_request = function(method, params, respond)
        if live() then
          self:on_request(method, params, respond)
        else
          respond(nil, { code = -32603, message = "stale session" })
        end
      end,
      on_notification = function(method, params)
        if live() then
          self:on_notification(method, params)
        end
      end,
      on_stderr = function(text)
        if live() then
          self.stderr_tail = text
        end
      end,
      on_exit = function(code)
        if live() then
          self:on_exit(code)
        end
      end,
    },
  })
  if not rpc then
    self:fail_start({ message = spawn_err }, "spawn failed")
    return
  end
  self.rpc = rpc

  self.rpc:request("initialize", {
    protocolVersion = 1,
    clientCapabilities = {
      fs = { readTextFile = true, writeTextFile = true },
      terminal = true,
    },
  }, function(result, ierr)
    if ierr or not result then
      self:fail_start(ierr, "initialize failed")
      return
    end
    self.caps = result.agentCapabilities or {}
    self.auth_methods = result.authMethods or {}
    self.auth_attempted = false
    self:open_session()
  end)
end

---@param text string
function Session:send(text)
  table.insert(self.queue, text)
  if self.busy then
    chat().append(self.thread, "meta", "(queued — will send when the current turn finishes)")
    return
  end
  self:ensure_started(function(ok)
    if not ok then
      self.queue = {}
      return
    end
    self:flush_queue()
  end)
end

---Send the next queued prompt if no turn is in flight.
function Session:flush_queue()
  if self.busy then
    return
  end
  local text = table.remove(self.queue, 1)
  if text then
    self:prompt(text)
  end
end

---@param text string
function Session:prompt(text)
  chat().append(self.thread, "user", text)
  self.busy = true
  self.turn_started = os.time()
  self.last_assistant_text = ""
  self.thread:set_status("working")
  local prompt_caps = (self.caps and self.caps.promptCapabilities) or {}
  local blocks = require("acp.context").to_blocks(text, prompt_caps.embeddedContext == true)
  self.rpc:request("session/prompt", {
    sessionId = self.thread.session_id,
    prompt = blocks,
  }, function(result, err)
    self:on_turn_end(result, err)
  end)
end

---@param result {stopReason: string}|nil
---@param err table|nil
function Session:on_turn_end(result, err)
  self.busy = false
  self:cancel_pending_permission()
  chat().close_stream(self.thread)
  local cfg = require("acp.config").options

  if err then
    chat().append(self.thread, "error", err.message or "turn failed")
    self.thread:set_status("error", "turn failed")
    return
  end

  local stop = (result and result.stopReason) or "end_turn"
  if cfg.ui.show_result_meta then
    local label = ({ cancelled = "interrupted", refusal = "refused" })[stop] or "done"
    local dur = self.turn_started and (" · " .. (os.time() - self.turn_started) .. "s") or ""
    chat().append(self.thread, "meta", "── " .. label .. dur)
  end

  if stop == "refusal" then
    self.thread:set_status("attention", "agent refused")
  elseif stop == "cancelled" then
    self.thread:set_status("idle")
  else
    -- Heuristic: a turn whose final line ends in "?" is a question for you.
    local lines = vim.split(vim.trim(self.last_assistant_text), "\n")
    local last = vim.trim(lines[#lines] or "")
    if last:sub(-1) == "?" then
      self.thread:set_status("attention", "asked a question")
    else
      self.thread:set_status("idle")
    end
  end

  if #self.queue > 0 then
    vim.defer_fn(function()
      self:flush_queue()
    end, 50)
  else
    self:schedule_reap()
  end
end

---Answer an outstanding permission request with "cancelled" (the spec
---requires every session/request_permission to be answered) and drop its
---keymaps.
function Session:cancel_pending_permission()
  local pending = self.pending_permission
  if not pending then
    return
  end
  self.pending_permission = nil
  if pending.clear then
    pcall(pending.clear)
  end
  pcall(pending.respond, { outcome = { outcome = "cancelled" } })
end

function Session:interrupt()
  if self.busy and self.rpc and self.rpc:alive() then
    self:cancel_pending_permission()
    self.rpc:notify("session/cancel", { sessionId = self.thread.session_id })
  end
end

---@param option_id string|nil nil cancels the request
function Session:answer_permission(option_id)
  local pending = self.pending_permission
  if not pending then
    return
  end
  self.pending_permission = nil
  if option_id then
    pending.respond({ outcome = { outcome = "selected", optionId = option_id } })
    local chosen
    for _, o in ipairs(pending.options) do
      if o.optionId == option_id then
        chosen = o.name or o.kind
      end
    end
    chat().append(self.thread, "meta", "→ " .. (chosen or option_id))
  else
    pending.respond({ outcome = { outcome = "cancelled" } })
    chat().append(self.thread, "meta", "→ dismissed")
  end
  if self.busy then
    self.thread:set_status("working")
  end
end

---@param method string
---@param params any
---@param respond fun(result: any, err: table|nil)
function Session:on_request(method, params, respond)
  if method == "session/request_permission" then
    local tool_call = params.toolCall or {}
    self.pending_permission = {
      respond = respond,
      options = params.options or {},
      title = tool_call.title or tool_call.kind or "tool",
    }
    require("acp.ui.permission").show(self.thread, self.pending_permission)
    self.thread:set_status("attention", "permission: " .. self.pending_permission.title)
  elseif method == "fs/read_text_file" then
    local content, err = require("acp.agent.fs").read_text_file(params)
    if content then
      respond({ content = content })
    else
      respond(nil, { code = -32603, message = err })
    end
  elseif method == "fs/write_text_file" then
    local ok, err = require("acp.agent.fs").write_text_file(params)
    if ok then
      respond(nil)
    else
      respond(nil, { code = -32603, message = err })
    end
  elseif method == "terminal/create" then
    local terminal = require("acp.agent.terminal")
    local id, err = terminal.create(params, self.thread.cwd, function()
      self:refresh_terminal_tools()
    end)
    if id then
      respond({ terminalId = id })
    else
      respond(nil, { code = -32603, message = err })
    end
  elseif method == "terminal/output" then
    local result = require("acp.agent.terminal").output(params.terminalId)
    if result then
      respond(result)
    else
      respond(nil, { code = -32602, message = "unknown terminal: " .. tostring(params.terminalId) })
    end
  elseif method == "terminal/wait_for_exit" then
    local known = require("acp.agent.terminal").wait_for_exit(params.terminalId, function(exit)
      respond(exit)
    end)
    if not known then
      respond(nil, { code = -32602, message = "unknown terminal: " .. tostring(params.terminalId) })
    end
  elseif method == "terminal/kill" then
    require("acp.agent.terminal").kill(params.terminalId)
    respond(nil)
  elseif method == "terminal/release" then
    require("acp.agent.terminal").release(params.terminalId)
    respond(nil)
  else
    respond(nil, { code = -32601, message = "method not supported: " .. method })
  end
end

---Re-render every tool call embedding a terminal (new output arrived).
function Session:refresh_terminal_tools()
  for id, call in pairs(self.tool_calls) do
    for _, item in ipairs(call.content or {}) do
      if item.type == "terminal" then
        require("acp.ui.chat").update_by_id(self.thread, id, events.tool_text(call))
        break
      end
    end
  end
end

---@param method string
---@param params any
function Session:on_notification(method, params)
  if method ~= "session/update" or type(params) ~= "table" then
    return
  end
  if params.sessionId ~= self.thread.session_id then
    return
  end
  local u = params.update or {}
  local kind = u.sessionUpdate
  local cfg = require("acp.config").options.ui

  if kind == "user_message_chunk" then
    -- Only meaningful during session/load replay; live turns echo locally.
    if self.loading then
      local text = events.content_text(u.content)
      if text ~= "" then
        chat().stream(self.thread, "user", text)
      end
    end
  elseif kind == "agent_message_chunk" then
    local text = events.content_text(u.content)
    if text ~= "" then
      self.last_assistant_text = self.last_assistant_text .. text
      chat().stream(self.thread, "text", text)
    end
  elseif kind == "agent_thought_chunk" then
    if cfg.show_thinking then
      local text = events.content_text(u.content)
      if text ~= "" then
        chat().stream(self.thread, "thinking", text)
      end
    end
  elseif kind == "tool_call" then
    local id = u.toolCallId or tostring(#self.thread.transcript)
    self.tool_calls[id] = {
      title = u.title,
      kind = u.kind,
      status = u.status or "pending",
      content = u.content,
    }
    chat().append(self.thread, "tool", events.tool_text(self.tool_calls[id]), id)
  elseif kind == "tool_call_update" then
    local id = u.toolCallId
    if id then
      local call = self.tool_calls[id] or {}
      for k, v in pairs(u) do
        if k ~= "sessionUpdate" and k ~= "toolCallId" then
          call[k] = v
        end
      end
      self.tool_calls[id] = call
      local text = events.tool_text(call)
      if not chat().update_by_id(self.thread, id, text) then
        chat().append(self.thread, "tool", text, id)
      end
    end
  elseif kind == "plan" then
    local text = events.plan_text(u.entries)
    if not chat().update_by_id(self.thread, "plan", text) then
      chat().append(self.thread, "plan", text, "plan")
    end
  elseif kind == "available_commands_update" then
    self.commands = u.availableCommands or {}
  elseif kind == "current_mode_update" then
    if self.modes then
      self.modes.currentModeId = u.currentModeId
    else
      self.modes = { currentModeId = u.currentModeId, availableModes = {} }
    end
    local mode = self:find_mode(u.currentModeId)
    chat().append(self.thread, "meta", "(mode: " .. ((mode and mode.name) or u.currentModeId) .. ")")
    require("acp.ui.workspace").update_winbar(self.thread)
  end
end

---@param code integer
function Session:on_exit(code)
  self.rpc = nil
  self.ready = false
  local was_busy = self.busy
  self.busy = false
  self:cancel_pending_permission()
  self.tool_calls = {}
  if self.starting then
    self:fail_start({ message = "agent exited during startup (code " .. code .. ")" }, "agent exited")
    return
  end
  if was_busy then
    local detail = "agent exited unexpectedly (code " .. code .. ")"
    if self.stderr_tail and self.stderr_tail ~= "" then
      detail = detail .. "\n" .. self.stderr_tail
    end
    chat().append(self.thread, "error", detail)
    self.thread:set_status("error", "agent exited")
  end
end

---Kill the process of an idle thread after the configured timeout — only for
---agents that can session/load the conversation back.
function Session:schedule_reap()
  local timeout = require("acp.config").options.idle_timeout
  if not timeout or timeout <= 0 or not self.caps.loadSession then
    return
  end
  local marker = os.time()
  self.reap_marker = marker
  vim.defer_fn(function()
    if self.reap_marker == marker and not self.busy and self.rpc and self.rpc:alive() then
      self.rpc:kill()
      self.rpc = nil
      self.ready = false
    end
  end, timeout * 1000)
end

function Session:stop()
  self:cancel_pending_permission()
  if self.rpc then
    self.rpc:kill()
    self.rpc = nil
  end
  self.ready = false
  self.starting = false
  self.busy = false
  self.queue = {}
  self.start_waiters = {}
end

---@param thread Thread
function M.stop(thread)
  if thread.session then
    thread.session:stop()
  end
end

return M
