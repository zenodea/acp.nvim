local h = require("tests.helpers")
local eq = h.eq

local events = require("acp.agent.events")
local config = require("acp.config")

local function ui(opts)
  config.setup({})
  config.options.ui = vim.tbl_deep_extend("force", config.options.ui, opts or {})
end

local function diff(old, new)
  return events.tool_content_lines({ { type = "diff", oldText = old, newText = new } })
end

local T = {}

function T.diff_single_line_change_renders_one_hunk()
  ui({ diff_context = 2, diff_max_lines = 24 })
  local old = table.concat({ "a", "b", "c", "d", "e", "f", "g", "h" }, "\n")
  local new = table.concat({ "a", "b", "c", "X", "e", "f", "g", "h" }, "\n")
  eq({ "  b", "  c", "- d", "+ X", "  e", "  f" }, diff(old, new))
end

function T.diff_insertion()
  ui({ diff_context = 2, diff_max_lines = 24 })
  eq({ "  a", "  b", "+ INS", "  c" }, diff("a\nb\nc", "a\nb\nINS\nc"))
end

function T.diff_deletion()
  ui({ diff_context = 1, diff_max_lines = 24 })
  eq({ "  a", "- b", "  c" }, diff("a\nb\nc", "a\nc"))
end

function T.diff_new_file_is_all_additions()
  ui({ diff_max_lines = 24 })
  eq({ "+ x", "+ y" }, diff("", "x\ny"))
end

function T.diff_identical_text_renders_nothing()
  ui({ diff_max_lines = 24 })
  eq({}, diff("a\nb", "a\nb"))
end

function T.diff_truncates_beyond_max_lines()
  ui({ diff_context = 0, diff_max_lines = 4 })
  local new = table.concat({ "1", "2", "3", "4", "5", "6", "7", "8" }, "\n")
  local lines = diff("", new)
  eq(5, #lines)
  eq("… (4 more lines)", lines[5])
end

function T.diff_disabled_renders_nothing()
  ui({ show_diffs = false })
  eq({}, diff("a", "b"))
  ui({ show_diffs = true })
end

function T.content_item_is_indented()
  ui({ diff_max_lines = 24 })
  local lines = events.tool_content_lines({ { type = "content", content = { type = "text", text = "hello" } } })
  eq({ "  hello" }, lines)
end

function T.tool_text_status_suffix()
  ui({ diff_max_lines = 24 })
  eq("thing ✗", events.tool_text({ title = "thing", status = "failed" }))
  eq("thing …", events.tool_text({ title = "thing", status = "pending" }))
  eq("thing", events.tool_text({ title = "thing", status = "completed" }))
end

function T.plan_text_step_glyphs()
  local text = events.plan_text({
    { status = "completed", content = "done step" },
    { status = "in_progress", content = "active step" },
    { status = "pending", content = "todo step" },
  })
  eq("Plan:\n  ● done step\n  ◐ active step\n  ○ todo step", text)
end

return T
