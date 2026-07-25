---The plan panel (gp): the agent's current plan in a read-only float, with
---the step being worked on accented and finished steps dimmed.
---
---The transcript keeps every plan where it landed, which scrolls away as the
---turn goes on; the panel always shows the latest one, and the chat winbar
---carries the step count so progress is visible without opening anything.
local M = {}

local ns = vim.api.nvim_create_namespace("acp-plan")

local step_hl = {
  in_progress = "AcpPlanActive",
  completed = "AcpChatMeta",
}

---Completed steps and total for a thread's current plan.
---@param thread Thread
---@return integer done
---@return integer total
function M.progress(thread)
  local entries = thread.plan or {}
  local done = 0
  for _, e in ipairs(entries) do
    if e.status == "completed" then
      done = done + 1
    end
  end
  return done, #entries
end

---Open the current plan in a float. q or :q closes it.
---@param thread Thread
function M.open(thread)
  local entries = thread.plan or {}
  if #entries == 0 then
    vim.notify("acp: this thread has no plan yet", vim.log.levels.INFO)
    return
  end
  local icons = require("acp.agent.events").plan_icons
  local lines, groups = {}, {}
  for i, e in ipairs(entries) do
    lines[i] = string.format(" %s %s", icons[e.status] or icons.pending, e.content or "")
    groups[i] = step_hl[e.status]
  end

  local util = require("acp.util")
  local buf = util.scratch_buf(nil, { bufhidden = "wipe" })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local done, total = M.progress(thread)
  local win = util.centered_float(buf, {
    lines = #lines,
    title = (" plan — %d/%d done · q closes "):format(done, total),
  })
  -- Steps are sentences, not code: wrap them rather than truncating.
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  -- Only the accented statuses land in `groups`, so pairs (not ipairs).
  for i, group in pairs(groups) do
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { line_hl_group = group, priority = 90 })
  end
  vim.keymap.set("n", "q", function()
    pcall(vim.api.nvim_win_close, win, true)
  end, { buffer = buf, nowait = true, desc = "Close the plan panel" })
end

return M
