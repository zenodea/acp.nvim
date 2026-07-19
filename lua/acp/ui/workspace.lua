local M = {}

---@param win integer
---@param role string
local function mark(win, role)
  vim.w[win].acp_ui = role
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].list = false
  vim.wo[win].spell = false
end

---Build the chat column (chat + input) on the right of the current tab.
---@param thread Thread
function M.build_chat_column(thread)
  local cfg = require("acp.config").options.ui
  local chat_buf = require("acp.ui.chat").ensure_buf(thread)
  local input_buf = require("acp.ui.input").ensure_buf(thread)

  vim.cmd("botright " .. cfg.chat_width .. "vsplit")
  local chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(chat_win, chat_buf)
  mark(chat_win, "chat")
  vim.wo[chat_win].wrap = true
  vim.wo[chat_win].linebreak = true
  vim.wo[chat_win].winfixwidth = true
  vim.wo[chat_win].winbar = " " .. thread.name

  vim.cmd("belowright " .. cfg.input_height .. "split")
  local input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(input_win, input_buf)
  mark(input_win, "input")
  vim.wo[input_win].wrap = true
  vim.wo[input_win].winfixheight = true
  vim.wo[input_win].winfixwidth = true
  vim.wo[input_win].winbar = " ⏎ send · C-j newline · C-c interrupt"

  -- Keep the transcript pinned to the bottom initially.
  local last = vim.api.nvim_buf_line_count(chat_buf)
  pcall(vim.api.nvim_win_set_cursor, chat_win, { last, 0 })
end

---Build the threads sidebar window on the left of the current tab.
function M.build_sidebar()
  local cfg = require("acp.config").options.ui
  local buf = require("acp.ui.sidebar").ensure_buf()
  vim.cmd("topleft " .. cfg.sidebar_width .. "vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  mark(win, "sidebar")
  vim.wo[win].winfixwidth = true
  vim.wo[win].cursorline = true
end

---@param thread Thread
local function build_tab(thread)
  vim.cmd("tabnew")
  thread.tabpage = vim.api.nvim_get_current_tabpage()
  if vim.fn.isdirectory(thread.cwd) == 1 then
    vim.cmd("tcd " .. vim.fn.fnameescape(thread.cwd))
  end

  -- Center: restore the persisted code layout into the initial window.
  local code_win = vim.api.nvim_get_current_win()
  if thread.layout then
    require("acp.persist.layout").restore(thread.layout)
  end

  vim.api.nvim_set_current_win(code_win)
  M.build_chat_column(thread)
  M.build_sidebar()
  vim.api.nvim_set_current_win(code_win)
end

---@param tabpage integer
---@param role string
---@return integer|nil win
function M.find_ui_win(tabpage, role)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if vim.w[win].acp_ui == role then
      return win
    end
  end
end

local find_ui_win = M.find_ui_win

---Open (or focus) a thread's workspace tab.
---@param thread Thread
function M.open(thread)
  local registry = require("acp.core.registry")
  if thread:tab_valid() then
    vim.api.nvim_set_current_tabpage(thread.tabpage)
  else
    build_tab(thread)
  end
  registry.last_active = thread.id
  thread.last_active = os.time()
  registry.emit("state")

  local focus = require("acp.config").options.ui.focus_on_open
  if focus == "input" then
    require("acp.ui.input").focus(thread)
  elseif focus == "sidebar" then
    local win = find_ui_win(thread.tabpage, "sidebar")
    if win then
      vim.api.nvim_set_current_win(win)
    end
  end
end

---Show/hide the chat column in the current thread tab.
function M.toggle_chat()
  local registry = require("acp.core.registry")
  local tab = vim.api.nvim_get_current_tabpage()
  local thread = registry.find_by_tab(tab)
  if not thread then
    vim.notify("acp: current tab is not a thread workspace", vim.log.levels.WARN)
    return
  end
  local chat_win = find_ui_win(tab, "chat")
  local input_win = find_ui_win(tab, "input")
  if chat_win or input_win then
    for _, win in ipairs({ chat_win, input_win }) do
      if win then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  else
    local cur = vim.api.nvim_get_current_win()
    M.build_chat_column(thread)
    pcall(vim.api.nvim_set_current_win, cur)
  end
end

---Snapshot the code-area layout of a thread's tab into thread.layout.
---@param thread Thread
function M.capture_layout(thread)
  if not thread:tab_valid() then
    return
  end
  local layout = require("acp.persist.layout").capture(thread.tabpage)
  if layout then
    thread.layout = layout
  end
end

---Close a thread's tab (capturing layout first).
---@param thread Thread
function M.close(thread)
  if not thread:tab_valid() then
    return
  end
  M.capture_layout(thread)
  local tab = thread.tabpage
  thread.tabpage = nil
  if #vim.api.nvim_list_tabpages() == 1 then
    -- Can't close the last tab; blank it out instead.
    vim.cmd("tabnew")
  end
  for _, t in ipairs(vim.api.nvim_list_tabpages()) do
    if t == tab then
      local wins = vim.api.nvim_tabpage_list_wins(t)
      vim.api.nvim_set_current_tabpage(t)
      vim.cmd("tabclose")
      break
    end
  end
end

return M
