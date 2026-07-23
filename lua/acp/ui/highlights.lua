local M = {}

function M.setup()
  local links = {
    AcpSidebarTitle = "Title",
    AcpSidebarHint = "Comment",
    AcpSidebarBranch = "Comment",
    AcpStatusWorking = "DiagnosticWarn",
    AcpStatusAttention = "DiagnosticError",
    AcpStatusIdle = "DiagnosticOk",
    AcpStatusError = "ErrorMsg",
    AcpChatUser = "Title",
    AcpChatAgent = "Function",
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
