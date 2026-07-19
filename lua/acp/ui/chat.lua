local M = {}

local ns = vim.api.nvim_create_namespace("acp-chat")

local kind_hl = {
  user = "AcpChatUser",
  tool = "AcpChatTool",
  thinking = "AcpChatThinking",
  meta = "AcpChatMeta",
  error = "AcpChatError",
  permission = "AcpChatPermission",
}

---@param thread Thread
---@return integer bufnr
function M.ensure_buf(thread)
  if thread.chat_buf and vim.api.nvim_buf_is_valid(thread.chat_buf) then
    return thread.chat_buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local name = "acp://chat/" .. thread.slug .. "/" .. thread.id
  require("acp.util").wipe_named_buf(name)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  thread.chat_buf = buf

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, desc = desc, nowait = true })
  end
  map("i", function()
    require("acp.ui.input").focus(thread)
  end, "Focus message input")
  map("<C-c>", function()
    if thread.session then
      thread.session:interrupt()
    end
  end, "Interrupt Claude")

  M.replay(thread)
  return buf
end

---@param icons table
---@param kind string
---@param text string
---@return string[]
local function entry_lines(icons, kind, text)
  local body = vim.split(text, "\n", { plain = true })
  if kind == "user" then
    local lines = { "", icons.user .. " You" }
    vim.list_extend(lines, body)
    return lines
  elseif kind == "text" then
    local lines = { "" }
    vim.list_extend(lines, body)
    return lines
  elseif kind == "tool" then
    return { icons.tool .. " " .. body[1] }
  elseif kind == "thinking" then
    return { icons.thinking .. " " .. body[1] }
  elseif kind == "error" then
    local lines = {}
    for i, l in ipairs(body) do
      lines[i] = (i == 1 and "✗ " or "  ") .. l
    end
    return lines
  elseif kind == "permission" then
    local lines = { "" }
    for i, l in ipairs(body) do
      table.insert(lines, (i == 1 and icons.permission .. " " or "  ") .. l)
    end
    return lines
  else -- meta
    return body
  end
end

---@param buf integer
---@param kind string
---@param text string
local function render_entry(buf, kind, text)
  local icons = require("acp.config").options.ui.icons
  local lines = entry_lines(icons, kind, text)
  vim.bo[buf].modifiable = true
  local start = vim.api.nvim_buf_line_count(buf)
  -- An untouched buffer has a single empty line; write into it, not after it.
  if start == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "" then
    start = 0
  end
  vim.api.nvim_buf_set_lines(buf, start, -1, false, lines)
  vim.bo[buf].modifiable = false

  local hl = kind_hl[kind]
  if hl then
    for i = 0, #lines - 1 do
      local lnum = start + i
      if kind ~= "user" or i == 1 or (start == 0 and i == 0) then
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { line_hl_group = hl, priority = 90 })
      end
    end
  elseif kind == "meta" then
    for i = 0, #lines - 1 do
      vim.api.nvim_buf_set_extmark(buf, ns, start + i, 0, { line_hl_group = "AcpChatMeta", priority = 90 })
    end
  end
  if kind == "meta" then
    -- Colorize diff-ish meta lines rendered for Edit/Write tool calls.
    for i, l in ipairs(lines) do
      if l:sub(1, 2) == "+ " then
        vim.api.nvim_buf_set_extmark(buf, ns, start + i - 1, 0, { line_hl_group = "AcpDiffAdd", priority = 95 })
      elseif l:sub(1, 2) == "- " then
        vim.api.nvim_buf_set_extmark(buf, ns, start + i - 1, 0, { line_hl_group = "AcpDiffDelete", priority = 95 })
      end
    end
  end
end

---Scroll every window showing this chat to the bottom (unless the user has
---scrolled up and is reading history in a focused chat window).
---@param buf integer
local function autoscroll(buf)
  local last = vim.api.nvim_buf_line_count(buf)
  local current_win = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if win ~= current_win then
      pcall(vim.api.nvim_win_set_cursor, win, { last, 0 })
    end
  end
end

---Append an entry: records it in the transcript and renders it.
---@param thread Thread
---@param kind string
---@param text string
function M.append(thread, kind, text)
  table.insert(thread.transcript, { kind = kind, text = text })
  local buf = M.ensure_buf(thread)
  render_entry(buf, kind, text)
  autoscroll(buf)
  require("acp.persist.store").save_debounced()
end

---Re-render the whole transcript into the chat buffer (used on restore).
---@param thread Thread
function M.replay(thread)
  local buf = thread.chat_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, entry in ipairs(thread.transcript) do
    render_entry(buf, entry.kind, entry.text)
  end
  autoscroll(buf)
end

return M
