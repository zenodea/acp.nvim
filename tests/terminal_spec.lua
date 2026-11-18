local h = require("tests.helpers")
local eq = h.eq

local terminal = require("acp.agent.terminal")

local T = {}

---Wait for a terminal to exit and return its exit status.
---@param id string
---@return table|nil exit
local function wait_exit(id)
  local exit
  terminal.wait_for_exit(id, function(e)
    exit = e
  end)
  vim.wait(5000, function()
    return exit ~= nil
  end)
  return exit
end

function T.release_preserves_output_for_rendering()
  local id = terminal.create({ command = "echo", args = { "preserved" }, cwd = "/tmp" }, "/tmp", function() end)
  local exit = wait_exit(id)
  eq(0, exit.exitCode)
  terminal.release(id)
  -- ACP spec: output must remain visible after release.
  local lines = terminal.render_lines(id, 100)
  eq(true, #lines > 0, "render_lines returns output after release")
  eq(true, table.concat(lines, "\n"):find("preserved", 1, true) ~= nil, "output preserved after release")
end

function T.release_preserves_output_for_output_call()
  local id = terminal.create({ command = "echo", args = { "still_here" }, cwd = "/tmp" }, "/tmp", function() end)
  local exit = wait_exit(id)
  eq(0, exit.exitCode)
  terminal.release(id)
  local out = terminal.output(id)
  eq(true, out ~= nil, "output() works after release")
  eq(true, out.output:find("still_here", 1, true) ~= nil, "output content preserved after release")
end

return T
