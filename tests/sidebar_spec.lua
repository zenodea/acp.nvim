local h = require("tests.helpers")
local eq = h.eq

local registry = h.stub("acp.core.registry", {
  threads = {
    { id = "a", name = "alpha", status = "idle" },
    { id = "b", name = "beta", status = "working" },
    { id = "c", name = "gamma", status = "idle", worktree = { branch = "feat/x" } },
  },
})
local sidebar = require("acp.ui.sidebar")

local T = {}

function T.reveal_moves_every_sidebar_window()
  sidebar.render()
  vim.api.nvim_win_set_buf(0, sidebar.buf)
  vim.cmd("vsplit")
  local wins = vim.fn.win_findbuf(sidebar.buf)
  eq(2, #wins)
  vim.api.nvim_win_set_cursor(wins[1], { 3, 0 })
  vim.api.nvim_win_set_cursor(wins[2], { 4, 0 })
  sidebar.reveal("c")
  eq(5, vim.api.nvim_win_get_cursor(wins[1])[1], "gamma line")
  eq(5, vim.api.nvim_win_get_cursor(wins[2])[1], "gamma line")
end

function T.reveal_unknown_id_is_noop()
  sidebar.render()
  vim.api.nvim_win_set_buf(0, sidebar.buf)
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  sidebar.reveal("does-not-exist")
  eq(4, vim.api.nvim_win_get_cursor(0)[1])
end

function T.snap_keeps_cursor_on_thread_names()
  sidebar.render()
  vim.api.nvim_win_set_buf(0, sidebar.buf)
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  vim.cmd("doautocmd CursorMoved")
  -- Line 6 is gamma's branch line, not a name: snapping pulls the cursor on.
  vim.api.nvim_win_set_cursor(0, { 6, 0 })
  sidebar.snap()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  eq(true, lnum == 5 or lnum == 3, "on a thread name line (got " .. lnum .. ")")
end

function T.render_lists_all_threads()
  registry.threads[4] = { id = "d", name = "delta", status = "attention" }
  sidebar.render()
  local lines = table.concat(vim.api.nvim_buf_get_lines(sidebar.buf, 0, -1, false), "\n")
  for _, name in ipairs({ "alpha", "beta", "gamma", "delta" }) do
    eq(true, lines:find(name) ~= nil, name .. " listed")
  end
  registry.threads[4] = nil
end

return T
