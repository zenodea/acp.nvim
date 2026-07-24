local h = require("tests.helpers")
local eq = h.eq

local registry = h.stub("acp.core.registry", {
  threads = {
    { id = "a", name = "alpha", status = "idle" },
    { id = "b", name = "beta", status = "working" },
    { id = "c", name = "gamma", status = "idle", worktree = { path = "/repo/.worktrees/feat-x", branch = "feat/x" } },
  },
})
local sidebar = require("acp.ui.sidebar")

local function lines()
  return vim.api.nvim_buf_get_lines(sidebar.buf, 0, -1, false)
end

---1-based line holding `text`.
local function line_of(text)
  for i, l in ipairs(lines()) do
    if l:find(text, 1, true) then
      return i
    end
  end
  error("no line containing " .. text)
end

local T = {}

function T.threads_grouped_by_worktree_with_spacing()
  sidebar.render()
  local checkout = line_of("checkout")
  local featx = line_of("feat-x")
  eq(true, checkout < line_of("alpha"), "main threads under checkout header")
  eq(true, line_of("beta") < featx, "worktree group after main group")
  eq(true, featx < line_of("gamma"), "worktree thread under its header")
  eq("", lines()[featx - 1], "blank line before the worktree group")
end

function T.working_thread_shows_spinner_frame()
  sidebar.render()
  local beta = lines()[line_of("beta")]
  local spins = false
  for _, f in ipairs(require("acp.util").spinner) do
    spins = spins or beta:find(f, 1, true) ~= nil
  end
  eq(true, spins, "working icon is a spinner frame: " .. beta)
end

function T.reveal_moves_every_sidebar_window()
  sidebar.render()
  vim.api.nvim_win_set_buf(0, sidebar.buf)
  vim.cmd("vsplit")
  local wins = vim.fn.win_findbuf(sidebar.buf)
  eq(2, #wins)
  vim.api.nvim_win_set_cursor(wins[1], { line_of("alpha"), 0 })
  vim.api.nvim_win_set_cursor(wins[2], { line_of("beta"), 0 })
  sidebar.reveal("c")
  local target = line_of("gamma")
  eq(target, vim.api.nvim_win_get_cursor(wins[1])[1], "gamma line")
  eq(target, vim.api.nvim_win_get_cursor(wins[2])[1], "gamma line")
end

function T.reveal_unknown_id_is_noop()
  sidebar.render()
  vim.api.nvim_win_set_buf(0, sidebar.buf)
  local start = line_of("beta")
  vim.api.nvim_win_set_cursor(0, { start, 0 })
  sidebar.reveal("does-not-exist")
  eq(start, vim.api.nvim_win_get_cursor(0)[1])
end

function T.snap_keeps_cursor_on_thread_names()
  sidebar.render()
  vim.api.nvim_win_set_buf(0, sidebar.buf)
  vim.api.nvim_win_set_cursor(0, { line_of("alpha"), 0 })
  vim.cmd("doautocmd CursorMoved")
  -- A group header is not a cursor target: snapping pulls the cursor off it.
  vim.api.nvim_win_set_cursor(0, { line_of("feat-x"), 0 })
  sidebar.snap()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local on_name = lnum == line_of("alpha") or lnum == line_of("beta") or lnum == line_of("gamma")
  eq(true, on_name, "on a thread name line (got " .. lnum .. ")")
end

function T.render_lists_all_threads()
  registry.threads[4] = { id = "d", name = "delta", status = "attention" }
  sidebar.render()
  local all = table.concat(lines(), "\n")
  for _, name in ipairs({ "alpha", "beta", "gamma", "delta" }) do
    eq(true, all:find(name) ~= nil, name .. " listed")
  end
  registry.threads[4] = nil
end

return T
