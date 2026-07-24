local M = {}

function M.setup()
  local links = {
    AcpSidebarTitle = "Title",
    AcpSidebarHint = "Comment",
    AcpSidebarBranch = "Comment",
    AcpSidebarGroup = "Directory",
    AcpStatusWorking = "DiagnosticWarn",
    AcpStatusAttention = "DiagnosticError",
    AcpStatusIdle = "DiagnosticOk",
    AcpStatusError = "ErrorMsg",
    -- Turn headers get their own hues, distinct from tool-call titles
    -- (Function): user prompts read as commands, agent headers as values.
    AcpChatUser = "Statement",
    AcpChatAgent = "Constant",
    AcpChatTool = "Function",
    AcpChatThinking = "Comment",
    AcpChatMeta = "Comment",
    AcpChatError = "DiagnosticError",
    AcpChatPermission = "DiagnosticWarn",
    AcpDiffAdd = "DiffAdd",
    AcpDiffDelete = "DiffDelete",
    AcpDiffAddText = "DiffText",
    AcpDiffDeleteText = "DiffText",
    AcpDiffSep = "NonText",
    AcpPlanActive = "Title",
    AcpChip = "Special",
  }
  for group, link in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

---@param status ThreadStatus
---@return string
function M.status_group(status)
  return ({
    working = "AcpStatusWorking",
    attention = "AcpStatusAttention",
    idle = "AcpStatusIdle",
    error = "AcpStatusError",
  })[status] or "Normal"
end

return M
