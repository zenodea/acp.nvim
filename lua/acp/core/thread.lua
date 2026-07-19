local util = require("acp.util")

---@alias ThreadStatus "idle"|"working"|"attention"|"error"

---@class TranscriptEntry
---@field kind "user"|"text"|"tool"|"thinking"|"permission"|"meta"|"error"
---@field text string

---@class Thread
---@field id string
---@field name string
---@field slug string
---@field status ThreadStatus
---@field status_detail string|nil  -- e.g. "permission: Bash", "asked a question"
---@field cwd string               -- worktree path or project root
---@field worktree {path: string, branch: string}|nil
---@field session_id string|nil    -- Claude Code session id, for --resume
---@field transcript TranscriptEntry[]
---@field layout table|nil         -- serialized code-area layout
---@field created_at integer
---@field last_active integer
---@field tabpage integer|nil      -- transient
---@field session table|nil        -- transient agent session
---@field chat_buf integer|nil     -- transient
---@field input_buf integer|nil    -- transient
local Thread = {}
Thread.__index = Thread

---@param opts {name: string, cwd: string, worktree: table|nil, agent: string|nil}
---@return Thread
function Thread.new(opts)
  local self = setmetatable({}, Thread)
  self.id = util.uuid()
  self.name = opts.name
  self.agent = opts.agent
  self.slug = util.slugify(opts.name)
  self.status = "idle"
  self.status_detail = nil
  self.cwd = opts.cwd
  self.worktree = opts.worktree
  self.session_id = nil
  self.transcript = {}
  self.layout = nil
  self.created_at = os.time()
  self.last_active = os.time()
  return self
end

---Rebuild a Thread object from persisted plain-table state.
---@param data table
---@return Thread
function Thread.from_state(data)
  local self = setmetatable({}, Thread)
  self.id = data.id
  self.name = data.name
  self.agent = data.agent
  self.slug = data.slug
  -- A restored thread is never mid-turn; keep attention/error, downgrade working.
  self.status = data.status == "working" and "idle" or (data.status or "idle")
  self.status_detail = data.status_detail
  self.cwd = data.cwd
  self.worktree = data.worktree
  self.session_id = data.session_id
  self.transcript = data.transcript or {}
  self.layout = data.layout
  self.created_at = data.created_at or os.time()
  self.last_active = data.last_active or os.time()
  return self
end

---Plain-table snapshot for persistence.
---@return table
function Thread:to_state()
  local max = require("acp.config").options.persist.max_transcript
  local transcript = self.transcript
  if #transcript > max then
    transcript = vim.list_slice(transcript, #transcript - max + 1, #transcript)
  end
  return {
    id = self.id,
    name = self.name,
    agent = self.agent,
    slug = self.slug,
    status = self.status,
    status_detail = self.status_detail,
    cwd = self.cwd,
    worktree = self.worktree,
    session_id = self.session_id,
    transcript = transcript,
    layout = self.layout,
    created_at = self.created_at,
    last_active = self.last_active,
  }
end

---@param status ThreadStatus
---@param detail string|nil
function Thread:set_status(status, detail)
  if self.status == status and self.status_detail == detail then
    return
  end
  local old = self.status
  self.status = status
  self.status_detail = detail
  self.last_active = os.time()
  require("acp.core.registry").emit("status", self, old)
end

---@return boolean
function Thread:tab_valid()
  return self.tabpage ~= nil and vim.api.nvim_tabpage_is_valid(self.tabpage)
end

return Thread
