local M = {}

local did_setup = false

local function registry()
  return require("acp.core.registry")
end

local function workspace()
  return require("acp.ui.workspace")
end

local function store()
  return require("acp.persist.store")
end

---@param thread Thread
---@param old ThreadStatus
---@param old_detail string|nil
local function notify_status(thread, old, old_detail)
  if not require("acp.config").options.notify then
    return
  end
  -- Only notify for threads you are not currently looking at.
  if thread:tab_valid() and thread.tabpage == vim.api.nvim_get_current_tabpage() then
    return
  end
  local name = thread.name
  if thread.status == "attention" then
    vim.notify(("acp: %s needs attention (%s)"):format(name, thread.status_detail or "waiting"), vim.log.levels.WARN)
  elseif thread.status == "error" then
    vim.notify(("acp: %s failed (%s)"):format(name, thread.status_detail or "error"), vim.log.levels.ERROR)
  elseif thread.status == "idle" and old == "working" and old_detail ~= "starting agent" then
    -- Finishing the session startup is not "done" in any interesting sense.
    vim.notify(("acp: %s is done"):format(name), vim.log.levels.INFO)
  end
end

local function setup_autocmds()
  local group = vim.api.nvim_create_augroup("Acp", { clear = true })

  vim.api.nvim_create_autocmd("TabLeave", {
    group = group,
    callback = function()
      local thread = registry().find_by_tab(vim.api.nvim_get_current_tabpage())
      if thread then
        workspace().capture_layout(thread)
        store().save_debounced()
      end
    end,
  })

  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      vim.schedule(function()
        for _, t in ipairs(registry().threads) do
          if t.tabpage and not vim.api.nvim_tabpage_is_valid(t.tabpage) then
            t.tabpage = nil
          end
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, t in ipairs(registry().threads) do
        if t:tab_valid() then
          workspace().capture_layout(t)
        end
        require("acp.agent.session").stop(t)
      end
      store().save()
    end,
  })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      require("acp.ui.highlights").setup()
    end,
  })

  vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    desc = "Track yanks for chat context chips",
    callback = function()
      require("acp.context").on_yank()
    end,
  })
end

---@param opts table|nil
function M.setup(opts)
  require("acp.config").setup(opts)
  if did_setup then
    return
  end
  did_setup = true

  require("acp.ui.highlights").setup()

  if require("acp.config").options.ui.hide_tabline then
    vim.o.showtabline = 0
  end

  local util = require("acp.util")
  local cwd = vim.fn.getcwd()
  registry().root = util.git_root(cwd) or cwd

  store().load()
  setup_autocmds()

  local sidebar = require("acp.ui.sidebar")
  registry().on("status", function(thread, old, old_detail)
    sidebar.render()
    store().save_debounced()
    notify_status(thread, old, old_detail)
  end)
  registry().on("threads", function()
    sidebar.render()
    store().save_debounced()
  end)
  registry().on("state", function()
    store().save_debounced()
  end)

  local keymaps = require("acp.config").options.keymaps or {}
  if keymaps.chat then
    vim.keymap.set("n", keymaps.chat, function()
      M.focus_chat()
    end, { desc = "ACP: focus chat" })
  end
  if keymaps.threads then
    vim.keymap.set("n", keymaps.threads, function()
      M.focus_threads()
    end, { desc = "ACP: focus threads sidebar" })
  end
end

local function ensure_setup()
  if not did_setup then
    M.setup({})
  end
end

---Slug unique across live threads and existing worktree dirs.
---@param name string
---@return string
local function unique_slug(name)
  local util = require("acp.util")
  local cfg = require("acp.config").options.worktrees
  local base = util.slugify(name)
  local slug = base
  local n = 1
  while registry().find_by_slug(slug) ~= nil
    or vim.fn.isdirectory(registry().root .. "/" .. cfg.dir .. "/" .. slug) == 1 do
    n = n + 1
    slug = base .. "-" .. n
  end
  return slug
end

---@param name string
---@param use_worktree boolean
---@param agent string|nil
local function create_thread(name, use_worktree, agent)
  local Thread = require("acp.core.thread")
  local root = registry().root
  local slug = unique_slug(name)

  local wt = nil
  if use_worktree then
    local err
    wt, err = require("acp.core.worktree").create(root, slug)
    if not wt then
      vim.notify("acp: worktree creation failed: " .. (err or "?"), vim.log.levels.ERROR)
      return
    end
  end

  local thread = Thread.new({ name = name, cwd = wt and wt.path or root, worktree = wt, agent = agent })
  thread.slug = slug
  registry().add(thread)
  workspace().open(thread)
end

---Create a new thread; prompts for name, agent, and worktree choice.
---@param name string|nil
function M.new(name)
  ensure_setup()

  local function pick_workspace(n, agent)
    if require("acp.util").git_root(registry().root) then
      vim.ui.select(
        { "Current checkout", "New worktree (isolated branch)" },
        { prompt = "Workspace for '" .. n .. "':" },
        function(choice, idx)
          if not choice then
            return
          end
          create_thread(n, idx == 2, agent)
        end
      )
    else
      create_thread(n, false, agent)
    end
  end

  local function pick_agent(n)
    local names = require("acp.config").agent_names()
    if #names <= 1 then
      pick_workspace(n, names[1])
      return
    end
    vim.ui.select(names, { prompt = "Agent for '" .. n .. "':" }, function(choice)
      if choice then
        pick_workspace(n, choice)
      end
    end)
  end

  local function with_name(n)
    if not n or vim.trim(n) == "" then
      return
    end
    pick_agent(vim.trim(n))
  end

  if name and vim.trim(name) ~= "" then
    with_name(name)
  else
    vim.ui.input({ prompt = "Thread name: " }, with_name)
  end
end

---Open the sidebar / last active thread (entry point for :Acp).
function M.open()
  ensure_setup()
  local thread = registry().last_active_thread()
  if thread then
    workspace().open(thread)
  else
    M.new()
  end
end

---@param thread Thread
function M.open_thread(thread)
  ensure_setup()
  workspace().open(thread)
end

---@param thread Thread
function M.delete(thread)
  ensure_setup()
  if vim.fn.confirm("Delete thread '" .. thread.name .. "'?", "&Yes\n&No", 2) ~= 1 then
    return
  end
  if thread.session then
    thread.session:delete_remote()
  end
  workspace().close(thread)

  if thread.worktree then
    local wt_mod = require("acp.core.worktree")
    local choice = vim.fn.confirm(
      "Remove worktree " .. thread.worktree.path .. " (branch " .. thread.worktree.branch .. ")?",
      "&Yes\n&No",
      2
    )
    if choice == 1 then
      local force = false
      if wt_mod.is_dirty(thread.worktree) then
        force = vim.fn.confirm("Worktree has uncommitted changes. Remove anyway?", "&Yes\n&No", 2) == 1
        if not force then
          vim.notify("acp: kept worktree " .. thread.worktree.path, vim.log.levels.INFO)
        end
      end
      if force or not wt_mod.is_dirty(thread.worktree) then
        local ok, err = wt_mod.remove(registry().root, thread.worktree, force)
        if not ok then
          vim.notify("acp: worktree removal failed: " .. (err or "?"), vim.log.levels.ERROR)
        end
      end
    end
  end

  require("acp.agent.session").stop(thread)
  registry().remove(thread)
  store().save()
end

---@param thread Thread
function M.rename(thread)
  ensure_setup()
  vim.ui.input({ prompt = "Rename thread: ", default = thread.name }, function(name)
    if not name or vim.trim(name) == "" then
      return
    end
    thread.name = vim.trim(name)
    thread.manual_name = true
    workspace().update_winbar(thread)
    registry().emit("threads")
  end)
end

function M.toggle_chat()
  ensure_setup()
  workspace().toggle_chat()
end

---Thread of the current tab, falling back to opening the last active one.
---@return Thread|nil
local function current_or_last_thread()
  local thread = registry().find_by_tab(vim.api.nvim_get_current_tabpage())
  if thread then
    return thread
  end
  thread = registry().last_active_thread()
  if not thread then
    M.new()
    return nil
  end
  workspace().open(thread)
  return thread
end

---Focus the chat input of the current (or last active) thread, building the
---chat column if it was hidden.
function M.focus_chat()
  ensure_setup()
  local thread = current_or_last_thread()
  if not thread then
    return
  end
  if not workspace().find_ui_win(thread.tabpage, "chat") then
    workspace().build_chat_column(thread)
  end
  require("acp.ui.input").focus(thread)
end

---Focus the threads sidebar of the current (or last active) thread's tab.
function M.focus_threads()
  ensure_setup()
  local thread = current_or_last_thread()
  if not thread then
    return
  end
  local win = workspace().find_ui_win(thread.tabpage, "sidebar")
  if not win then
    workspace().build_sidebar()
    win = workspace().find_ui_win(thread.tabpage, "sidebar")
  end
  if win then
    vim.api.nvim_set_current_win(win)
  end
end

---Interrupt the thread of the current tab.
function M.interrupt()
  ensure_setup()
  local thread = registry().find_by_tab(vim.api.nvim_get_current_tabpage())
  if thread and thread.session then
    thread.session:interrupt()
  end
end

---Statusline component, e.g. "●2 ?1" (empty when there are no threads).
---@return string
function M.statusline()
  if not did_setup or #registry().threads == 0 then
    return ""
  end
  local icons = require("acp.config").options.ui.icons
  local counts = registry().status_counts()
  local parts = {}
  for _, status in ipairs({ "working", "attention", "error" }) do
    if counts[status] > 0 then
      table.insert(parts, icons[status] .. counts[status])
    end
  end
  if #parts == 0 then
    return icons.idle .. #registry().threads
  end
  return table.concat(parts, " ")
end

return M
