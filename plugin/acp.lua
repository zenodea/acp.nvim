if vim.g.loaded_acp then
  return
end
vim.g.loaded_acp = 1

vim.api.nvim_create_user_command("Acp", function()
  require("acp").open()
end, { desc = "Open the last active agent thread (or create one)" })

vim.api.nvim_create_user_command("AcpNew", function(cmd)
  require("acp").new(cmd.args ~= "" and cmd.args or nil)
end, { nargs = "?", desc = "Create a new agent thread" })

vim.api.nvim_create_user_command("AcpToggleChat", function()
  require("acp").toggle_chat()
end, { desc = "Show/hide the chat column of the current thread" })

vim.api.nvim_create_user_command("AcpInterrupt", function()
  require("acp").interrupt()
end, { desc = "Interrupt the current thread's turn" })
