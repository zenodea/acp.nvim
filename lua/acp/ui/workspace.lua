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

---Build the chat column (chat + input) next to the sidebar (or far left).
---@param thread Thread
function M.build_chat_column(thread)
  local cfg = require("acp.config").options.ui
  local chat_buf = require("acp.ui.chat").ensure_buf(thread)
  local input_buf = require("acp.ui.input").ensure_buf(thread)

  local sidebar_win = M.find_ui_win(vim.api.nvim_get_current_tabpage(), "sidebar")
  if sidebar_win then
    vim.api.nvim_set_current_win(sidebar_win)
    vim.cmd("rightbelow " .. cfg.chat_width .. "vsplit")
  else
    vim.cmd("topleft " .. cfg.chat_width .. "vsplit")
  end
  local chat_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(chat_win, chat_buf)
  mark(chat_win, "chat")
  vim.wo[chat_win].wrap = true
  vim.wo[chat_win].linebreak = true
  vim.wo[chat_win].winfixwidth = true
  M.update_winbar(thread)

  vim.cmd("belowright " .. cfg.input_height .. "split")
  local input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(input_win, input_buf)
  mark(input_win, "input")
  vim.wo[input_win].wrap = true
  vim.wo[input_win].winfixheight = true
  vim.wo[input_win].winfixwidth = true
  vim.wo[input_win].winbar = " ⏎ send · C-j newline · C-c interrupt"

  -- Highlight context chips like "(file.txt 1-3)" in both chat windows.
  local chip_regex = [[([^) ]\+ \d\+-\d\+)]]
  for _, win in ipairs({ chat_win, input_win }) do
    vim.api.nvim_win_call(win, function()
      vim.fn.matchadd("AcpChip", chip_regex)
    end)
  end

  -- Keep the transcript pinned to the bottom initially.
  local last = vim.api.nvim_buf_line_count(chat_buf)
  pcall(vim.api.nvim_win_set_cursor, chat_win, { last, 0 })

  -- Splitting the sidebar redistributes widths; restore them.
  if sidebar_win and vim.api.nvim_win_is_valid(sidebar_win) then
    vim.api.nvim_win_set_width(sidebar_win, cfg.sidebar_width)
  end
  vim.api.nvim_win_set_width(chat_win, cfg.chat_width)
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
  require("acp.ui.sidebar").snap()
end

---@param thread Thread
local function build_tab(thread)
  vim.cmd("tabnew")
  thread.tabpage = vim.api.nvim_get_current_tabpage()
  if vim.fn.isdirectory(thread.cwd) == 1 then
    vim.cmd("tcd " .. vim.fn.fnameescape(thread.cwd))
  end

  -- Right: restore the persisted code layout into the initial window.
  local code_win = vim.api.nvim_get_current_win()
  if thread.layout then
    require("acp.persist.layout").restore(thread.layout)
  end

  -- Column order: sidebar | chat | code.
  vim.api.nvim_set_current_win(code_win)
  M.build_sidebar()
  M.build_chat_column(thread)
  vim.api.nvim_set_current_win(code_win)
end

---Refresh the chat winbar: "name · agent [mode]".
---@param thread Thread
function M.update_winbar(thread)
  if not thread:tab_valid() then
    return
  end
  local win = M.find_ui_win(thread.tabpage, "chat")
  if not win then
    return
  end
  local agent = thread.agent or require("acp.config").options.default_agent
  local text = " " .. thread.name .. (agent and (" · " .. agent) or "")
  local session = thread.session
  local badges = {}
  if session then
    -- Prefer config options (mode/model categories); fall back to legacy modes.
    for _, opt in ipairs(session.config_options or {}) do
      if opt.category == "mode" or opt.category == "model" then
        local label = tostring(opt.currentValue)
        if opt.type == "select" then
          for _, o in ipairs(opt.options or {}) do
            if o.value == opt.currentValue then
              label = o.name or o.value
            end
          end
        end
        table.insert(badges, label)
      end
    end
    if #badges == 0 and session.modes and session.modes.currentModeId then
      local mode = session:find_mode(session.modes.currentModeId)
      table.insert(badges, (mode and mode.name) or session.modes.currentModeId)
    end
  end
  if #badges > 0 then
    text = text .. " [" .. table.concat(badges, " · ") .. "]"
  end
  vim.wo[win].winbar = text
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

---First non-plugin window of a tab (the code area).
---@param tabpage integer
---@return integer|nil
local function find_code_win(tabpage)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if not vim.w[win].acp_ui then
      return win
    end
  end
end

---Open (or focus) a thread's workspace tab.
---@param thread Thread
function M.open(thread)
  local registry = require("acp.core.registry")
  local from_role = vim.w[vim.api.nvim_get_current_win()].acp_ui or "code"
  if thread:tab_valid() then
    vim.api.nvim_set_current_tabpage(thread.tabpage)
  else
    build_tab(thread)
  end
  registry.last_active = thread.id
  thread.last_active = os.time()
  registry.emit("state")

  local focus = require("acp.config").options.ui.focus_on_open
  if focus == "keep" then
    focus = from_role
  end
  if focus == "input" then
    require("acp.ui.input").focus(thread)
    return
  end
  local win
  if focus == "code" then
    win = find_code_win(thread.tabpage)
  else
    win = find_ui_win(thread.tabpage, focus)
  end
  win = win or find_code_win(thread.tabpage)
  if win then
    vim.api.nvim_set_current_win(win)
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
