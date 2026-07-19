local process = require("acp.agent.process")

---JSON-RPC 2.0 client over newline-delimited JSON on stdio — the ACP wire
---format. Handles outgoing requests/notifications and incoming
---agent->client requests (permissions, fs) and notifications (session/update).
---@class Rpc
---@field job integer|nil
---@field pending table<integer, fun(result: any, err: table|nil)>
---@field next_id integer
---@field handlers RpcHandlers
local Rpc = {}
Rpc.__index = Rpc

---@class RpcHandlers
---@field on_request fun(method: string, params: any, respond: fun(result: any, err: table|nil))
---@field on_notification fun(method: string, params: any)
---@field on_exit fun(code: integer)
---@field on_stderr fun(text: string)|nil

local M = {}

---@param opts {args: string[], cwd: string, env: table|nil, handlers: RpcHandlers}
---@return Rpc|nil rpc, string|nil err
function M.spawn(opts)
  local self = setmetatable({
    job = nil,
    pending = {},
    next_id = 0,
    handlers = opts.handlers,
  }, Rpc)

  local job, err = process.spawn({
    args = opts.args,
    cwd = opts.cwd,
    env = opts.env,
    on_line = function(line)
      self:on_line(line)
    end,
    on_stderr = opts.handlers.on_stderr,
    on_exit = function(code)
      local pending = self.pending
      self.pending = {}
      self.job = nil
      for _, cb in pairs(pending) do
        pcall(cb, nil, { code = -1, message = "agent process exited" })
      end
      opts.handlers.on_exit(code)
    end,
  })
  if not job then
    return nil, err
  end
  self.job = job
  return self, nil
end

---@param line string
function Rpc:on_line(line)
  local ok, msg = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
  if not ok or type(msg) ~= "table" then
    return
  end

  if msg.method and msg.id ~= nil then
    -- Incoming request from the agent; must be answered exactly once.
    local answered = false
    self.handlers.on_request(msg.method, msg.params, function(result, err)
      if answered then
        return
      end
      answered = true
      if err then
        self:send({ jsonrpc = "2.0", id = msg.id, error = err })
      else
        if result == nil then
          result = vim.NIL
        end
        self:send({ jsonrpc = "2.0", id = msg.id, result = result })
      end
    end)
  elseif msg.method then
    self.handlers.on_notification(msg.method, msg.params)
  elseif msg.id ~= nil then
    local cb = self.pending[msg.id]
    self.pending[msg.id] = nil
    if cb then
      cb(msg.result, msg.error)
    end
  end
end

---@param tbl table
function Rpc:send(tbl)
  if self.job then
    process.send(self.job, tbl)
  end
end

---@param method string
---@param params any
---@param cb fun(result: any, err: table|nil)|nil
function Rpc:request(method, params, cb)
  if not self.job then
    if cb then
      cb(nil, { code = -1, message = "agent process not running" })
    end
    return
  end
  self.next_id = self.next_id + 1
  local id = self.next_id
  if cb then
    self.pending[id] = cb
  end
  self:send({ jsonrpc = "2.0", id = id, method = method, params = params })
end

---@param method string
---@param params any
function Rpc:notify(method, params)
  self:send({ jsonrpc = "2.0", method = method, params = params })
end

---@return boolean
function Rpc:alive()
  return process.alive(self.job)
end

function Rpc:kill()
  if self.job then
    process.kill(self.job)
    self.job = nil
  end
end

return M
