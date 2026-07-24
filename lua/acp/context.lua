---Context chips: pasting yanked lines into the chat input inserts a compact
---token like `(file.txt 1-3)` instead of the raw text. At send time the chip
---expands to the referenced lines (read fresh, through buffers) — as an ACP
---embedded resource when the agent supports it, else as a fenced code block.
local M = {}

---Ranged chip token like "(file.txt 1-3)". Whole-file chips look like
---"(file.txt)"; only registered tokens expand, so ordinary parenthesised
---prose passes through untouched.
local ranged_pattern = "%([^%s()]+ %d+%-%d+%)"
local file_pattern = "%([^%s()]+%)"

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

---Register a chip for `path` (+ optional line range) and return its token.
---Tokens use the file tail, falling back to the relative path when two
---files share a tail.
---@param path string absolute path
---@param s integer|nil first line (nil = whole file)
---@param e integer|nil last line
---@return string token
function M.add(path, s, e)
  local function token_for(name)
    if s then
      return string.format("(%s %d-%d)", name, s, e or s)
    end
    return string.format("(%s)", name)
  end
  local token = token_for(vim.fn.fnamemodify(path, ":t"))
  local existing = chips[token]
  if existing and existing.path ~= path then
    -- Same tail, different file: disambiguate with the relative path.
    token = token_for(vim.fn.fnamemodify(path, ":~:."))
  end
  chips[token] = { path = path, s = s, e = e or s }
  return token
end

---If `regtext` is the content of the last recorded yank, return its chip
---token (registering it for send-time expansion).
---@param regtext string
---@return string|nil
function M.chip_for(regtext)
  if not last_yank or norm(regtext) ~= norm(last_yank.text) then
    return nil
  end
  return M.add(last_yank.path, last_yank.s, last_yank.e)
end

---Chip for the current visual selection (call while visual mode is active
---or right after leaving it). Returns nil outside a named file buffer.
---@return string|nil token
function M.selection_chip()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= "" or path == "" then
    return nil
  end
  local s, e
  if vim.fn.mode():match("^[vV\022]") then
    s, e = vim.fn.line("v"), vim.fn.line(".")
  else
    s, e = vim.fn.line("'<"), vim.fn.line("'>")
  end
  if s == 0 or e == 0 then
    return nil
  end
  if s > e then
    s, e = e, s
  end
  return M.add(path, s, e)
end

---Chip + message for the diagnostics on the current line, or nil.
---@return string|nil
function M.diagnostic_chip()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  if vim.bo[buf].buftype ~= "" or path == "" then
    return nil
  end
  local lnum = vim.fn.line(".")
  local diags = vim.diagnostic.get(buf, { lnum = lnum - 1 })
  if #diags == 0 then
    return nil
  end
  local msgs = {}
  for _, d in ipairs(diags) do
    table.insert(msgs, (d.message:gsub("%s+", " ")))
  end
  return M.add(path, lnum, lnum) .. " — " .. table.concat(msgs, "; ")
end

---@param chip {path: string, s: integer|nil, e: integer|nil}
---@return string
local function chip_content(chip)
  local content = require("acp.agent.fs").read_text_file({
    path = chip.path,
    line = chip.s,
    limit = chip.s and (chip.e - chip.s + 1) or nil,
  })
  return content or ""
end

---Earliest chip-shaped token (ranged or whole-file) at or after `from`.
---@param text string
---@param from integer
---@return integer|nil s, integer|nil e
local function next_token(text, from)
  local s1, e1 = text:find(ranged_pattern, from)
  local s2, e2 = text:find(file_pattern, from)
  if s1 and (not s2 or s1 <= s2) then
    return s1, e1
  end
  return s2, e2
end

local files_cache = { cwd = nil, at = 0, list = {} }

---Project files matching `base` (for the @ completion), relative to `cwd`.
---Uses git when available (respects .gitignore), else a bounded glob.
---Paths containing spaces are skipped: chips cannot express them.
---@param cwd string
---@param base string
---@return string[]
function M.files(cwd, base)
  -- The @ completion refires per keystroke; scan once and refilter.
  local now = (vim.uv or vim.loop).now()
  if files_cache.cwd ~= cwd or (now - files_cache.at) > 5000 then
    local ok, out = require("acp.util").system({ "git", "-C", cwd, "ls-files", "-co", "--exclude-standard" })
    local candidates
    if ok then
      candidates = vim.split(out, "\n", { plain = true, trimempty = true })
    else
      candidates = vim.fn.globpath(cwd, "**", false, true)
      for i, p in ipairs(candidates) do
        candidates[i] = p:sub(#cwd + 2)
      end
    end
    files_cache = { cwd = cwd, at = now, list = candidates }
  end
  local candidates = files_cache.list
  local matches = {}
  base = base:lower()
  for _, rel in ipairs(candidates) do
    if not rel:find("%s") and (base == "" or rel:lower():find(base, 1, true)) then
      table.insert(matches, rel)
      if #matches >= 200 then
        break
      end
    end
  end
  return matches
end

---'completefunc' for the chat input: complete "@partial" into a whole-file
---context chip. The input buffer sets b:acp_cwd to the thread's cwd.
---@param findstart integer
---@param base string
---@return integer|table
function M.complete(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local at = line:sub(1, col):find("@[^%s@]*$")
    return at and (at - 1) or -3
  end
  local cwd = vim.b.acp_cwd or vim.fn.getcwd()
  local items = {}
  for _, rel in ipairs(M.files(cwd, base:gsub("^@", ""))) do
    table.insert(items, {
      word = M.add(cwd .. "/" .. rel),
      abbr = rel,
      menu = "file",
    })
  end
  return items
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
    local s_idx, e_idx = next_token(text, search)
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
