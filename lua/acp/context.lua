---Context chips: pasting yanked lines into the chat input inserts a compact
---token like `(file.txt 1-3)` instead of the raw text. At send time the chip
---expands to the referenced lines (read fresh, through buffers) — as an ACP
---embedded resource when the agent supports it, else as a fenced code block.
local M = {}

---Lua pattern matching a chip token.
M.pattern = "%([^%s()]+ %d+%-%d+%)"

---@type {path: string, s: integer, e: integer, text: string}|nil last linewise yank
local last_yank = nil
---@type table<string, {path: string, s: integer, e: integer}> chip token -> source
local chips = {}

---TextYankPost handler: remember linewise yanks from named file buffers.
function M.on_yank()
  local ev = vim.v.event
  if ev.operator ~= "y" or (ev.regtype or ""):sub(1, 1) ~= "V" then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= "" or name == "" then
    return
  end
  local s = vim.api.nvim_buf_get_mark(buf, "[")[1]
  local e = vim.api.nvim_buf_get_mark(buf, "]")[1]
  if s == 0 or e == 0 then
    return
  end
  last_yank = { path = name, s = s, e = e, text = table.concat(ev.regcontents or {}, "\n") }
end

---@param text string
---@return string
local function norm(text)
  return (text:gsub("\n+$", ""))
end

---If `regtext` is the content of the last recorded yank, return its chip
---token (registering it for send-time expansion).
---@param regtext string
---@return string|nil
function M.chip_for(regtext)
  if not last_yank or norm(regtext) ~= norm(last_yank.text) then
    return nil
  end
  local tail = vim.fn.fnamemodify(last_yank.path, ":t")
  local token = string.format("(%s %d-%d)", tail, last_yank.s, last_yank.e)
  local existing = chips[token]
  if existing and existing.path ~= last_yank.path then
    -- Same tail, different file: disambiguate with the relative path.
    token = string.format("(%s %d-%d)", vim.fn.fnamemodify(last_yank.path, ":~:."), last_yank.s, last_yank.e)
  end
  chips[token] = { path = last_yank.path, s = last_yank.s, e = last_yank.e }
  return token
end

---@param chip {path: string, s: integer, e: integer}
---@return string
local function chip_content(chip)
  local content = require("acp.agent.fs").read_text_file({
    path = chip.path,
    line = chip.s,
    limit = chip.e - chip.s + 1,
  })
  return content or ""
end

---Expand chips in a message into ACP prompt content blocks.
---@param text string
---@param allow_resource boolean agent supports embeddedContext
---@return table[] blocks
function M.to_blocks(text, allow_resource)
  local blocks = {}
  local function push_text(t)
    if t ~= "" then
      table.insert(blocks, { type = "text", text = t })
    end
  end

  local flush_from, search = 1, 1
  while true do
    local s_idx, e_idx = text:find(M.pattern, search)
    if not s_idx then
      break
    end
    local token = text:sub(s_idx, e_idx)
    local chip = chips[token]
    if chip then
      push_text(text:sub(flush_from, s_idx - 1))
      local content = chip_content(chip)
      if allow_resource then
        table.insert(blocks, {
          type = "resource",
          resource = { uri = "file://" .. chip.path, text = content },
        })
      else
        push_text(string.format("\n```\n# %s\n%s\n```\n", token, content))
      end
      flush_from = e_idx + 1
    end
    search = e_idx + 1
  end

  local rest = text:sub(flush_from)
  if rest ~= "" or #blocks == 0 then
    push_text(rest ~= "" and rest or text)
  end
  return blocks
end

return M
