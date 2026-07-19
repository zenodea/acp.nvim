if vim.g.loaded_agent_flow then
  return
end
vim.g.loaded_agent_flow = 1

vim.api.nvim_create_user_command("AgentFlow", function()
  require("agent-flow").open()
end, { desc = "Open the last active agent thread (or create one)" })

vim.api.nvim_create_user_command("AgentFlowNew", function(cmd)
  require("agent-flow").new(cmd.args ~= "" and cmd.args or nil)
end, { nargs = "?", desc = "Create a new agent thread" })

vim.api.nvim_create_user_command("AgentFlowToggleChat", function()
  require("agent-flow").toggle_chat()
end, { desc = "Show/hide the chat column of the current thread" })

vim.api.nvim_create_user_command("AgentFlowInterrupt", function()
  require("agent-flow").interrupt()
end, { desc = "Interrupt the current thread's turn" })
