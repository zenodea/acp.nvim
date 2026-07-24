local h = require("tests.helpers")
local eq = h.eq

h.stub("acp.persist.store", {
  save_debounced = function() end,
  save = function() end,
  load = function() end,
})
require("acp").setup({})

---One code window plus one marked plugin window in the current tab.
---@return integer ui_win
local function workspace_layout()
  vim.cmd("vsplit")
  local ui_win = vim.api.nvim_get_current_win()
  vim.w[ui_win].acp_ui = "chat"
  vim.cmd("wincmd p")
  return ui_win
end

local T = {}

function T.quit_in_float_keeps_the_workspace()
  local ui_win = workspace_layout()
  local buf = vim.api.nvim_create_buf(false, true)
  local float = vim.api.nvim_open_win(buf, true, { relative = "editor", row = 1, col = 1, width = 10, height = 3 })
  vim.cmd("quit")
  eq(false, vim.api.nvim_win_is_valid(float), "float closed")
  eq(true, vim.api.nvim_win_is_valid(ui_win), "plugin window survives")
end

function T.new_worktree_thread_prompts_for_worktree_name()
  local cfg = require("acp.config")
  local registry = require("acp.core.registry")
  local wt_mod = require("acp.core.worktree")
  local old_autostart, real_create = cfg.options.autostart, wt_mod.create
  local old_select, old_input = vim.ui.select, vim.ui.input
  cfg.options.autostart = false
  local created_name
  wt_mod.create = function(_, slug)
    created_name = slug
    return { path = "/tmp/fake-wt/" .. slug, branch = "agents/" .. slug }
  end
  vim.ui.select = function(items, _, cb)
    if items[1] == "Current checkout" then
      cb(items[2], 2) -- "New worktree (isolated branch)"
    else
      cb(items[1], 1) -- first agent
    end
  end
  vim.ui.input = function(_, cb)
    cb("My Fancy Tree") -- the user's worktree name, needing slugification
  end

  local ok, err = pcall(require("acp").new, "wt-name-test")

  vim.ui.select, vim.ui.input = old_select, old_input
  wt_mod.create = real_create
  cfg.options.autostart = old_autostart
  assert(ok, err)

  eq("my-fancy-tree", created_name, "worktree named from the prompt, slugified")
  local t = registry.threads[#registry.threads]
  eq("agents/my-fancy-tree", t.worktree.branch)
  require("acp.ui.workspace").close(t)
  vim.cmd("silent! tabonly!")
  registry.remove(t)
end

function T.quit_last_code_window_closes_plugin_windows()
  vim.cmd("tabnew") -- keep another tab so the quit cannot exit Neovim
  local ui_win = workspace_layout()
  vim.cmd("quit")
  eq(false, vim.api.nvim_win_is_valid(ui_win), "plugin window closed too")
end

return T
