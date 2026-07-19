local M = {}

---Render a permission request in the chat panel and arm y/n keymaps on the
---thread's chat + input buffers until it is answered.
---@param thread Thread
---@param pending {request_id: string, tool_name: string, input: table}
function M.show(thread, pending)
  local chat = require("claude-agents.ui.chat")
  local events = require("claude-agents.agent.events")

  local text = "Permission: " .. events.tool_summary(pending.tool_name, pending.input)
  if pending.tool_name == "Bash" and pending.input.command then
    text = "Permission: Bash\n$ " .. pending.input.command
  end
  chat.append(thread, "permission", text .. "\n[y] allow · [n] deny")

  local bufs = {}
  for _, b in ipairs({ thread.chat_buf, thread.input_buf }) do
    if b and vim.api.nvim_buf_is_valid(b) then
      table.insert(bufs, b)
    end
  end

  local function answer(allow)
    for _, b in ipairs(bufs) do
      pcall(vim.keymap.del, "n", "y", { buffer = b })
      pcall(vim.keymap.del, "n", "n", { buffer = b })
    end
    if thread.session and thread.session.pending_permission
      and thread.session.pending_permission.request_id == pending.request_id then
      thread.session:answer_permission(allow)
    end
    -- Restore the sidebar's `n` = new-thread style default on the input buffer:
    -- nothing to restore; chat/input have no default y/n maps.
  end

  for _, b in ipairs(bufs) do
    vim.keymap.set("n", "y", function()
      answer(true)
    end, { buffer = b, nowait = true, desc = "Allow tool" })
    vim.keymap.set("n", "n", function()
      answer(false)
    end, { buffer = b, nowait = true, desc = "Deny tool" })
  end
end

return M
