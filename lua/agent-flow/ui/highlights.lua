local M = {}

function M.setup()
  local links = {
    AgentFlowSidebarTitle = "Title",
    AgentFlowSidebarHint = "Comment",
    AgentFlowSidebarBranch = "Comment",
    AgentFlowStatusWorking = "DiagnosticWarn",
    AgentFlowStatusAttention = "DiagnosticError",
    AgentFlowStatusIdle = "DiagnosticOk",
    AgentFlowStatusError = "ErrorMsg",
    AgentFlowChatUser = "Title",
    AgentFlowChatTool = "Function",
    AgentFlowChatThinking = "Comment",
    AgentFlowChatMeta = "Comment",
    AgentFlowChatError = "DiagnosticError",
    AgentFlowChatPermission = "DiagnosticWarn",
    AgentFlowDiffAdd = "DiffAdd",
    AgentFlowDiffDelete = "DiffDelete",
  }
  for group, link in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

---@param status ThreadStatus
---@return string
function M.status_group(status)
  return ({
    working = "AgentFlowStatusWorking",
    attention = "AgentFlowStatusAttention",
    idle = "AgentFlowStatusIdle",
    error = "AgentFlowStatusError",
  })[status] or "Normal"
end

return M
