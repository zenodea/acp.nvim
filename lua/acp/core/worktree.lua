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

---Path a worktree for `slug` lives at (single source of the dir layout).
---@param root string repo root
---@param slug string
---@return string
function M.path_for(root, slug)
  return root .. "/" .. require("acp.config").options.worktrees.dir .. "/" .. slug
end

---Create a worktree + branch for a thread slug.
---@param root string repo root
---@param slug string
---@return {path: string, branch: string}|nil worktree, string|nil err
function M.create(root, slug)
  local cfg = require("acp.config").options.worktrees
  local path = M.path_for(root, slug)
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
---One `git worktree list` call instead of a git invocation per directory.
---@param root string repo root
---@return {path: string, branch: string, name: string}[]
function M.list(root)
  local cfg = require("acp.config").options.worktrees
  -- git prints symlink-resolved paths (/private/var vs /var on macOS):
  -- compare resolved forms.
  local base = vim.fn.resolve(root) .. "/" .. cfg.dir .. "/"
  local out = {}
  local ok, porcelain = util.system({ "git", "-C", root, "worktree", "list", "--porcelain" })
  if not ok then
    return out
  end
  local path, branch
  local function flush()
    if path and vim.fn.resolve(path):sub(1, #base) == base and branch then
      -- Emit the canonical root-based path (git's is symlink-resolved).
      local name = vim.fs.basename(path)
      table.insert(out, { path = M.path_for(root, name), branch = branch, name = name })
    end
    path, branch = nil, nil
  end
  for _, line in ipairs(util.lines(porcelain)) do
    if line:match("^worktree ") then
      flush()
      path = line:sub(#"worktree " + 1)
    elseif line:match("^branch ") then
      branch = line:sub(#"branch " + 1):gsub("^refs/heads/", "")
    end
  end
  flush()
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
