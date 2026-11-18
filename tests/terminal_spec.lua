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

function T.shell_command_string_runs_through_sh()
  local id = terminal.create({ command = "echo hello", cwd = "/tmp" }, "/tmp", function() end)
  eq(true, id ~= nil, "terminal created")
  local exit = wait_exit(id)
  eq(0, exit.exitCode, "echo exits 0")
  local out = terminal.output(id)
  eq(true, out.output:find("hello", 1, true) ~= nil, "output contains hello")
  terminal.release(id)
end

function T.shell_operators_work_without_args()
  local id = terminal.create({ command = "echo a && echo b", cwd = "/tmp" }, "/tmp", function() end)
  eq(true, id ~= nil, "terminal created with && operator")
  local exit = wait_exit(id)
  eq(0, exit.exitCode, "compound command exits 0")
  local out = terminal.output(id)
  eq(true, out.output:find("a", 1, true) ~= nil, "output has first command result")
  eq(true, out.output:find("b", 1, true) ~= nil, "output has second command result")
  terminal.release(id)
end

function T.pipes_work_without_args()
  local id = terminal.create({ command = "printf 'x\\ny\\n' | grep y", cwd = "/tmp" }, "/tmp", function() end)
  eq(true, id ~= nil, "terminal created with pipe")
  local exit = wait_exit(id)
  eq(0, exit.exitCode, "grep exits 0")
  local out = terminal.output(id)
  eq(true, out.output:find("y", 1, true) ~= nil, "output has piped result")
  terminal.release(id)
end

function T.binary_with_args_still_works()
  local id = terminal.create({ command = "printf", args = { "hello\\n" }, cwd = "/tmp" }, "/tmp", function() end)
  eq(true, id ~= nil, "terminal created with binary + args")
  local exit = wait_exit(id)
  eq(0, exit.exitCode, "printf exits 0")
  local out = terminal.output(id)
  eq(true, out.output:find("hello", 1, true) ~= nil, "output has printf result")
  terminal.release(id)
end

function T.invalid_binary_with_args_returns_error()
  local id, err = terminal.create(
    { command = "this-binary-does-not-exist-12345", args = { "--flag" } },
    "/tmp",
    function() end
  )
  eq(true, id == nil, "no terminal id for invalid binary")
  eq(true, err ~= nil, "error message returned")
  eq(true, tostring(err):find("failed to spawn", 1, true) ~= nil, "error mentions spawn failure")
end

function T.invalid_command_in_shell_exits_nonzero()
  local id = terminal.create({ command = "this-binary-does-not-exist-12345" }, "/tmp", function() end)
  eq(true, id ~= nil, "sh -c spawns even for invalid inner command")
  local exit = wait_exit(id)
  eq(true, exit.exitCode ~= 0, "inner command failure exits non-zero")
  terminal.release(id)
end

function T.cd_chains_work_without_args()
  local id = terminal.create({ command = "cd /tmp && pwd" }, "/tmp", function() end)
  eq(true, id ~= nil, "terminal created with cd chain")
  local exit = wait_exit(id)
  eq(0, exit.exitCode, "cd + pwd exits 0")
  local out = terminal.output(id)
  eq(true, out.output:find("/tmp", 1, true) ~= nil, "output has pwd result")
  terminal.release(id)
end

return T
