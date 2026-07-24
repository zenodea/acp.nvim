local h = require("tests.helpers")
local eq = h.eq

local context = require("acp.context")

---A temp file with the given lines, deleted by the caller.
local function temp_file(lines)
  local path = vim.fn.tempname()
  vim.fn.writefile(lines, path)
  return path
end

local T = {}

function T.ranged_chip_expands_to_the_selected_lines()
  local path = temp_file({ "l1", "l2", "l3", "l4" })
  local token = context.add(path, 2, 3)
  eq(true, token:find("2%-3%)$") ~= nil, "token carries the range: " .. token)
  local blocks = context.to_blocks("look at " .. token .. " please", true)
  eq(3, #blocks)
  eq("look at ", blocks[1].text)
  eq("l2\nl3", blocks[2].resource.text)
  eq(" please", blocks[3].text)
  vim.fn.delete(path)
end

function T.whole_file_chip_expands_to_the_full_file()
  local path = temp_file({ "a", "b" })
  local token = context.add(path)
  eq(true, token:find("%d%-%d%)$") == nil, "no range in a whole-file token: " .. token)
  local blocks = context.to_blocks(token, true)
  eq("a\nb", blocks[1].resource.text)
  eq("file://" .. path, blocks[1].resource.uri)
  vim.fn.delete(path)
end

function T.unregistered_parens_stay_plain_text()
  local blocks = context.to_blocks("this (word) and (range 1-2) are prose", true)
  eq(1, #blocks)
  eq("this (word) and (range 1-2) are prose", blocks[1].text)
end

function T.selection_chip_uses_the_visual_range()
  local path = temp_file({ "x1", "x2", "x3" })
  vim.cmd.edit(path)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd("normal! Vj") -- select lines 1-2
  local token = context.selection_chip()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  eq(true, token ~= nil and token:find("1%-2%)$") ~= nil, "selection range: " .. tostring(token))
  local blocks = context.to_blocks(token, true)
  eq("x1\nx2", blocks[1].resource.text)
  vim.fn.delete(path)
end

function T.files_lists_repo_files_filtered()
  local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
  local files = context.files(root, "readme")
  eq(true, vim.tbl_contains(files, "README.md"), "README.md found")
  for _, f in ipairs(files) do
    eq(true, f:lower():find("readme", 1, true) ~= nil, "all matches contain the base: " .. f)
  end
end

return T
