local M = {}

---@param thread Thread
local function send(thread)
  local buf = thread.input_buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = vim.trim(table.concat(lines, "\n"))
  if text == "" then
    return
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
  thread.input_history = thread.input_history or {}
  table.insert(thread.input_history, text)
  thread.history_pos = nil
  require("acp.agent.session").get(thread):send(text)
end

---@param thread Thread
---@param delta integer
local function history(thread, delta)
  local hist = thread.input_history or {}
  if #hist == 0 then
    return
  end
  local pos = thread.history_pos or (#hist + 1)
  pos = math.min(math.max(pos + delta, 1), #hist + 1)
  thread.history_pos = pos
  local text = hist[pos] or ""
  vim.api.nvim_buf_set_lines(thread.input_buf, 0, -1, false, vim.split(text, "\n"))
end

---@param thread Thread
---@return integer bufnr
function M.ensure_buf(thread)
  if thread.input_buf and vim.api.nvim_buf_is_valid(thread.input_buf) then
    return thread.input_buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  local name = "acp://input/" .. thread.slug .. "/" .. thread.id
  require("acp.util").wipe_named_buf(name)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  thread.input_buf = buf

  local opts = function(desc)
    return { buffer = buf, desc = desc, nowait = true }
  end
  vim.keymap.set({ "n", "i" }, "<CR>", function()
    vim.cmd.stopinsert()
    send(thread)
  end, opts("Send message"))
  vim.keymap.set("i", "<C-j>", "<CR>", { buffer = buf, desc = "Insert newline" })
  vim.keymap.set({ "n", "i" }, "<C-c>", function()
    if thread.session then
      thread.session:interrupt()
    end
  end, opts("Interrupt Claude"))
  vim.keymap.set("n", "<C-p>", function()
    history(thread, -1)
  end, opts("Previous prompt"))
  vim.keymap.set("n", "<C-n>", function()
    history(thread, 1)
  end, opts("Next prompt"))

  -- Pasting lines yanked from a file inserts a context chip like
  -- "(file.txt 1-3)" instead of the raw text (expanded at send time).
  local function paste(after)
    local reg = vim.v.register
    local chip = require("acp.context").chip_for(vim.fn.getreg(reg))
    if chip then
      vim.api.nvim_put({ chip }, "c", after, true)
    else
      vim.cmd('normal! "' .. reg .. (after and "p" or "P"))
    end
  end
  vim.keymap.set("n", "p", function()
    paste(true)
  end, opts("Paste (chips file yanks)"))
  vim.keymap.set("n", "P", function()
    paste(false)
  end, opts("Paste before (chips file yanks)"))
  vim.keymap.set("i", "<C-r>", function()
    local okc, reg = pcall(vim.fn.getcharstr)
    if not okc or not reg or #reg ~= 1 then
      return
    end
    local chip = require("acp.context").chip_for(vim.fn.getreg(reg))
    if chip then
      vim.api.nvim_put({ chip }, "c", false, true)
    else
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-r>" .. reg, true, false, true), "n", false)
    end
  end, opts("Insert register (chips file yanks)"))
  return buf
end

---Focus the input window of the thread's tab (if visible).
---@param thread Thread
function M.focus(thread)
  if not thread:tab_valid() then
    return
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(thread.tabpage)) do
    if vim.w[win].acp_ui == "input" then
      vim.api.nvim_set_current_win(win)
      vim.cmd.startinsert()
      return
    end
  end
end

return M
