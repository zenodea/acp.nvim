local M = {}

function M.check()
  local health = vim.health
  local util = require("acp.util")
  local cfg = require("acp.config").options

  health.start("acp")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim >= 0.10")
  else
    health.error("Neovim 0.10+ required (vim.system, extmark APIs)")
  end

  if vim.fn.executable(cfg.claude.cmd) == 1 then
    local ok, out = util.system({ cfg.claude.cmd, "--version" })
    if ok then
      health.ok("claude CLI found: " .. out)
    else
      health.warn("claude CLI found but --version failed: " .. out)
    end
    health.info(
      "streaming permission prompts (permissions = \"prompt\") need a recent CLI; "
        .. "if spawning fails, set claude.permissions to \"acceptEdits\" or \"default\""
    )
  else
    health.error("claude CLI not found (config: claude.cmd = " .. cfg.claude.cmd .. ")", {
      "install Claude Code: https://docs.anthropic.com/en/docs/claude-code",
    })
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
