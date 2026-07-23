-- Test runner: nvim --headless -l tests/run.lua
-- Each tests/*_spec.lua returns a table of test-name -> function; a test
-- fails by raising (assert/error). State is reset between tests.

local script = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.dirname(vim.fs.dirname(script))
package.path = table.concat({
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/?.lua",
  package.path,
}, ";")

---Wipe windows/buffers so tests cannot leak layout into each other.
local function reset()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  vim.cmd("silent! only!")
  vim.cmd("silent! enew!")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if buf ~= vim.api.nvim_get_current_buf() then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

local specs = vim.fn.glob(root .. "/tests/*_spec.lua", true, true)
table.sort(specs)
local total, failed = 0, 0

for _, file in ipairs(specs) do
  local spec_name = vim.fn.fnamemodify(file, ":t:r")
  local tests = dofile(file)
  local names = vim.tbl_keys(tests)
  table.sort(names)
  for _, name in ipairs(names) do
    total = total + 1
    reset()
    local ok, err = pcall(tests[name])
    if ok then
      io.write(string.format("ok   %s / %s\n", spec_name, name))
    else
      failed = failed + 1
      io.write(string.format("FAIL %s / %s\n     %s\n", spec_name, name, tostring(err)))
    end
  end
end

io.write(string.format("\n%d tests, %d failed\n", total, failed))
os.exit(failed > 0 and 1 or 0)
