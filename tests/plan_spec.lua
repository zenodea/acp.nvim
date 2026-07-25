local h = require("tests.helpers")
local eq = h.eq

local plan = require("acp.ui.plan")

local ENTRIES = {
  { content = "Read the spec", status = "completed" },
  { content = "Write the parser", status = "in_progress" },
  { content = "Add tests", status = "pending" },
}

---@param entries table[]|nil
local function thread_with(entries)
  local thread = h.thread("plan-test")
  thread.plan = entries
  return thread
end

local T = {}

function T.progress_counts_completed_steps()
  eq({ 1, 3 }, { plan.progress(thread_with(ENTRIES)) })
end

function T.progress_is_zero_without_a_plan()
  eq({ 0, 0 }, { plan.progress(thread_with(nil)) })
end

function T.panel_lists_every_step_with_its_glyph()
  plan.open(thread_with(ENTRIES))
  eq("editor", vim.api.nvim_win_get_config(0).relative, "plan opens in a float")
  eq({
    " ✓ Read the spec",
    " ◐ Write the parser",
    " ○ Add tests",
  }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  eq(true, vim.api.nvim_win_get_config(0).title[1][1]:find("1/3 done", 1, true) ~= nil, "title shows progress")
  vim.cmd("normal q")
  eq("", vim.api.nvim_win_get_config(0).relative, "q closes the float")
end

function T.panel_accents_the_step_in_progress()
  plan.open(thread_with(ENTRIES))
  local ns = vim.api.nvim_get_namespaces()["acp-plan"]
  local marks = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
    marks[m[2]] = m[4].line_hl_group
  end
  -- Done steps dim, the in-progress step is accented, pending stays plain.
  eq({ [0] = "AcpChatMeta", [1] = "AcpPlanActive" }, marks)
  vim.cmd("normal q")
end

function T.empty_plan_notifies_instead_of_opening()
  local notified
  local orig = vim.notify
  vim.notify = function(msg)
    notified = msg
  end
  plan.open(thread_with({}))
  vim.notify = orig
  eq("", vim.api.nvim_win_get_config(0).relative, "no float opened")
  eq(true, notified ~= nil and notified:find("no plan", 1, true) ~= nil, "notified: " .. tostring(notified))
end

return T
