---Keymaps shared by a thread's chat and input buffers.
local M = {}

---@param buf integer
---@param thread Thread
---@param interrupt_modes string|string[] modes to bind <C-c> in
function M.apply(buf, thread, interrupt_modes)
  local function opts(desc)
    return { buffer = buf, desc = desc, nowait = true }
  end
  local function session()
    return require("acp.agent.session").get(thread)
  end
  vim.keymap.set(interrupt_modes, "<C-c>", function()
    if thread.session then
      thread.session:interrupt()
    end
  end, opts("Interrupt agent"))
  vim.keymap.set("n", "gm", function()
    session():select_config()
  end, opts("Session config (mode/model)"))
  vim.keymap.set("n", "gq", function()
    session():edit_queue()
  end, opts("Edit queued prompts"))
  vim.keymap.set("n", "gp", function()
    require("acp.ui.plan").open(thread)
  end, opts("Show the agent's current plan"))
  vim.keymap.set("n", "gs", function()
    require("acp.ui.subagents").open(thread)
  end, opts("Show the subagents spawned in this thread"))
  vim.keymap.set("n", "gf", function()
    thread.follow = not session():follow_enabled()
    vim.notify("acp: follow mode " .. (thread.follow and "on" or "off"))
  end, opts("Toggle follow mode"))
end

return M
