local h = require("tests.helpers")
local eq = h.eq

-- The real registry: stubbing it here would leak into later specs
-- (init_spec uses the real one), so tests add and remove their own threads.
local registry = require("acp.core.registry")
local details = require("acp.ui.details")

local function lines()
  return vim.api.nvim_buf_get_lines(details.buf, 0, -1, false)
end

local function has_line(text)
  for _, l in ipairs(lines()) do
    if l:find(text, 1, true) then
      return true
    end
  end
  return false
end

---Register `t` as the current tab's thread and show the panel buffer.
local function open(t)
  t.id = t.id or "t"
  t.cwd = t.cwd or vim.fn.tempname() -- no repo: the git lines stay out
  t.tabpage = vim.api.nvim_get_current_tabpage()
  table.insert(registry.threads, t)
  vim.api.nvim_win_set_buf(0, details.ensure_buf())
  return t
end

local function cleanup(t)
  for i, other in ipairs(registry.threads) do
    if other == t then
      table.remove(registry.threads, i)
      break
    end
  end
end

local T = {}

function T.render_shows_plan_step_queue_and_usage()
  local t = open({
    plan = {
      { status = "completed", content = "read the code" },
      { status = "in_progress", content = "wire the panel" },
      { status = "pending", content = "test it" },
    },
    session = { queue = { "one", "two" } },
    usage = { used = 42, size = 200 },
  })
  details.render()
  eq(true, has_line("▤ plan 1/3"), "plan progress")
  eq(true, has_line("wire the panel"), "the in-progress step")
  eq(false, has_line("test it"), "pending steps stay in the gp float")
  eq(true, has_line("⧗ 2 queued"), "queue count")
  eq(true, has_line("21% of context"), "usage")
  cleanup(t)
end

function T.only_running_subagents_are_listed()
  local t = open({
    subagents = {
      { id = "1", title = "Task: explore the code", status = "in_progress", started = os.time() - 5 },
      { id = "2", title = "Task: already done", status = "completed", started = os.time() - 60, ended = os.time() },
    },
  })
  details.render()
  eq(true, has_line("◇ Task: explore the code"), "running subagent listed")
  eq(false, has_line("Task: already done"), "finished subagent not listed")
  cleanup(t)
end

function T.no_thread_for_the_tab_leaves_the_panel_alone()
  local t = open({ usage = { used = 50, size = 100 } })
  details.render()
  eq(true, has_line("50% of context"))
  cleanup(t)
  -- With no thread in this tab a render must not clear another tab's
  -- content; TabEnter repaints when a thread tab comes back.
  details.render()
  eq(true, has_line("50% of context"), "content kept")
end

function T.git_line_shows_branch_and_untracked()
  local u = require("acp.util")
  local repo = vim.fn.tempname()
  vim.fn.mkdir(repo, "p")
  u.system({ "git", "-C", repo, "init", "-b", "main" })
  u.system({ "git", "-C", repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-m", "init" })
  vim.fn.writefile({ "hello" }, repo .. "/new.txt")

  local t = open({ cwd = repo })
  details.render() -- kicks the async git refresh
  local ok = vim.wait(4000, function()
    return has_line("⎇ main")
  end, 50)
  eq(true, ok, "branch line appears once git answers: " .. vim.inspect(lines()))
  eq(true, has_line("1 new"), "untracked count")
  cleanup(t)
  vim.fn.delete(repo, "rf")
end

return T
