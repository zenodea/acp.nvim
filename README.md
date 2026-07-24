# acp.nvim

A Neovim plugin for running AI coding agents in parallel threads, similar to
[Zed](https://zed.dev)'s agent panel. It is built on the
[Agent Client Protocol](https://agentclientprotocol.com) (ACP), so it works
with any ACP agent. [Claude Code](https://docs.anthropic.com/en/docs/claude-code),
[Codex](https://github.com/zed-industries/codex-acp), and
[Gemini CLI](https://github.com/google-gemini/gemini-cli) are configured out
of the box; any other ACP agent is one config entry away.

## What it does

Work is organized into threads. A thread is one conversation with one agent
plus its own workspace: a tab page, a window layout, and optionally a git
worktree. Several agents can work on the same repository at the same time
without interfering with each other or with you.

Each thread's tab has three columns: the threads sidebar, the agent chat, and
your editing windows. The sidebar groups threads by workspace — the main
checkout first, then one section per worktree — and shows a status per
thread: an animated spinner while working, `?` needs you, `✓` done, `✗`
failed. Background threads that need attention also fire a notification, and
`require("acp").statusline()` gives you a summary for your statusline.

## Features

- [x] One agent process per thread, different agents per thread
- [x] Optional git worktree and branch per thread
- [x] Streaming chat with live tool calls, diffs, and plans
- [x] Permission prompts answered inline in the chat
- [x] Agent reads and writes through your buffers, unsaved edits included
- [x] Editor-provided terminals with live command output
- [x] Context chips: pasted file yanks become `(file.txt 1-3)`
- [x] Mode and model picker (`gm`), slash command picker (`/`)
- [x] Favourite model per agent: the last model you pick becomes the default
- [x] Sessions autostart when a thread is opened (spinner while booting)
- [x] Prompt queue shown in the input winbar, editable with `gq`
- [x] Follow mode: jump to where the agent is working (`gf`)
- [x] Persistence: threads, layouts, and conversations survive restarts
- [x] Auto-titled threads, in-editor authentication

## Requirements

- Neovim 0.10+, Node.js, git (for worktrees)
- A logged-in Claude Code, Codex, or Gemini CLI

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "zenodea/acp.nvim",
  cmd = { "Acp", "AcpNew" },
  opts = {},
}
```

Run `:checkhealth acp` after installing.

## Commands

| Command            | Action                                                |
| ------------------ | ----------------------------------------------------- |
| `:Acp`             | Open the last active thread, or create one if none exist |
| `:AcpNew [name]`   | Create a thread: pick the agent, then the workspace (checkout, new worktree, or an existing free worktree) |
| `:AcpToggleChat`   | Show or hide the chat column                          |
| `:AcpInterrupt`    | Interrupt the current thread's turn                   |
| `:checkhealth acp` | Verify agents, git, and Neovim setup                  |

## Keymaps

Global: `<leader>cc` focus chat, `<leader>ct` focus sidebar.

Sidebar: `Enter` open, `n` new, `d` delete, `r` rename.

Chat input: `Enter` send, `Ctrl-j` newline, `Ctrl-c` interrupt, `Ctrl-p`/`Ctrl-n`
history, `gm` config, `gq` edit queued prompts, `gf` follow, `/` commands,
`y`/`a`/`n` permissions.

Chat transcript: `Enter` expand/collapse an entry, `gd` jump to the code a
tool call touched.

Messages sent while the agent is working are queued; the input winbar shows
the count. `gq` opens the queue as plain text in a floating buffer — edit,
reorder, or delete the `─`-separated blocks like any text and close the
window (or `:w`) to apply.

## Configuration

Defaults:

```lua
require("acp").setup({
  agents = {
    claude = { cmd = { "npx", "-y", "@agentclientprotocol/claude-agent-acp" }, icon = "✳" },
    codex  = { cmd = { "npx", "-y", "@agentclientprotocol/codex-acp" }, icon = "⬡" },
    gemini = { cmd = { "npx", "-y", "@google/gemini-cli", "--experimental-acp" }, icon = "◆" },
    -- entries may also set env = { KEY = "value" }
  },
  default_agent = "claude",
  mcp_servers = {},     -- MCP servers forwarded to every agent session
  autostart = true,     -- boot the agent session when a thread is opened
  idle_timeout = 900,   -- seconds before an idle agent process is stopped
  ui = {
    sidebar_width = 30,
    chat_width = 64,
    input_height = 5,
    hide_tabline = true,     -- threads are tabs, the sidebar replaces the tabline
    focus_on_open = "keep",  -- "keep" | "input" | "code" | "sidebar"
    show_thinking = true,
    show_diffs = true,
    diff_max_lines = 24,
    diff_context = 3,
    show_result_meta = true,
    auto_title = true,
    follow = false,
  },
  worktrees = {
    dir = ".worktrees",       -- relative to the repo root
    branch_prefix = "agents/",
  },
  persist = { enabled = true, max_transcript = 2000 },
  keymaps = {
    chat = "<leader>cc",
    threads = "<leader>ct",
  },
  notify = true,
})
```

Notes:

- Idle agent processes are stopped after `idle_timeout` seconds and revived
  transparently. Nothing is lost.
- Worktrees live in `.worktrees/<thread-name>` on branch `agents/<thread-name>`.
  Deleting a thread offers to remove its worktree.
- State is stored per project in `stdpath("data")/acp/`, keyed by git root.
- Picking a model with `gm` makes it the favourite for that agent: new
  sessions start on it. Favourites are global (all projects), stored in
  `stdpath("data")/acp/prefs.json`.
- `:q` in the last code window of a thread tab closes the sidebar/chat
  windows with it, so quitting doesn't require closing each plugin window.
