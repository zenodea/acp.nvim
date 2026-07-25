local h = require("tests.helpers")
local eq = h.eq

local subagents = require("acp.ui.subagents")

---@return table thread
local function thread()
  local t = h.thread("subagent-test")
  t.subagents = nil
  return t
end

local T = {}

function T.titles_are_matched_on_word_boundaries()
  eq(true, subagents.is_subagent("Task: hunt the flaky test"), "Task")
  eq(true, subagents.is_subagent("Explore the config loader"), "Explore")
  eq(true, subagents.is_subagent("run a subagent"), "subagent anywhere")
  eq(false, subagents.is_subagent("Taskbar tweaks"), "Taskbar is not Task")
  eq(false, subagents.is_subagent("Edit foo.lua"), "ordinary tool call")
  eq(false, subagents.is_subagent(nil), "missing title")
end

function T.track_ignores_calls_that_are_not_subagents()
  local t = thread()
  eq(false, subagents.track(t, "t1", "Edit foo.lua", "in_progress"))
  eq(nil, t.subagents, "nothing recorded")
end

function T.track_records_a_spawn_then_follows_its_status()
  local t = thread()
  eq(true, subagents.track(t, "t1", "Task: find the bug", "in_progress"))
  eq(1, #t.subagents)
  eq(1, subagents.running(t), "counts as running")
  -- The update carries no title of its own; the recorded one survives.
  eq(true, subagents.track(t, "t1", nil, "completed"))
  eq(1, #t.subagents, "same spawn, not a second row")
  eq("Task: find the bug", t.subagents[1].title)
  eq(0, subagents.running(t), "no longer running")
  eq(true, t.subagents[1].ended ~= nil, "runtime frozen at completion")
end

function T.finished_runtime_is_not_stretched_by_later_updates()
  local t = thread()
  subagents.track(t, "t1", "Task: build", "completed")
  local ended = t.subagents[1].ended
  t.subagents[1].ended = ended - 30 -- pretend it finished 30s ago
  subagents.track(t, "t1", "Task: build", "completed")
  eq(ended - 30, t.subagents[1].ended)
end

function T.panel_lists_spawns_with_status_and_runtime()
  local t = thread()
  subagents.track(t, "t1", "Task: find the bug", "completed")
  subagents.track(t, "t2", "Explore the loader", "in_progress")
  t.subagents[1].started = t.subagents[1].ended - 8
  t.subagents[2].started = os.time() - 90

  subagents.open(t)
  eq("editor", vim.api.nvim_win_get_config(0).relative, "opens in a float")
  eq({
    " ✓ Task: find the bug  done · 8s",
    " ◐ Explore the loader  running · 1m30s",
  }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  eq(
    true,
    vim.api.nvim_win_get_config(0).title[1][1]:find("1 of 2 running", 1, true) ~= nil,
    "title counts the running ones"
  )
  vim.cmd("normal q")
  eq("", vim.api.nvim_win_get_config(0).relative, "q closes the float")
end

function T.panel_colours_the_status_glyph_and_dims_the_meta()
  local t = thread()
  subagents.track(t, "t1", "Task: find the bug", "failed")
  subagents.open(t)
  local ns = vim.api.nvim_get_namespaces()["acp-subagents"]
  local found = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
    table.insert(found, m[4].hl_group)
  end
  table.sort(found)
  eq({ "AcpChatMeta", "AcpStatusError" }, found)
  vim.cmd("normal q")
end

function T.empty_list_notifies_instead_of_opening()
  local notified
  local orig = vim.notify
  vim.notify = function(msg)
    notified = msg
  end
  subagents.open(thread())
  vim.notify = orig
  eq("", vim.api.nvim_win_get_config(0).relative, "no float opened")
  eq(true, notified ~= nil and notified:find("no subagents", 1, true) ~= nil, "notified: " .. tostring(notified))
end

return T
