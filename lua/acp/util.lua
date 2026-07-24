local M = {}

---Spinner frames shared by the chat winbar (startup) and the sidebar
---(working threads).
M.spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

---Turn a human name into a filesystem/branch-safe slug.
---@param name string
---@return string
function M.slugify(name)
  local slug = name:lower():gsub("[^%w%-_]+", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
  if slug == "" then
    slug = "thread"
  end
  return slug
end

local id_counter = 0

---Unique-enough id for a thread (stable across serialization).
---@return string
function M.uuid()
  id_counter = id_counter + 1
  return string.format("%x-%x-%d", os.time(), math.random(0, 0xffff), id_counter)
end

---@param str string
---@param max integer
---@return string
function M.shorten(str, max)
  str = str:gsub("%s+", " ")
  if vim.fn.strdisplaywidth(str) <= max then
    return str
  end
  return vim.fn.strcharpart(str, 0, max - 1) .. "…"
end

---Stable key for a project root, used to name the state file.
---@param root string
---@return string
function M.project_key(root)
  return vim.fn.sha256(root):sub(1, 16)
end

---Synchronous shell helper.
---@param args string[]
---@param cwd string|nil
---@return boolean ok, string output
function M.system(args, cwd)
  local res = vim.system(args, { cwd = cwd, text = true }):wait()
  local out = vim.trim((res.stdout or "") .. (res.stderr or ""))
  return res.code == 0, out
end

---Git root of a directory, or nil when not in a repo.
---@param dir string
---@return string|nil
function M.git_root(dir)
  local ok, out = M.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
  if ok and out ~= "" then
    return out
  end
  return nil
end

---Delete any existing buffer with this exact name (stale after a thread
---object is recreated, e.g. on persistence reload).
---@param name string
function M.wipe_named_buf(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == name then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

---Split possibly-multiline text into a list of lines.
---@param text string
---@return string[]
function M.lines(text)
  return vim.split(text, "\n", { plain = true })
end

return M
