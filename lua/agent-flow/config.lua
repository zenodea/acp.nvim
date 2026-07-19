local M = {}

---@class AgentFlowConfig
M.defaults = {
  -- Claude Code CLI
  claude = {
    cmd = "claude", -- binary name or absolute path
    model = nil, -- e.g. "claude-sonnet-5"; nil = CLI default
    -- Extra args appended to every spawn (e.g. { "--allowedTools", "Read,Grep" })
    extra_args = {},
    -- "prompt": route tool permissions through the chat panel (stream-json
    -- control protocol). Any other value is passed to --permission-mode
    -- (e.g. "acceptEdits", "bypassPermissions", "plan", "default").
    permissions = "prompt",
    -- Kill the process of a thread that has been idle this long (seconds).
    -- The conversation survives: it is resumed with --resume on next use.
    idle_timeout = 900,
  },

  ui = {
    sidebar_width = 30,
    chat_width = 64,
    input_height = 5,
    -- "input" | "code" | "sidebar": window focused after opening a thread
    focus_on_open = "input",
    show_thinking = true, -- render a marker line for thinking blocks
    show_diffs = true, -- render diffs for Edit/Write tool calls
    diff_max_lines = 24, -- truncate rendered diffs beyond this
    show_result_meta = true, -- "✓ done · $0.01 · 12s" line after each turn
    icons = {
      working = "●",
      attention = "?",
      idle = "✓",
      error = "✗",
      tool = "⏺",
      thinking = "✱",
      permission = "⚠",
      user = "❯",
    },
  },

  worktrees = {
    -- Directory (relative to the repo root) where thread worktrees live.
    dir = ".worktrees",
    -- Prefix for branches created for thread worktrees.
    branch_prefix = "agents/",
  },

  persist = {
    enabled = true,
    -- Max transcript entries kept per thread in the state file.
    max_transcript = 2000,
  },

  -- Global keymaps (set a value to false to disable it).
  keymaps = {
    chat = "<leader>cc", -- focus the chat of the current (or last) thread
    threads = "<leader>ct", -- focus the threads sidebar
  },

  -- vim.notify when a background thread needs attention / finishes.
  notify = true,
}

M.options = vim.deepcopy(M.defaults)

---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
