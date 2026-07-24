---The prompt-queue editor (gq): a scratch float holding the plain text of
---every queued prompt, separated by ─ lines. Edit, reorder, or delete
---blocks like any buffer; closing it (or :w) applies the queue back to the
---session.
local M = {}

local SEP = string.rep("─", 40)

---@param session Session
function M.open(session)
  if #session.queue == 0 then
    vim.notify("acp: no queued prompts", vim.log.levels.INFO)
    return
  end
  local util = require("acp.util")

  local lines = {}
  for i, text in ipairs(session.queue) do
    if i > 1 then
      table.insert(lines, SEP)
    end
    vim.list_extend(lines, util.lines(text))
  end

  local buf = util.scratch_buf("acp://queue/" .. session.thread.slug, {
    buftype = "acwrite", -- lets :w apply without closing
    bufhidden = "wipe",
    filetype = "markdown",
  })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  -- The queue is applied when the window closes, so the buffer is never
  -- "unsaved": keep 'modified' off so a plain :q never trips E37.
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      vim.bo[buf].modified = false
    end,
  })

  util.centered_float(buf, {
    max_width = 80,
    lines = #lines,
    title = " queued prompts — :q applies · :w applies and stays ",
  })

  -- Prompts sent while the editor is open (recorded by flush_queue) must
  -- not be re-queued when the buffer is applied.
  local flushed = {}
  session._queue_flushed = flushed

  local function parse()
    local prompts, block = {}, {}
    local function push()
      local s, e = 1, #block
      while s <= e and block[s]:match("^%s*$") do
        s = s + 1
      end
      while e >= s and block[e]:match("^%s*$") do
        e = e - 1
      end
      if s <= e then
        table.insert(prompts, table.concat(vim.list_slice(block, s, e), "\n"))
      end
      block = {}
    end
    -- "─" is multibyte, so quantifiers can't apply to the whole char: match
    -- three literal ─ then allow only ─ bytes/whitespace to the end.
    local sep_pat = "^%s*───[─%s]*$"
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if l:match(sep_pat) then
        push()
      else
        table.insert(block, l)
      end
    end
    push()
    local out = {}
    for _, p in ipairs(prompts) do
      local sent
      for j, f in ipairs(flushed) do
        if f == p then
          sent = j
          break
        end
      end
      if sent then
        table.remove(flushed, sent)
      else
        table.insert(out, p)
      end
    end
    return out
  end

  local function apply()
    session.queue = parse()
    session:queue_changed()
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    desc = "Apply the edited prompt queue",
    callback = function()
      apply()
      vim.bo[buf].modified = false
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    desc = "Apply the edited prompt queue",
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) then
        apply()
      end
      if session._queue_flushed == flushed then
        session._queue_flushed = nil
      end
    end,
  })
end

return M
