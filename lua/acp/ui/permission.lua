local M = {}

---Preferred keys per ACP permission-option kind.
local kind_keys = { allow_once = "y", allow_always = "a", reject_once = "n", reject_always = "N" }

---Render an ACP permission request in the chat panel and arm per-option
---keymaps on the thread's chat + input buffers until it is answered.
---@param thread Thread
---@param pending {respond: fun(...), options: table[], title: string}
function M.show(thread, pending)
  local chat = require("acp.ui.chat")

  -- Assign a key to every option (kind-based, falling back to digits).
  local used, keyed = {}, {}
  for i, option in ipairs(pending.options) do
    local key = kind_keys[option.kind]
    if not key or used[key] then
      key = tostring(i)
    end
    used[key] = true
    table.insert(keyed, { key = key, option = option })
  end

  local hints = {}
  for _, k in ipairs(keyed) do
    table.insert(hints, string.format("[%s] %s", k.key, k.option.name or k.option.kind or k.option.optionId))
  end
  chat.append(thread, "permission", "Permission: " .. pending.title .. "\n" .. table.concat(hints, " · "))

  local bufs = {}
  for _, b in ipairs({ thread.chat_buf, thread.input_buf }) do
    if b and vim.api.nvim_buf_is_valid(b) then
      table.insert(bufs, b)
    end
  end

  local function clear_maps()
    for _, b in ipairs(bufs) do
      for _, k in ipairs(keyed) do
        pcall(vim.keymap.del, "n", k.key, { buffer = b })
      end
    end
  end
  -- Let the session clear the keymaps when the request is cancelled.
  pending.clear = clear_maps

  for _, k in ipairs(keyed) do
    for _, b in ipairs(bufs) do
      vim.keymap.set("n", k.key, function()
        clear_maps()
        -- Only answer if this request is still the live one.
        if thread.session and thread.session.pending_permission == pending then
          thread.session:answer_permission(k.option.optionId)
        end
      end, { buffer = b, nowait = true, desc = "Permission: " .. (k.option.name or k.key) })
    end
  end
end

return M
