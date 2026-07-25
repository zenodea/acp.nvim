local h = require("tests.helpers")
local eq = h.eq

h.stub("acp.persist.store", { save_debounced = function() end, save = function() end })
local workspace = require("acp.ui.workspace")
local Thread = require("acp.core.thread")

---A thread whose tab is the current one, with `n` extra code windows.
---@param splits integer
---@return Thread thread, integer[] code windows, integer ui window
local function tab_with(splits)
  local thread = Thread.new({ name = "follow-test", cwd = vim.fn.getcwd() })
  thread.tabpage = vim.api.nvim_get_current_tabpage()
  -- The runner keeps one window alive between tests, and a split inherits
  -- the winbar of the window it came from: wipe the plugin's window-local
  -- state so nothing here reads the previous test's leftovers.
  local function blank(win)
    vim.wo[win].winbar = ""
    vim.w[win].acp_ui = nil
    vim.w[win].acp_follow = nil
    vim.w[win].acp_follow_winbar = nil
    return win
  end
  local wins = { blank(vim.api.nvim_get_current_win()) }
  for _ = 1, splits do
    vim.cmd("vsplit")
    table.insert(wins, blank(vim.api.nvim_get_current_win()))
  end
  -- One plugin window, so the "code window" filter has something to reject.
  vim.cmd("vsplit")
  local ui = blank(vim.api.nvim_get_current_win())
  vim.w[ui].acp_ui = "chat"
  vim.api.nvim_set_current_win(wins[1])
  return thread, wins, ui
end

---The window reveal() picks when nothing is marked: `:vsplit` opens to the
---left, so it is the last one created, not wins[1].
---@param wins integer[]
---@return integer
local function leftmost(wins)
  return wins[#wins]
end

---@param thread Thread
---@param path string
local function reveal(thread, path)
  return workspace.reveal(thread, path, 1)
end

local T = {}

function T.marking_a_window_turns_follow_on()
  local thread, wins = tab_with(1)
  vim.api.nvim_set_current_win(wins[2])
  workspace.follow_here(thread)
  eq(true, thread.follow, "follow enabled")
  eq(true, vim.w[wins[2]].acp_follow, "window marked")
  eq(true, vim.wo[wins[2]].winbar:find("following", 1, true) ~= nil, "winbar: " .. vim.wo[wins[2]].winbar)
end

function T.reveal_lands_in_the_marked_window_not_the_first()
  local thread, wins = tab_with(2)
  local target = vim.fn.tempname()
  vim.fn.writefile({ "one", "two" }, target)
  local before = vim.api.nvim_win_get_buf(leftmost(wins))

  -- Mark wins[1], which is *not* the one reveal would pick on its own.
  vim.api.nvim_set_current_win(wins[1])
  workspace.follow_here(thread)
  reveal(thread, target)

  local shown = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(wins[1]))
  eq(vim.fn.resolve(target), vim.fn.resolve(shown), "file landed in the marked window")
  eq(before, vim.api.nvim_win_get_buf(leftmost(wins)), "the default target was left alone")
  vim.fn.delete(target)
end

function T.reveal_falls_back_to_a_code_window_when_unmarked()
  local thread, wins = tab_with(1)
  local target = vim.fn.tempname()
  vim.fn.writefile({ "one" }, target)
  reveal(thread, target)
  local win = leftmost(wins)
  local shown = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
  eq(vim.fn.resolve(target), vim.fn.resolve(shown))
  vim.fn.delete(target)
end

function T.a_float_is_never_the_reveal_target()
  local thread, wins = tab_with(0)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_open_win(buf, true, { relative = "editor", row = 1, col = 1, width = 20, height = 5 })
  local target = vim.fn.tempname()
  vim.fn.writefile({ "one" }, target)
  reveal(thread, target)
  eq(buf, vim.api.nvim_win_get_buf(0), "float untouched")
  eq(vim.fn.resolve(target), vim.fn.resolve(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(wins[1]))))
  vim.fn.delete(target)
end

function T.marking_moves_the_mark_off_the_previous_window()
  local thread, wins = tab_with(2)
  vim.api.nvim_set_current_win(wins[2])
  workspace.follow_here(thread)
  vim.api.nvim_set_current_win(wins[3])
  workspace.follow_here(thread)
  eq(nil, vim.w[wins[2]].acp_follow, "old mark cleared")
  eq(true, vim.w[wins[3]].acp_follow, "new window marked")
  eq("", vim.wo[wins[2]].winbar, "old winbar restored")
end

function T.marking_the_marked_window_again_turns_follow_off()
  local thread, wins = tab_with(1)
  vim.api.nvim_set_current_win(wins[2])
  vim.wo[wins[2]].winbar = " mine "
  workspace.follow_here(thread)
  workspace.follow_here(thread)
  eq(false, thread.follow, "follow disabled")
  eq(nil, vim.w[wins[2]].acp_follow, "mark cleared")
  eq(" mine ", vim.wo[wins[2]].winbar, "the window's own winbar came back")
end

function T.pausing_follow_relabels_the_marked_window()
  local thread, wins = tab_with(1)
  vim.api.nvim_set_current_win(wins[2])
  workspace.follow_here(thread)
  thread.follow = false -- what gf does
  workspace.update_follow_winbar(thread)
  eq(true, vim.wo[wins[2]].winbar:find("paused", 1, true) ~= nil, "winbar: " .. vim.wo[wins[2]].winbar)
end

function T.plugin_windows_refuse_the_mark()
  local thread, _, ui = tab_with(1)
  local notified
  local orig = vim.notify
  vim.notify = function(msg)
    notified = msg
  end
  vim.api.nvim_set_current_win(ui)
  workspace.follow_here(thread)
  vim.notify = orig
  eq(nil, vim.w[ui].acp_follow, "plugin window not marked")
  eq(nil, thread.follow, "follow left alone")
  eq(true, notified ~= nil and notified:find("code window", 1, true) ~= nil, "notified: " .. tostring(notified))
end

function T.the_mark_round_trips_through_a_captured_layout()
  local thread, wins = tab_with(1)
  vim.api.nvim_set_current_win(wins[2])
  workspace.follow_here(thread)
  local layout = require("acp.persist.layout").capture(thread.tabpage)
  local marked = 0
  for _, child in ipairs(layout.children) do
    marked = marked + (child.follow and 1 or 0)
  end
  eq(2, #layout.children, "both code windows captured, the plugin window pruned")
  eq(1, marked, "exactly one leaf carries the mark")

  vim.cmd("only")
  require("acp.persist.layout").restore(layout)
  local marked = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.w[win].acp_follow then
      table.insert(marked, win)
    end
  end
  eq(1, #marked, "exactly one window came back marked")
end

return T
