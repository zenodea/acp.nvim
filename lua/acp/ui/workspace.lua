local M = {}

---Title a window: a highlighted chip saying what the window is, followed by
---optional live detail. With one statusline at the bottom of the screen
---(ui.global_statusline) this bar is a plugin window's only nameplate.
---
---'winbar' takes statusline syntax, where `%` introduces an item: an
---unescaped one in a thread name, a model label, or a percentage raises E539
---and leaves the winbar unset. Only the highlight items below are meant as
---syntax, so every `%` coming from elsewhere is doubled.
---@param win integer
---@param title string
---@param detail string|nil
local function set_title(win, title, detail)
  -- `%<` puts the truncation point after the chip: in a narrow window the
  -- detail gets cut, never the name of the window.
  local text = "%#AcpWinbarTitle# " .. title:gsub("%%", "%%%%") .. " %#AcpWinbarDetail#%<"
  if detail and detail ~= "" then
    text = text .. " " .. detail:gsub("%%", "%%%%")
  end
  vim.wo[win].winbar = text
end

---@param win integer
---@param role string
local function mark(win, role)
  vim.w[win].acp_ui = role
  -- The window says what it is in its winbar, so its statusline has nothing
  -- left to say: blank it rather than show the `acp://…` buffer name. Moot
  -- under ui.global_statusline (laststatus=3 draws one bar for the screen),
  -- which is why it degrades to an empty bar rather than a second title.
  vim.wo[win].statusline = " "
  -- Callers set the window's buffer before marking; from here on the window
  -- refuses buffer swaps, so file explorers pick a code window instead of
  -- clobbering the sidebar/chat/input.
  vim.wo[win].winfixbuf = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].list = false
  vim.wo[win].spell = false
end

---Build the chat column (chat + input) next to the sidebar (or far right).
---@param thread Thread
function M.build_chat_column(thread)
  local cfg = require("acp.config").options.ui
  local chat_buf = require("acp.ui.chat").ensure_buf(thread)
  local input_buf = require("acp.ui.input").ensure_buf(thread)

  local tab = vim.api.nvim_get_current_tabpage()
  local sidebar_win = M.find_ui_win(tab, "sidebar")
  if sidebar_win then
    -- The chat splits off the sidebar leaf: a details window stacked below
    -- it would end up spanning under the new chat, so drop it and rebuild
    -- it once the chat column is in place.
    local details_win = M.find_ui_win(tab, "details")
    if details_win then
      pcall(vim.api.nvim_win_close, details_win, true)
    end
    vim.api.nvim_set_current_win(sidebar_win)
    vim.cmd("leftabove " .. cfg.chat_width .. "vsplit")
  else
    vim.cmd("botright " .. cfg.chat_width .. "vsplit")
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
  M.update_input_winbar(thread)

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
  M.build_details()
end

---Build the threads sidebar window on the right of the current tab.
function M.build_sidebar()
  local cfg = require("acp.config").options.ui
  local buf = require("acp.ui.sidebar").ensure_buf()
  vim.cmd("botright " .. cfg.sidebar_width .. "vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  mark(win, "sidebar")
  set_title(win, "threads")
  vim.wo[win].winfixwidth = true
  vim.wo[win].cursorline = true
  require("acp.ui.sidebar").snap()
end

---Build the details panel docked below the sidebar of the current tab.
---Split off the sidebar leaf so the panel stays inside the sidebar column.
function M.build_details()
  local cfg = require("acp.config").options.ui
  -- Unset, the panel is as tall as the prompt window it faces.
  local height = cfg.details_height or cfg.input_height
  if height <= 0 then
    return
  end
  local tab = vim.api.nvim_get_current_tabpage()
  if M.find_ui_win(tab, "details") then
    return
  end
  local sidebar_win = M.find_ui_win(tab, "sidebar")
  if not sidebar_win then
    return
  end
  local cur = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(sidebar_win)
  vim.cmd("belowright " .. height .. "split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, require("acp.ui.details").ensure_buf())
  mark(win, "details")
  set_title(win, "details")
  vim.wo[win].winfixheight = true
  vim.wo[win].winfixwidth = true
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false -- inherited from the sidebar split
  pcall(vim.api.nvim_set_current_win, cur)
  require("acp.ui.details").render()
end

---@param thread Thread
local function build_tab(thread)
  vim.cmd("tabnew")
  thread.tabpage = vim.api.nvim_get_current_tabpage()
  if vim.fn.isdirectory(thread.cwd) == 1 then
    vim.cmd("tcd " .. vim.fn.fnameescape(thread.cwd))
  end

  -- Left: restore the persisted code layout into the initial window.
  local code_win = vim.api.nvim_get_current_win()
  if thread.layout then
    require("acp.persist.layout").restore(thread.layout)
  end

  -- Column order: code | chat | sidebar.
  vim.api.nvim_set_current_win(code_win)
  M.build_sidebar()
  M.build_chat_column(thread)
  -- The restored layout may have brought a follow mark back with it.
  M.update_follow_winbar(thread)
  vim.api.nvim_set_current_win(code_win)
end

---@param win integer
---@return boolean
local function is_code_win(win)
  return not vim.w[win].acp_ui and vim.api.nvim_win_get_config(win).relative == ""
end

---The code window a thread reveals files into: the one explicitly marked to
---follow the agent, else the first ordinary window of the tab. Floats (the
---plan panel, a tool-call detail) are never candidates.
---@param tabpage integer
---@return integer|nil
local function find_code_win(tabpage)
  local first
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
    if is_code_win(win) then
      if vim.w[win].acp_follow then
        return win
      end
      first = first or win
    end
  end
  return first
end

---@param win integer
local function unmark_follow(win)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.w[win].acp_follow = nil
  -- Restore whatever winbar the window carried before it was marked.
  vim.wo[win].winbar = vim.w[win].acp_follow_winbar or ""
  vim.w[win].acp_follow_winbar = nil
end

---Repaint the marked window's winbar: follow can also be toggled from the
---chat with gf, and a paused target must not claim to be following.
---@param thread Thread
function M.update_follow_winbar(thread)
  if not thread:tab_valid() then
    return
  end
  local on = thread:follow_enabled()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(thread.tabpage)) do
    if vim.w[win].acp_follow then
      if on then
        set_title(win, "⟳ following", thread:agent_name())
      else
        set_title(win, "⟳ follow paused", "gf to resume")
      end
    end
  end
end

---Mark the current window as where the agent's edits are revealed, and turn
---follow on. Repeating it in the marked window clears the mark and turns
---follow off, so one key covers both directions.
---@param thread Thread
function M.follow_here(thread)
  local win = vim.api.nvim_get_current_win()
  if not is_code_win(win) then
    vim.notify("acp: run this in a code window, not a plugin window", vim.log.levels.WARN)
    return
  end
  if not thread:tab_valid() or vim.api.nvim_win_get_tabpage(win) ~= thread.tabpage then
    vim.notify("acp: this window is not in " .. thread.name .. "'s tab", vim.log.levels.WARN)
    return
  end
  if vim.w[win].acp_follow then
    unmark_follow(win)
    thread.follow = false
    vim.notify("acp: follow mode off")
    return
  end
  -- One target per tab: the agent reveals into a single window.
  for _, other in ipairs(vim.api.nvim_tabpage_list_wins(thread.tabpage)) do
    if vim.w[other].acp_follow then
      unmark_follow(other)
    end
  end
  vim.w[win].acp_follow_winbar = vim.wo[win].winbar
  vim.w[win].acp_follow = true
  thread.follow = true
  M.update_follow_winbar(thread)
  require("acp.persist.store").save_debounced()
  vim.notify("acp: following " .. thread:agent_name() .. " in this window")
end

---Show a file (and line) in the thread's code window without stealing focus.
---@param thread Thread
---@param path string
---@param line integer|nil
---@return integer|nil win the code window revealed into
function M.reveal(thread, path, line)
  if not thread:tab_valid() or not path or vim.fn.filereadable(path) ~= 1 then
    return
  end
  local win = find_code_win(thread.tabpage)
  if not win then
    return
  end
  local buf = vim.fn.bufadd(path)
  vim.bo[buf].buflisted = true
  pcall(vim.fn.bufload, buf)
  pcall(vim.api.nvim_win_set_buf, win, buf)
  if line then
    pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
  end
  return win
end

---Refresh the chat title: "chat" plus "name · agent [mode] ▤ 2/5 ◇ 1 ◔ 21%".
---@param thread Thread
function M.update_winbar(thread)
  if not thread:tab_valid() then
    return
  end
  local win = M.find_ui_win(thread.tabpage, "chat")
  if not win then
    return
  end
  local agent = thread:agent_name()
  local text = thread.name .. (agent and (" · " .. agent) or "")
  local session = thread.session
  local badges = {}
  if session then
    -- Prefer config options (mode/model categories); fall back to legacy modes.
    for _, opt in ipairs(session.config_options or {}) do
      if opt.category == "mode" or opt.category == "model" then
        table.insert(badges, session:option_label(opt))
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
  -- Plan progress rides outside the brackets: those hold what the session is
  -- configured as, this is what it is doing.
  local done, total = require("acp.ui.plan").progress(thread)
  if total > 0 then
    text = text .. ("  ▤ %d/%d"):format(done, total)
  end
  local subagents = require("acp.ui.subagents").running(thread)
  if subagents > 0 then
    text = text .. ("  ◇ %d"):format(subagents)
  end
  local usage = require("acp.agent.events").usage_text(thread.usage)
  if usage then
    text = text .. "  " .. usage
  end
  if session and session.starting then
    text = text .. "  " .. (session.spinner or "…") .. " starting"
  end
  set_title(win, "chat", text)
  -- Everything the winbar summarises (plan, subagents, usage) also feeds the
  -- details panel, so this is its repaint hub too.
  require("acp.ui.details").render()
end

---Refresh the input title: send hints, plus the prompt queue when non-empty.
---@param thread Thread
function M.update_input_winbar(thread)
  if not thread:tab_valid() then
    return
  end
  local win = M.find_ui_win(thread.tabpage, "input")
  if not win then
    return
  end
  local queue = (thread.session and thread.session.queue) or {}
  if #queue > 0 then
    set_title(win, "prompt", ("⧗ %d queued · gq edit · C-c interrupt"):format(#queue))
  else
    set_title(win, "prompt", "⏎ send · C-j newline · C-c interrupt")
  end
  require("acp.ui.details").render()
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
  local from_role = vim.w[vim.api.nvim_get_current_win()].acp_ui or "code"
  if thread:tab_valid() then
    vim.api.nvim_set_current_tabpage(thread.tabpage)
  else
    build_tab(thread)
  end
  registry.last_active = thread.id
  thread.last_active = os.time()
  registry.emit("state")
  -- Keep every sidebar window's cursor on the thread being opened.
  require("acp.ui.sidebar").reveal(thread.id)

  -- Boot the agent session right away so it is ready for the first message.
  if require("acp.config").options.autostart then
    require("acp.agent.session").get(thread):ensure_started(function() end)
  end

  local focus = require("acp.config").options.ui.focus_on_open
  if focus == "keep" then
    focus = from_role
  end
  if focus == "input" then
    require("acp.ui.input").focus(thread)
    return
  end
  local win = find_ui_win(thread.tabpage, focus) or find_code_win(thread.tabpage)
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
      vim.api.nvim_set_current_tabpage(t)
      vim.cmd("tabclose")
      break
    end
  end
end

return M
