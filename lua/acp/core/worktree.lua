local util = require("acp.util")

local M = {}

---Ensure the worktrees dir is ignored without touching the project's .gitignore.
---@param root string
---@param dir string
local function ensure_excluded(root, dir)
  local exclude = root .. "/.git/info/exclude"
  local pattern = "/" .. dir .. "/"
  local existing = {}
  local f = io.open(exclude, "r")
  if f then
    for line in f:lines() do
      existing[line] = true
    end
    f:close()
  end
  if not existing[pattern] then
    local fa = io.open(exclude, "a")
    if fa then
      fa:write(pattern .. "\n")
      fa:close()
    end
  end
end

---Create a worktree + branch for a thread slug.
---@param root string repo root
---@param slug string
---@return {path: string, branch: string}|nil worktree, string|nil err
function M.create(root, slug)
  local cfg = require("acp.config").options.worktrees
  local path = root .. "/" .. cfg.dir .. "/" .. slug
  local branch = cfg.branch_prefix .. slug

  if vim.fn.isdirectory(path) == 1 then
    return nil, "worktree path already exists: " .. path
  end
  vim.fn.mkdir(root .. "/" .. cfg.dir, "p")
  ensure_excluded(root, cfg.dir)

  local args = { "git", "-C", root, "worktree", "add", path, "-b", branch }
  local ok, out = util.system(args)
  if not ok and out:find("already exists") then
    -- Branch exists from a previous thread with the same slug: reuse it.
    ok, out = util.system({ "git", "-C", root, "worktree", "add", path, branch })
  end
  if not ok then
    return nil, out
  end
  return { path = path, branch = branch }, nil
end

---Plugin-managed worktrees found under the configured worktrees dir.
---@param root string repo root
---@return {path: string, branch: string, name: string}[]
function M.list(root)
  local cfg = require("acp.config").options.worktrees
  local base = root .. "/" .. cfg.dir
  local out = {}
  if vim.fn.isdirectory(base) ~= 1 then
    return out
  end
  for name, kind in vim.fs.dir(base) do
    if kind == "directory" and vim.fn.filereadable(base .. "/" .. name .. "/.git") == 1 then
      -- A worktree root has a .git *file*; a stray dir (where git would
      -- resolve to the parent repo) or a nested repo does not.
      local path = base .. "/" .. name
      local ok, branch = util.system({ "git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD" })
      if ok then
        table.insert(out, { path = path, branch = vim.trim(branch), name = name })
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

---@param wt {path: string, branch: string}
---@return boolean
function M.is_dirty(wt)
  local ok, out = util.system({ "git", "-C", wt.path, "status", "--porcelain" })
  return ok and out ~= ""
end

---Remove a worktree (and prune). Refuses dirty worktrees unless force.
---@param root string
---@param wt {path: string, branch: string}
---@param force boolean
---@return boolean ok, string|nil err
function M.remove(root, wt, force)
  local args = { "git", "-C", root, "worktree", "remove", wt.path }
  if force then
    table.insert(args, "--force")
  end
  local ok, out = util.system(args)
  if not ok then
    return false, out
  end
  util.system({ "git", "-C", root, "worktree", "prune" })
  return true, nil
end

return M
