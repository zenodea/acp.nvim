local M = {}

function M.check()
  local health = vim.health
  local util = require("acp.util")
  local cfg = require("acp.config").options

  health.start("acp")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10")
  else
    health.error("Neovim 0.10+ required")
  end

  local names = require("acp.config").agent_names()
  if #names == 0 then
    health.error("no ACP agents configured (config: agents = { ... })")
  end
  for _, name in ipairs(names) do
    local def = cfg.agents[name]
    local bin = def.cmd and def.cmd[1]
    if not bin then
      health.error("agent '" .. name .. "' has no cmd")
    elseif vim.fn.executable(bin) == 1 then
      health.ok(("agent '%s': %s"):format(name, table.concat(def.cmd, " ")))
      if bin == "npx" then
        health.info("agent '" .. name .. "' runs via npx — first spawn may be slow while the package downloads")
      end
    else
      health.error(("agent '%s': executable not found: %s"):format(name, bin))
    end
  end
  if cfg.agents.claude then
    health.info("the claude adapter uses your Claude Code login (run `claude` once to authenticate) or ANTHROPIC_API_KEY")
  end

  if vim.fn.executable("git") == 1 then
    local root = util.git_root(vim.fn.getcwd())
    if root then
      health.ok("git repository: " .. root .. " (worktrees available)")
    else
      health.warn("not inside a git repository — threads will share the cwd, no worktrees")
    end
  else
    health.warn("git not found — worktree support disabled")
  end
end

return M
