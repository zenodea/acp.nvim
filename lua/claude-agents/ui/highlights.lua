local M = {}

function M.setup()
  local links = {
    ClaudeAgentsSidebarTitle = "Title",
    ClaudeAgentsSidebarHint = "Comment",
    ClaudeAgentsSidebarBranch = "Comment",
    ClaudeAgentsStatusWorking = "DiagnosticWarn",
    ClaudeAgentsStatusAttention = "DiagnosticError",
    ClaudeAgentsStatusIdle = "DiagnosticOk",
    ClaudeAgentsStatusError = "ErrorMsg",
    ClaudeAgentsChatUser = "Title",
    ClaudeAgentsChatTool = "Function",
    ClaudeAgentsChatThinking = "Comment",
    ClaudeAgentsChatMeta = "Comment",
    ClaudeAgentsChatError = "DiagnosticError",
    ClaudeAgentsChatPermission = "DiagnosticWarn",
    ClaudeAgentsDiffAdd = "DiffAdd",
    ClaudeAgentsDiffDelete = "DiffDelete",
  }
  for group, link in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

---@param status ThreadStatus
---@return string
function M.status_group(status)
  return ({
    working = "ClaudeAgentsStatusWorking",
    attention = "ClaudeAgentsStatusAttention",
    idle = "ClaudeAgentsStatusIdle",
    error = "ClaudeAgentsStatusError",
  })[status] or "Normal"
end

return M
