local h = require("tests.helpers")
local eq = h.eq

h.stub("acp.ui.workspace", {
  update_input_winbar = function() end,
  update_winbar = function() end,
})
local session = require("acp.agent.session")

local SEP = string.rep("─", 40)
local n = 0

---A session with the given queue and its editor buffer open.
local function open_editor(queue)
  n = n + 1
  local s = session.get(h.thread("queue-test-" .. n))
  s.queue = queue
  s:edit_queue()
  return s, vim.fn.bufnr("acp://queue/queue-test-" .. n)
end

local function set_lines(buf, lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false -- API edits may not fire the TextChanged reset
end

local T = {}

function T.editor_shows_prompts_separated()
  local _, buf = open_editor({ "one", "two\nlines" })
  eq({ "one", SEP, "two", "lines" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
end

function T.close_applies_edits_reorder_and_delete()
  local s, buf = open_editor({ "first", "second", "third" })
  set_lines(buf, { "third", SEP, "first EDITED" })
  vim.cmd("close")
  eq({ "third", "first EDITED" }, s.queue)
end

function T.write_applies_without_closing()
  local s, buf = open_editor({ "alpha", "beta" })
  set_lines(buf, { "beta", SEP, "alpha" })
  vim.cmd("write")
  eq({ "beta", "alpha" }, s.queue)
  eq("editor", vim.api.nvim_win_get_config(0).relative)
  vim.cmd("close")
end

function T.prompt_flushed_while_open_is_not_requeued()
  local s, _ = open_editor({ "first", "second" })
  s.busy = false
  s.prompt = function() end -- sends "first"
  s:flush_queue()
  vim.cmd("close")
  eq({ "second" }, s.queue)
end

function T.markdown_rule_is_not_a_separator()
  local s, _ = open_editor({ "above\n---\nbelow" })
  vim.cmd("close")
  eq({ "above\n---\nbelow" }, s.queue)
end

function T.blank_edges_are_trimmed_blank_blocks_dropped()
  local s, buf = open_editor({ "keep" })
  set_lines(buf, { "", "keep", "", SEP, "   ", SEP, "also" })
  vim.cmd("close")
  eq({ "keep", "also" }, s.queue)
end

function T.empty_queue_notifies_instead_of_opening()
  local s = session.get(h.thread("queue-empty"))
  s.queue = {}
  s:edit_queue()
  eq(1, #vim.api.nvim_list_wins())
end

return T
