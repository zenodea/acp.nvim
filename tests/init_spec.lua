local h = require("tests.helpers")
local eq = h.eq

h.stub("acp.persist.store", {
  save_debounced = function() end,
  save = function() end,
  load = function() end,
})
require("acp").setup({})

---One code window plus one marked plugin window in the current tab.
---@return integer ui_win
local function workspace_layout()
  vim.cmd("vsplit")
  local ui_win = vim.api.nvim_get_current_win()
  vim.w[ui_win].acp_ui = "chat"
  vim.cmd("wincmd p")
  return ui_win
end

local T = {}

function T.quit_in_float_keeps_the_workspace()
  local ui_win = workspace_layout()
  local buf = vim.api.nvim_create_buf(false, true)
  local float = vim.api.nvim_open_win(buf, true, { relative = "editor", row = 1, col = 1, width = 10, height = 3 })
  vim.cmd("quit")
  eq(false, vim.api.nvim_win_is_valid(float), "float closed")
  eq(true, vim.api.nvim_win_is_valid(ui_win), "plugin window survives")
end

function T.quit_last_code_window_closes_plugin_windows()
  vim.cmd("tabnew") -- keep another tab so the quit cannot exit Neovim
  local ui_win = workspace_layout()
  vim.cmd("quit")
  eq(false, vim.api.nvim_win_is_valid(ui_win), "plugin window closed too")
end

return T
