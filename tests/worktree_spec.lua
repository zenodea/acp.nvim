local h = require("tests.helpers")
local eq = h.eq

require("acp.config").setup({})
local wt = require("acp.core.worktree")
local util = require("acp.util")

---A throwaway git repo with one commit.
local function temp_repo()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  local function git(args)
    local ok, out = util.system(vim.list_extend({ "git", "-C", root }, args))
    assert(ok, "git failed: " .. tostring(out))
  end
  git({ "init", "-q" })
  git({ "config", "user.email", "test@test" })
  git({ "config", "user.name", "test" })
  vim.fn.writefile({ "hello" }, root .. "/f.txt")
  git({ "add", "." })
  git({ "commit", "-q", "-m", "init" })
  return root
end

local T = {}

function T.create_list_remove_roundtrip()
  local root = temp_repo()
  eq({}, wt.list(root), "empty before any worktree")
  local created, err = wt.create(root, "feat-a")
  assert(created, err)
  local listed = wt.list(root)
  eq(1, #listed)
  eq("feat-a", listed[1].name)
  eq("agents/feat-a", listed[1].branch)
  eq(created.path, listed[1].path)
  eq(true, wt.remove(root, created, false))
  eq({}, wt.list(root), "empty after removal")
  vim.fn.delete(root, "rf")
end

function T.list_survives_stray_files()
  local root = temp_repo()
  assert(wt.create(root, "feat-b"))
  -- A stray file and a non-worktree dir in .worktrees must not break list.
  vim.fn.writefile({ "junk" }, root .. "/.worktrees/notes.txt")
  vim.fn.mkdir(root .. "/.worktrees/not-a-worktree", "p")
  local listed = wt.list(root)
  eq(1, #listed)
  eq("feat-b", listed[1].name)
  vim.fn.delete(root, "rf")
end

return T
