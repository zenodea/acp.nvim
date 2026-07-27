---The details panel: a small window docked under the threads sidebar with
---the current tab's thread at a glance — its branch and diff, plan progress,
---running subagents, queued prompts, and context usage. The floats (gp plan,
---gs subagents, gq queue) hold the full picture; this is the always-visible
---summary of the same state.
local M = {}

local ns = vim.api.nvim_create_namespace("acp-details")

---@type integer|nil shared details buffer, shown in one window per thread tab
M.buf = nil

---Git facts per working directory. Renders read this cache and kick an async
---refresh when it goes stale, so no git call ever blocks a render.
---@type table<string, {branch: string|nil, ahead: integer|nil, behind: integer|nil, plus: integer, minus: integer, untracked: integer, at: integer}>
local git = {}
---@type table<string, boolean>
local pending = {}
local TTL = 5

---@param args string[]
---@param cb fun(ok: boolean, out: string)
local function sys(args, cb)
  vim.system(args, { text = true }, function(res)
    vim.schedule(function()
      cb(res.code == 0, vim.trim(res.stdout or ""))
    end)
  end)
end

---Refill the cache for `cwd`: branch, working-tree diff, untracked count,
---and — for worktrees — commit counts against the main checkout's branch.
---@param cwd string
---@param is_worktree boolean
local function refresh(cwd, is_worktree)
  if pending[cwd] then
    return
  end
  pending[cwd] = true
  local info = { plus = 0, minus = 0, untracked = 0 }
  local function finish()
    info.at = os.time()
    git[cwd] = info
    pending[cwd] = nil
    M.render()
  end
  sys({ "git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD" }, function(ok, branch)
    if not ok or branch == "" then
      -- Not a repo (or the directory is gone): cache the miss so the git
      -- lines are skipped instead of re-probed on every render.
      return finish()
    end
    info.branch = branch
    sys({ "git", "-C", cwd, "diff", "--shortstat", "HEAD" }, function(_, stat)
      info.plus = tonumber(stat:match("(%d+) insertion")) or 0
      info.minus = tonumber(stat:match("(%d+) deletion")) or 0
      sys({ "git", "-C", cwd, "ls-files", "--others", "--exclude-standard" }, function(ok2, untracked)
        if ok2 and untracked ~= "" then
          info.untracked = #require("acp.util").lines(untracked)
        end
        local root = require("acp.core.registry").root
        if not is_worktree or not root then
          return finish()
        end
        sys({ "git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD" }, function(ok3, base)
          if not ok3 or base == "" or base == branch then
            return finish()
          end
          sys({ "git", "-C", cwd, "rev-list", "--left-right", "--count", base .. "...HEAD" }, function(ok4, counts)
            if ok4 then
              local behind, ahead = counts:match("^(%d+)%s+(%d+)$")
              info.behind, info.ahead = tonumber(behind), tonumber(ahead)
            end
            finish()
          end)
        end)
      end)
    end)
  end)
end

---@param entry table subagent entry (see acp.ui.subagents)
---@return string
local function duration(entry)
  local secs = os.time() - (entry.started or os.time())
  if secs < 60 then
    return secs .. "s"
  end
  return ("%dm%02ds"):format(math.floor(secs / 60), secs % 60)
end

---@return integer
function M.ensure_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end
  M.buf = require("acp.util").scratch_buf("acp://details", { filetype = "acp-details" })
  vim.bo[M.buf].modifiable = false
  return M.buf
end

---Repaint the panel for the current tab's thread. A no-op when the panel is
---not on screen or the current tab is not a thread workspace — background
---tabs are repainted by the TabEnter autocmd when they come back.
function M.render()
  local buf = M.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local wins = vim.fn.win_findbuf(buf)
  if #wins == 0 then
    return
  end
  local thread = require("acp.core.registry").find_by_tab(vim.api.nvim_get_current_tabpage())
  if not thread then
    return
  end

  local util = require("acp.util")
  -- All panel windows share the sidebar column, so any one's width will do.
  local width = math.max(vim.api.nvim_win_get_width(wins[1]) - 4, 10)

  local info = git[thread.cwd]
  if not info or os.time() - info.at > TTL then
    refresh(thread.cwd, thread.worktree ~= nil)
  end

  local lines, marks = {}, {}
  ---@param text string
  ---@param hl string|nil
  ---@param end_col integer|nil hl the first end_col bytes instead of the line
  local function add(text, hl, end_col)
    table.insert(lines, text)
    if hl then
      table.insert(marks, { #lines - 1, hl, end_col })
    end
  end

  if not info then
    add(" ⎇ …", "AcpSidebarHint")
  elseif info.branch then
    add(" ⎇ " .. util.shorten(info.branch, width), "AcpSidebarGroup")
    local parts = {}
    if (info.ahead or 0) > 0 then
      table.insert(parts, "⇡" .. info.ahead)
    end
    if (info.behind or 0) > 0 then
      table.insert(parts, "⇣" .. info.behind)
    end
    if info.plus > 0 or info.minus > 0 then
      table.insert(parts, ("+%d −%d"):format(info.plus, info.minus))
    end
    if info.untracked > 0 then
      table.insert(parts, info.untracked .. " new")
    end
    add("   " .. (#parts > 0 and table.concat(parts, " · ") or "clean"), "AcpSidebarHint")
  end

  local done, total = require("acp.ui.plan").progress(thread)
  if total > 0 then
    add((" ▤ plan %d/%d"):format(done, total))
    for _, e in ipairs(thread.plan or {}) do
      if e.status == "in_progress" then
        add("   " .. util.shorten(e.content or "", width), "AcpPlanActive")
        break
      end
    end
  end

  local shown, extra = 0, 0
  for _, entry in ipairs(thread.subagents or {}) do
    if entry.status == "pending" or entry.status == "in_progress" then
      if shown < 3 then
        local label = util.shorten(entry.title or "subagent", width - 8)
        add((" ◇ %s · %s"):format(label, duration(entry)), "AcpStatusWorking", #" ◇")
        shown = shown + 1
      else
        extra = extra + 1
      end
    end
  end
  if extra > 0 then
    add(("   … %d more running"):format(extra), "AcpSidebarHint")
  end

  local queue = (thread.session and thread.session.queue) or {}
  if #queue > 0 then
    add((" ⧗ %d queued"):format(#queue))
  end
  local usage = require("acp.agent.events").usage_text(thread.usage)
  if usage then
    add(" " .. usage .. " of context")
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks) do
    local lnum, group, end_col = m[1], m[2], m[3]
    if end_col then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = end_col, hl_group = group })
    else
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = group })
    end
  end
end

return M
