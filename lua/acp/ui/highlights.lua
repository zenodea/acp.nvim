local M = {}

function M.setup()
  local links = {
    AcpSidebarHint = "Comment",
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
    -- Live detail next to a window's title chip (thread name, send hints).
    AcpWinbarDetail = "Comment",
  }
  for group, link in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end

  -- The title chip every plugin window wears in its winbar. No colourscheme
  -- ships a group for it, so it is derived: Title's colour on the fill used
  -- for popups, which reads as a small box on any background. Re-derived
  -- whenever the colourscheme changes (see the ColorScheme autocmd).
  local function resolve(name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
    return (ok and hl) or {}
  end
  vim.api.nvim_set_hl(0, "AcpWinbarTitle", {
    fg = resolve("Title").fg,
    bg = resolve("Pmenu").bg or resolve("CursorLine").bg or resolve("Visual").bg,
    bold = true,
    default = true,
  })
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
