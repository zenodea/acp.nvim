local M = {}

---@class AcpConfig
M.defaults = {
  -- ACP agents available for threads. Keys are agent names shown in the
  -- picker; `cmd` is the full command spawning an ACP server on stdio;
  -- `icon` is shown next to the thread in the sidebar.
  agents = {
    claude = { cmd = { "npx", "-y", "@agentclientprotocol/claude-agent-acp" }, icon = "✳" },
    codex = { cmd = { "npx", "-y", "@agentclientprotocol/codex-acp" }, icon = "⬡" },
    gemini = { cmd = { "npx", "-y", "@google/gemini-cli", "--experimental-acp" }, icon = "◆" },
    -- Each entry may also set `env = { KEY = "value" }`.
  },
  -- Agent used when only one is configured or none is picked.
  default_agent = "claude",

  -- MCP servers forwarded to every agent session (ACP session/new
  -- mcpServers). Stdio entries: { name = "...", command = "...", args = {},
  -- env = { { name = "K", value = "V" } } }; http/sse entries per the spec.
  mcp_servers = {},

  -- Start the agent session as soon as a thread is opened (instead of on the
  -- first message), so the agent is ready when you start typing.
  autostart = true,

  -- Kill the process of a thread that has been idle this long (seconds).
  -- Only applies to agents that support session/load (the conversation is
  -- reloaded on next use); others are kept alive.
  idle_timeout = 900,

  ui = {
    sidebar_width = 30,
    chat_width = 64,
    input_height = 5,
    -- Hide the native tabline (each thread is a tab page; the sidebar
    -- already shows them). Sets showtabline=0.
    hide_tabline = true,
    -- Window focused after opening/switching a thread:
    -- "keep" stays in the same kind of window you came from (sidebar stays
    -- sidebar, code stays code); "input" | "code" | "sidebar" force one.
    focus_on_open = "keep",
    show_thinking = true, -- render agent thought chunks (dimmed)
    show_diffs = true, -- render diffs from tool-call content
    diff_max_lines = 24, -- truncate rendered diffs beyond this
    diff_context = 3, -- unchanged context lines kept around each diff hunk
    show_result_meta = true, -- "── done · 12s" line after each turn
    -- Rename threads from the agent's session title (session_info_update);
    -- manual renames always win.
    auto_title = true,
    -- Follow the agent: jump the code window to tool-call locations as it
    -- works. Toggle per thread with `gf` in the chat.
    follow = false,
    icons = {
      working = "●",
      attention = "?",
      idle = "✓",
      error = "✗",
      tool = "󰖷",
      -- Per ACP tool kind overrides (read/edit/delete/move/search/execute/
      -- think/fetch). Trailing spaces are respected: wide nerd-font glyphs
      -- can bake in the spacing they need.
      tool_kinds = {
        read = " ",
        edit = " ",
      },
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

---Sorted list of configured agent names.
---@return string[]
function M.agent_names()
  local names = vim.tbl_keys(M.options.agents)
  table.sort(names)
  return names
end

return M
