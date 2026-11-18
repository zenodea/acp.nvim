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
  ui({ diff_context = 2 })
  local old = table.concat({ "a", "b", "c", "d", "e", "f", "g", "h" }, "\n")
  local new = table.concat({ "a", "b", "c", "X", "e", "f", "g", "h" }, "\n")
  eq({ "⋯", "  b", "  c", "- d", "+ X", "  e", "  f", "⋯" }, diff(old, new))
end

function T.diff_insertion()
  ui({ diff_context = 2 })
  eq({ "  a", "  b", "+ INS", "  c" }, diff("a\nb\nc", "a\nb\nINS\nc"))
end

function T.diff_deletion()
  ui({ diff_context = 1 })
  eq({ "  a", "- b", "  c" }, diff("a\nb\nc", "a\nc"))
end

function T.diff_new_file_is_all_additions()
  ui({})
  eq({ "+ x", "+ y" }, diff("", "x\ny"))
end

function T.diff_identical_text_renders_nothing()
  ui({})
  eq({}, diff("a\nb", "a\nb"))
end

function T.diff_is_never_truncated()
  -- Expanding a tool call means you want to read the change, so the whole
  -- diff renders however long it is.
  ui({ diff_context = 0, terminal_max_lines = 4 })
  local big = {}
  for i = 1, 300 do
    big[i] = tostring(i)
  end
  local lines = diff("", table.concat(big, "\n"))
  eq(300, #lines)
  eq("+ 1", lines[1])
  eq("+ 300", lines[300])
  eq(nil, table.concat(lines, "\n"):find("more lines", 1, true), "no truncation marker")
end

function T.diff_gap_between_hunks_marked()
  ui({ diff_context = 2 })
  local old_t = {}
  for i = 1, 12 do
    old_t[i] = "L" .. i
  end
  local new_t = vim.deepcopy(old_t)
  new_t[2] = "X"
  new_t[11] = "Y"
  eq({
    "  L1",
    "- L2",
    "+ X",
    "  L3",
    "  L4",
    "⋯",
    "  L9",
    "  L10",
    "- L11",
    "+ Y",
    "  L12",
  }, diff(table.concat(old_t, "\n"), table.concat(new_t, "\n")))
end

function T.diff_close_hunks_do_not_duplicate_context()
  ui({ diff_context = 3 })
  eq(
    { "  a", "- b", "+ B", "  c", "- d", "+ D", "  e" },
    diff(table.concat({ "a", "b", "c", "d", "e" }, "\n"), table.concat({ "a", "B", "c", "D", "e" }, "\n"))
  )
end

function T.diff_trailing_gap_marked()
  ui({ diff_context = 1 })
  local lines =
    diff(table.concat({ "a", "b", "c", "d", "e", "f" }, "\n"), table.concat({ "a", "X", "c", "d", "e", "f" }, "\n"))
  eq({ "  a", "- b", "+ X", "  c", "⋯" }, lines)
end

function T.diff_disabled_renders_nothing()
  ui({ show_diffs = false })
  eq({}, diff("a", "b"))
  ui({ show_diffs = true })
end

function T.content_item_is_indented()
  ui({})
  local lines = events.tool_content_lines({ { type = "content", content = { type = "text", text = "hello" } } })
  eq({ "  hello" }, lines)
end

function T.tool_text_status_suffix()
  ui({})
  eq("thing ✗", events.tool_text({ title = "thing", status = "failed" }))
  -- Unfinished calls carry no suffix: the chat spins a glyph next to them.
  eq("thing", events.tool_text({ title = "thing", status = "pending" }))
  eq("thing", events.tool_text({ title = "thing", status = "in_progress" }))
  eq("thing", events.tool_text({ title = "thing", status = "completed" }))
end

function T.usage_gauge_fills_with_the_context_window()
  local function g(used, size)
    return events.usage_text({ used = used, size = size })
  end
  eq("○ 0%", g(0, 200000))
  eq("○ 10%", g(20000, 200000))
  eq("◔ 21%", g(42000, 200000))
  eq("◑ 50%", g(100000, 200000))
  eq("◕ 75%", g(150000, 200000))
  eq("● 100%", g(200000, 200000))
  -- Agents may report more used than the window after a compaction race.
  eq("● 100%", g(250000, 200000), "clamped at 100")
end

function T.usage_gauge_is_absent_without_usable_numbers()
  eq(nil, events.usage_text(nil), "no usage reported yet")
  eq(nil, events.usage_text({ used = 10 }), "no window size")
  eq(nil, events.usage_text({ used = 10, size = 0 }), "zero window size")
end

function T.plan_text_step_glyphs()
  local text = events.plan_text({
    { status = "completed", content = "done step" },
    { status = "in_progress", content = "active step" },
    { status = "pending", content = "todo step" },
  })
  eq("Plan:\n  ✓ done step\n  ◐ active step\n  ○ todo step", text)
end

function T.content_text_extracts_resource_text()
  local text = events.content_text({
    type = "resource",
    resource = { uri = "file:///tmp/script.sh", mimeType = "text/x-shellscript", text = "echo hello" },
  })
  eq("echo hello", text)
end

function T.content_text_resource_without_text_returns_empty()
  local text = events.content_text({
    type = "resource",
    resource = { uri = "file:///tmp/binary.dat", mimeType = "application/octet-stream" },
  })
  eq("", text)
end

function T.tool_content_lines_renders_resource_content()
  ui({ show_diffs = true })
  local lines = events.tool_content_lines({
    {
      type = "content",
      content = {
        type = "resource",
        resource = { uri = "file:///tmp/cmd.sh", mimeType = "text/x-shellscript", text = "cd /tmp && ls" },
      },
    },
  })
  eq({ "  cd /tmp && ls" }, lines)
end

function T.tool_text_shows_command_from_rawInput()
  ui({ show_diffs = true })
  local text = events.tool_text({
    title = "Ran command",
    kind = "execute",
    status = "completed",
    rawInput = { command = "cd /tmp && git log --oneline" },
    content = { { type = "content", content = { type = "text", text = "Exited with code 0" } } },
  })
  eq(true, text:find("$ cd /tmp && git log --oneline", 1, true) ~= nil, "command shown: " .. text)
  eq(true, text:find("Exited with code 0", 1, true) ~= nil, "content shown without terminal: " .. text)
end

function T.tool_text_shows_terminal_output_for_execute()
  ui({ show_diffs = true })
  local terminal = require("acp.agent.terminal")
  local id = terminal.create({ command = "echo", args = { "hello_world" }, cwd = "/tmp" }, "/tmp", function() end)
  -- Wait for exit.
  local exit
  terminal.wait_for_exit(id, function(e)
    exit = e
  end)
  vim.wait(5000, function()
    return exit ~= nil
  end)
  local text = events.tool_text({
    title = "Ran command",
    kind = "execute",
    status = "completed",
    terminal_id = id,
    rawInput = { command = "echo hello_world" },
    content = { { type = "content", content = { type = "text", text = "Exited with code 0" } } },
  })
  terminal.release(id)
  eq(true, text:find("hello_world", 1, true) ~= nil, "terminal output shown: " .. text)
  eq(true, text:find("$ echo hello_world", 1, true) ~= nil, "command shown: " .. text)
  eq(true, text:find("Exited with code", 1, true) == nil, "redundant exit text filtered: " .. text)
end

function T.tool_text_does_not_show_command_for_non_execute()
  ui({ show_diffs = true })
  local text = events.tool_text({
    title = "Edited file.lua",
    kind = "edit",
    status = "completed",
    rawInput = { command = "should not appear" },
    content = {},
  })
  eq(true, text:find("should not appear", 1, true) == nil, "no command prefix for edit: " .. text)
end

return T
