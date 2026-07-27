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

---A span of seconds as "12s" / "1m02s", for runtimes shown in the UI.
---@param secs integer
---@return string
function M.duration(secs)
  secs = math.max(secs or 0, 0)
  if secs < 60 then
    return secs .. "s"
  end
  return ("%dm%02ds"):format(math.floor(secs / 60), secs % 60)
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

---Unlisted scratch buffer, optionally named (wiping any stale holder).
---@param name string|nil
---@param opts {buftype: string|nil, bufhidden: string|nil, filetype: string|nil}|nil
---@return integer bufnr
function M.scratch_buf(name, opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  if name then
    M.wipe_named_buf(name)
    vim.api.nvim_buf_set_name(buf, name)
  end
  vim.bo[buf].buftype = opts.buftype or "nofile"
  vim.bo[buf].bufhidden = opts.bufhidden or "hide"
  vim.bo[buf].swapfile = false
  if opts.filetype then
    vim.bo[buf].filetype = opts.filetype
  end
  return buf
end

---Open `buf` in a centered rounded float sized to its content.
---@param buf integer
---@param opts {max_width: integer|nil, lines: integer, title: string}
---@return integer win
function M.centered_float(buf, opts)
  local width = math.min(opts.max_width or 80, math.max(vim.o.columns - 8, 20))
  local height = math.min(math.max(opts.lines, 3) + 1, math.max(vim.o.lines - 6, 3))
  return vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    border = "rounded",
    title = opts.title,
    title_pos = "center",
  })
end

---A 120 ms spinner ticker: `on_frame(frame)` runs per tick while started.
---@param on_frame fun(frame: string)
---@return {start: fun(), stop: fun()}
function M.spinner_timer(on_frame)
  local uv = vim.uv or vim.loop
  local timer, i = nil, 0
  return {
    start = function()
      if timer then
        return
      end
      timer = uv.new_timer()
      if not timer then
        return
      end
      timer:start(
        120,
        120,
        vim.schedule_wrap(function()
          i = (i % #M.spinner) + 1
          on_frame(M.spinner[i])
        end)
      )
    end,
    stop = function()
      if timer then
        timer:stop()
        timer:close()
        timer = nil
      end
    end,
  }
end

---Keep the cursor of the current window on lines where `is_target(lnum)`
---holds, snapping in the direction it was moving (tracked per window in
---w:acp_last_pos, which dies with the window).
---@param is_target fun(lnum: integer): boolean
function M.snap_cursor(is_target)
  local win = vim.api.nvim_get_current_win()
  local lnum = vim.api.nvim_win_get_cursor(win)[1]
  if is_target(lnum) then
    vim.w[win].acp_last_pos = lnum
    return
  end
  local prev = vim.w[win].acp_last_pos
  local down = prev ~= nil and lnum > prev
  local total = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  local step = down and 1 or -1
  local target
  for l = lnum + step, down and total or 1, step do
    if is_target(l) then
      target = l
      break
    end
  end
  if not target then -- nothing further that way: search back the other way
    for l = lnum - step, down and 1 or total, -step do
      if is_target(l) then
        target = l
        break
      end
    end
  end
  if target then
    local pos = vim.api.nvim_win_get_cursor(win)
    pcall(vim.api.nvim_win_set_cursor, win, { target, pos[2] })
    vim.w[win].acp_last_pos = target
  end
end

---"name — description" label for pickers.
---@param name string
---@param description string|nil
---@return string
function M.labeled(name, description)
  return name .. ((description and description ~= "") and (" — " .. description) or "")
end

---@param path string
---@return table|nil
function M.read_json(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, decoded = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
  return (ok and type(decoded) == "table") and decoded or nil
end

---@param path string
---@param tbl table
function M.write_json(path, tbl)
  local ok, encoded = pcall(vim.json.encode, tbl)
  if not ok then
    return
  end
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = io.open(path, "w")
  if f then
    f:write(encoded)
    f:close()
  end
end

return M
