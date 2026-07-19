---Handlers for the ACP fs capability: the agent reads/writes files through
---the editor, so it sees unsaved buffer contents and its edits land in open
---buffers.
local M = {}

---@param path string
---@return integer|nil bufnr loaded buffer visiting path
local function loaded_buf(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == path then
      return buf
    end
  end
end

---@param params {path: string, line: integer|nil, limit: integer|nil}
---@return string|nil content, string|nil err
function M.read_text_file(params)
  local path = params.path
  local lines
  local buf = loaded_buf(path)
  if buf then
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  elseif vim.fn.filereadable(path) == 1 then
    local ok, read = pcall(vim.fn.readfile, path)
    if not ok then
      return nil, "failed to read " .. path
    end
    lines = read
  else
    return nil, "file not found: " .. path
  end
  if params.line or params.limit then
    local first = params.line or 1
    local last = params.limit and (first + params.limit - 1) or #lines
    lines = vim.list_slice(lines, first, math.min(last, #lines))
  end
  return table.concat(lines, "\n"), nil
end

---@param params {path: string, content: string}
---@return boolean ok, string|nil err
function M.write_text_file(params)
  local path = params.path
  local lines = vim.split(params.content or "", "\n", { plain = true })
  local buf = loaded_buf(path)
  if buf then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local ok = pcall(vim.api.nvim_buf_call, buf, function()
      vim.cmd("silent keepalt write!")
    end)
    if not ok then
      return false, "failed to write buffer for " .. path
    end
    return true, nil
  end
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = io.open(path, "w")
  if not f then
    return false, "cannot open " .. path .. " for writing"
  end
  f:write(params.content or "")
  f:close()
  return true, nil
end

return M
