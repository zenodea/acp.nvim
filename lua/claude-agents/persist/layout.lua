local M = {}

---@param node table winlayout() node
---@return table|nil serializable node (UI windows pruned)
local function capture_node(node)
  local kind = node[1]
  if kind == "leaf" then
    local win = node[2]
    if not vim.api.nvim_win_is_valid(win) or vim.w[win].claude_agents_ui then
      return nil
    end
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].buftype ~= "" then
      return nil
    end
    local name = vim.api.nvim_buf_get_name(buf)
    local cursor = vim.api.nvim_win_get_cursor(win)
    if name == "" then
      return { type = "leaf" } -- empty window: keep the slot, no file
    end
    return { type = "leaf", file = name, cursor = cursor }
  else -- "row" | "col"
    local children = {}
    for _, child in ipairs(node[2]) do
      local captured = capture_node(child)
      if captured then
        table.insert(children, captured)
      end
    end
    if #children == 0 then
      return nil
    end
    if #children == 1 then
      return children[1]
    end
    return { type = kind, children = children }
  end
end

---Capture the code-area layout of a tabpage (plugin UI windows excluded).
---@param tabpage integer
---@return table|nil
function M.capture(tabpage)
  local tabnr = vim.api.nvim_tabpage_get_number(tabpage)
  local ok, tree = pcall(vim.fn.winlayout, tabnr)
  if not ok then
    return nil
  end
  return capture_node(tree)
end

---@param node table
local function restore_node(node)
  if node.type == "leaf" then
    if node.file and vim.fn.filereadable(node.file) == 1 then
      pcall(vim.cmd.edit, vim.fn.fnameescape(node.file))
      if node.cursor then
        pcall(vim.api.nvim_win_set_cursor, 0, node.cursor)
      end
    end
    return
  end
  -- row = side-by-side (vsplit), col = stacked (split)
  local split_cmd = node.type == "row" and "rightbelow vsplit" or "rightbelow split"
  local wins = { vim.api.nvim_get_current_win() }
  for _ = 2, #node.children do
    vim.cmd(split_cmd)
    table.insert(wins, vim.api.nvim_get_current_win())
  end
  for i, child in ipairs(node.children) do
    if vim.api.nvim_win_is_valid(wins[i]) then
      vim.api.nvim_set_current_win(wins[i])
      restore_node(child)
    end
  end
end

---Restore a captured layout into the current window (best-effort).
---@param layout table
function M.restore(layout)
  pcall(restore_node, layout)
end

return M
