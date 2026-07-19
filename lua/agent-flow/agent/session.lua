local process = require("agent-flow.agent.process")
local events = require("agent-flow.agent.events")

---@class Session
---@field thread Thread
---@field job integer|nil
---@field busy boolean
---@field queue string[] prompts waiting for the current turn to finish
---@field pending_permission {request_id: string, tool_name: string, input: table}|nil
---@field last_assistant_text string
---@field turn_started integer|nil
local Session = {}
Session.__index = Session

local M = {}

local req_counter = 0
local function next_request_id()
  req_counter = req_counter + 1
  return "req_nvim_" .. req_counter
end

---@param thread Thread
---@return Session
function M.get(thread)
  if not thread.session then
    thread.session = setmetatable({
      thread = thread,
      job = nil,
      busy = false,
      queue = {},
      pending_permission = nil,
      last_assistant_text = "",
      turn_started = nil,
    }, Session)
  end
  return thread.session
end

local function chat()
  return require("agent-flow.ui.chat")
end

function Session:build_args()
  local cfg = require("agent-flow.config").options.claude
  local args = {
    cfg.cmd,
    "-p",
    "--input-format",
    "stream-json",
    "--output-format",
    "stream-json",
    "--verbose",
  }
  if cfg.model then
    vim.list_extend(args, { "--model", cfg.model })
  end
  if self.thread.session_id then
    vim.list_extend(args, { "--resume", self.thread.session_id })
  end
  if cfg.permissions == "prompt" then
    -- Route can_use_tool through the stream-json control protocol so we can
    -- render allow/deny prompts in the chat panel.
    vim.list_extend(args, { "--permission-prompt-tool", "stdio" })
  elseif cfg.permissions then
    vim.list_extend(args, { "--permission-mode", cfg.permissions })
  end
  vim.list_extend(args, cfg.extra_args or {})
  return args
end

---@return boolean ok
function Session:ensure_started()
  if process.alive(self.job) then
    return true
  end
  local job, err = process.spawn({
    args = self:build_args(),
    cwd = self.thread.cwd,
    on_line = function(line)
      self:on_line(line)
    end,
    on_stderr = function(text)
      self.stderr_tail = text
    end,
    on_exit = function(code)
      self:on_exit(code)
    end,
  })
  if not job then
    chat().append(self.thread, "error", err or "failed to start claude")
    self.thread:set_status("error", "spawn failed")
    return false
  end
  self.job = job
  return true
end

---@param text string
function Session:send(text)
  if self.busy then
    table.insert(self.queue, text)
    chat().append(self.thread, "meta", "(queued — will send when the current turn finishes)")
    return
  end
  if not self:ensure_started() then
    return
  end
  chat().append(self.thread, "user", text)
  self.busy = true
  self.turn_started = os.time()
  self.last_assistant_text = ""
  self.thread:set_status("working")
  process.send(self.job, {
    type = "user",
    message = { role = "user", content = { { type = "text", text = text } } },
  })
end

function Session:interrupt()
  if not self.busy or not process.alive(self.job) then
    return
  end
  process.send(self.job, {
    type = "control_request",
    request_id = next_request_id(),
    request = { subtype = "interrupt" },
  })
  chat().append(self.thread, "meta", "(interrupt requested)")
end

---@param allow boolean
function Session:answer_permission(allow)
  local pending = self.pending_permission
  if not pending or not process.alive(self.job) then
    return
  end
  self.pending_permission = nil
  local response
  if allow then
    response = { behavior = "allow", updatedInput = pending.input }
  else
    response = { behavior = "deny", message = "Denied by user" }
  end
  process.send(self.job, {
    type = "control_response",
    response = { subtype = "success", request_id = pending.request_id, response = response },
  })
  chat().append(self.thread, "meta", (allow and "→ allowed " or "→ denied ") .. pending.tool_name)
  if self.busy then
    self.thread:set_status("working")
  end
end

---@param code integer
function Session:on_exit(code)
  self.job = nil
  self.pending_permission = nil
  if self.busy then
    self.busy = false
    local detail = "claude exited unexpectedly (code " .. code .. ")"
    if self.stderr_tail and self.stderr_tail ~= "" then
      detail = detail .. "\n" .. self.stderr_tail
    end
    chat().append(self.thread, "error", detail)
    self.thread:set_status("error", "process exited")
  end
end

---@param block table assistant message content block
function Session:on_content_block(block)
  local ui = require("agent-flow.config").options.ui
  if block.type == "text" and block.text and block.text ~= "" then
    self.last_assistant_text = block.text
    chat().append(self.thread, "text", block.text)
  elseif block.type == "tool_use" then
    chat().append(self.thread, "tool", events.tool_summary(block.name, block.input))
    if ui.show_diffs and (block.name == "Edit" or block.name == "MultiEdit" or block.name == "Write") then
      local diff = events.tool_diff(block.name, block.input)
      if #diff > 0 then
        chat().append(self.thread, "meta", table.concat(diff, "\n"))
      end
    end
  elseif block.type == "thinking" and ui.show_thinking then
    chat().append(self.thread, "thinking", "thinking…")
  end
end

---@param event table
function Session:on_result(event)
  self.busy = false
  local cfg = require("agent-flow.config").options

  if cfg.ui.show_result_meta then
    local parts = {}
    if event.total_cost_usd then
      table.insert(parts, string.format("$%.4f", event.total_cost_usd))
    end
    if self.turn_started then
      table.insert(parts, os.time() - self.turn_started .. "s")
    end
    local label = event.is_error and "turn failed" or "done"
    chat().append(self.thread, "meta", "── " .. label .. (#parts > 0 and " · " .. table.concat(parts, " · ") or ""))
  end

  if event.is_error then
    self.thread:set_status("error", event.subtype or "error")
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
    local text = table.remove(self.queue, 1)
    vim.defer_fn(function()
      self:send(text)
    end, 50)
  else
    self:schedule_reap()
  end
end

---@param event table
function Session:on_control_request(event)
  local request = event.request or {}
  if request.subtype == "can_use_tool" then
    self.pending_permission = {
      request_id = event.request_id,
      tool_name = request.tool_name or "tool",
      input = request.input or vim.empty_dict(),
    }
    require("agent-flow.ui.permission").show(self.thread, self.pending_permission)
    self.thread:set_status("attention", "permission: " .. self.pending_permission.tool_name)
  else
    -- Politely refuse control requests we don't implement (hooks, etc.).
    process.send(self.job, {
      type = "control_response",
      response = { subtype = "error", request_id = event.request_id, error = "unsupported by agent-flow.nvim" },
    })
  end
end

---@param line string
function Session:on_line(line)
  local event = events.decode(line)
  if not event then
    return
  end

  if event.type == "system" and event.subtype == "init" then
    if event.session_id then
      self.thread.session_id = event.session_id
      require("agent-flow.core.registry").emit("state")
    end
  elseif event.type == "assistant" then
    local message = event.message or {}
    for _, block in ipairs(message.content or {}) do
      self:on_content_block(block)
    end
  elseif event.type == "user" then
    -- Echoed tool results: only surface failures.
    local message = event.message or {}
    local content = message.content
    if type(content) == "table" then
      for _, block in ipairs(content) do
        if block.type == "tool_result" and block.is_error then
          local text = block.content
          if type(text) == "table" then
            local parts = {}
            for _, c in ipairs(text) do
              if c.type == "text" then
                table.insert(parts, c.text)
              end
            end
            text = table.concat(parts, "\n")
          end
          if type(text) == "string" and text ~= "" then
            chat().append(self.thread, "error", require("agent-flow.util").shorten(text, 200))
          end
        end
      end
    end
  elseif event.type == "result" then
    self:on_result(event)
  elseif event.type == "control_request" then
    self:on_control_request(event)
  elseif event.type == "control_cancel_request" then
    if self.pending_permission and self.pending_permission.request_id == event.request_id then
      self.pending_permission = nil
      chat().append(self.thread, "meta", "(permission request cancelled)")
      if self.busy then
        self.thread:set_status("working")
      end
    end
  end
  -- control_response (acks of our interrupts) and stream_event are ignored.
end

---Kill the process of an idle thread after the configured timeout; the
---conversation is resumable via --resume, so this only frees resources.
function Session:schedule_reap()
  local timeout = require("agent-flow.config").options.claude.idle_timeout
  if not timeout or timeout <= 0 then
    return
  end
  local marker = os.time()
  self.reap_marker = marker
  vim.defer_fn(function()
    if self.reap_marker == marker and not self.busy and process.alive(self.job) then
      process.kill(self.job)
      self.job = nil
    end
  end, timeout * 1000)
end

function Session:stop()
  if self.job then
    process.kill(self.job)
    self.job = nil
  end
  self.busy = false
  self.queue = {}
  self.pending_permission = nil
end

---@param thread Thread
function M.stop(thread)
  if thread.session then
    thread.session:stop()
  end
end

return M
