---Spec-side helpers for end-to-end UI tests: run the real plugin against
---the fake ACP agent (fake_agent.lua) and assert on real buffers/windows.
local H = {}

local ROOT =
  vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))))

local did_setup = false

---First acp.setup in this process (setup is first-call-wins). Isolated:
---no persistence, no reap timers, no notifications.
function H.setup_once()
  if did_setup then
    return
  end
  did_setup = true
  require("acp").setup({
    agents = { fake = { cmd = { "placeholder" }, icon = "◈" } },
    default_agent = "fake",
    autostart = true,
    idle_timeout = 0,
    notify = false,
    persist = { enabled = false },
  })
end

---@param pred fun(): any
---@param what string
---@param timeout integer|nil ms
function H.wait_for(pred, what, timeout)
  timeout = timeout or tonumber(vim.env.ACP_TEST_TIMEOUT) or 5000
  if not vim.wait(timeout, pred, 10) then
    local dump = H.thread and H.dump(H.thread) or ""
    error(("timeout waiting for %s\n%s"):format(what, dump))
  end
end

---@param thread table
---@return string
function H.dump(thread)
  local status = ("status=%s detail=%s busy=%s"):format(
    tostring(thread.status),
    tostring(thread.status_detail),
    tostring(thread.session and thread.session.busy)
  )
  local chat = thread.chat_buf
      and vim.api.nvim_buf_is_valid(thread.chat_buf)
      and table.concat(vim.api.nvim_buf_get_lines(thread.chat_buf, 0, -1, false), "\n")
    or "<no chat buf>"
  return status .. "\nchat:\n" .. chat
end

local n = 0

---Create + open a thread on the fake agent playing `scenario`.
---@param scenario string
---@param opts {wait_ready: boolean|nil}|nil
---@return table thread
function H.start(scenario, opts)
  H.setup_once()
  require("acp.config").options.agents.fake.cmd = {
    vim.v.progpath,
    "--clean",
    "-l",
    ROOT .. "/tests/e2e/fake_agent.lua",
    scenario,
  }
  n = n + 1
  local thread = require("acp.core.thread").new({
    name = "e2e-" .. scenario .. "-" .. n,
    cwd = ROOT,
    agent = "fake",
  })
  require("acp.core.registry").add(thread)
  require("acp").open_thread(thread)
  H.thread = thread
  if not (opts and opts.wait_ready == false) then
    H.wait_for(function()
      return thread.session and thread.session.ready
    end, "session ready")
  end
  return thread
end

---Send `text` through the real input buffer + <CR> keymap.
---@param thread table
---@param text string
function H.send(thread, text)
  local input = require("acp.ui.input")
  local buf = input.ensure_buf(thread)
  local win = H.win(thread, "input")
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
  H.feed(win, "<CR>")
end

---Feed keys into a window (normal mode), flushing synchronously.
---@param win integer
---@param keys string
function H.feed(win, keys)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

---Wait for the current turn to finish (busy off, status settled).
---@param thread table
function H.wait_done(thread)
  H.wait_for(function()
    return thread.session and not thread.session.busy and thread.status ~= "working"
  end, "turn done")
end

---@param thread table
---@return string[]
function H.chat_lines(thread)
  return vim.api.nvim_buf_get_lines(thread.chat_buf, 0, -1, false)
end

---True if some chat line contains `pat` (plain match).
---@param thread table
---@param pat string
function H.chat_has(thread, pat)
  for _, l in ipairs(H.chat_lines(thread)) do
    if l:find(pat, 1, true) then
      return true
    end
  end
  return false
end

---@param thread table
---@param role string sidebar|chat|input
---@return integer
function H.win(thread, role)
  local win = require("acp.ui.workspace").find_ui_win(thread.tabpage, role)
  assert(win, "no " .. role .. " window")
  return win
end

---Tear down a thread completely so tests cannot leak into each other.
---@param thread table
function H.stop(thread)
  pcall(function()
    require("acp.agent.session").stop(thread)
  end)
  pcall(function()
    require("acp.ui.workspace").close(thread)
  end)
  vim.cmd("silent! tabonly!")
  local registry = require("acp.core.registry")
  pcall(registry.remove, thread)
  registry.threads = {}
  registry.last_active = nil
  H.thread = nil
end

---Wrap a test body so teardown always runs.
---@param scenario string
---@param fn fun(thread: table)
---@param opts table|nil passed to H.start
---@return fun()
function H.test(scenario, fn, opts)
  return function()
    local thread = H.start(scenario, opts)
    local ok, err = pcall(fn, thread)
    H.stop(thread)
    assert(ok, err)
  end
end

return H
