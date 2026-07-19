if vim.g.loaded_claude_agents then
  return
end
vim.g.loaded_claude_agents = 1

vim.api.nvim_create_user_command("ClaudeAgents", function()
  require("claude-agents").open()
end, { desc = "Open the last active agent thread (or create one)" })

vim.api.nvim_create_user_command("ClaudeAgentsNew", function(cmd)
  require("claude-agents").new(cmd.args ~= "" and cmd.args or nil)
end, { nargs = "?", desc = "Create a new agent thread" })

vim.api.nvim_create_user_command("ClaudeAgentsToggleChat", function()
  require("claude-agents").toggle_chat()
end, { desc = "Show/hide the chat column of the current thread" })

vim.api.nvim_create_user_command("ClaudeAgentsInterrupt", function()
  require("claude-agents").interrupt()
end, { desc = "Interrupt the current thread's turn" })
