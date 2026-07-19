# acp.nvim

A Neovim plugin for running AI coding agents in parallel threads, built on the
Agent Client Protocol (ACP). It works with any ACP agent. Claude Code and
Codex are configured out of the box, and others like Gemini CLI can be added
with a single config entry.

## What it does

The plugin organizes your work into threads. A thread is one conversation with
one agent, plus its own workspace: its own tab page, its own window layout,
and optionally its own git worktree. This means you can have several agents
working on the same repository at the same time without them interfering with
each other or with your own editing.

Each thread's tab has three columns: a sidebar listing all threads on the
left, the agent chat in the middle, and your normal editing windows on the
right.

The sidebar shows a status icon for every thread so you always know what each
agent is doing:

- `●` the agent is working
- `?` the agent needs you (a permission request or a question)
- `✓` the agent is idle or done
- `✗` something failed

If a background thread needs attention you also get a notification, and
`require("acp").statusline()` returns a summary string you can put in your
statusline.

## Features

- One agent process per thread, speaking JSON-RPC over stdio (the ACP wire
  format). Threads can use different agents: one thread on Claude, another on
  Codex, picked when the thread is created. The sidebar shows an icon per
  agent.
- Optional git worktree per thread. When you create a thread you can choose
  between the current checkout and a fresh worktree with its own branch, so
  parallel changes never collide.
- Streaming chat. Responses, thought chunks, plans, and tool calls render
  live. Tool calls update in place as they progress and show inline diffs.
- Permission prompts in the chat. When the agent wants to run something that
  needs approval, the request appears inline with the agent's own options
  (allow once, always allow, reject) mapped to keys.
- File access through the editor. The agent reads and writes files through
  Neovim, so it sees your unsaved changes and its edits land in your open
  buffers.
- Terminals provided by the editor. Agents run commands in terminals the
  plugin spawns, and the live output streams inside the tool call.
- Context chips. If you yank lines from a file and paste them into the chat
  input, they collapse to a token like `(file.txt 1-3)`. When you send the
  message, the token expands to the current content of those lines.
- Session config. `gm` opens the agent's config options, such as permission
  mode and model. The current mode and model are shown above the chat.
- Slash commands. `/` on an empty input lists the commands the agent
  advertises.
- Follow mode. `gf` toggles jumping the code window to the file and line the
  agent is currently touching.
- Persistence. Threads, transcripts, layouts, and session ids survive
  restarting Neovim. Conversations resume through the protocol, including
  turns that happened outside Neovim.
- Auto titles. Agents that send a session title rename their thread, unless
  you renamed it yourself.
- Authentication in the editor. If an agent requires login, its auth methods
  are offered in a picker.

## Requirements

- Neovim 0.10 or newer
- Node.js (the default adapters are npm packages run through npx)
- A logged-in Claude Code (or `ANTHROPIC_API_KEY`) for the Claude agent
- A logged-in Codex CLI for the Codex agent
- git, if you want worktree support

## Install

With lazy.nvim:

```lua
{
  "zenodea/acp.nvim",
  cmd = { "Acp", "AcpNew" },
  opts = {},
}
```

Run `:checkhealth acp` after installing to verify the setup.

## Commands

| Command            | Action                                                |
| ------------------ | ----------------------------------------------------- |
| `:Acp`             | Open the last active thread, or create one if none exist |
| `:AcpNew [name]`   | Create a thread, asking for the agent and workspace   |
| `:AcpToggleChat`   | Show or hide the chat column                          |
| `:AcpInterrupt`    | Interrupt the current thread's turn                   |
| `:checkhealth acp` | Verify agents, git, and Neovim setup                  |

## Keymaps

Global (configurable, set to `false` to disable):

- `<leader>cc` focus the chat of the current or last thread
- `<leader>ct` focus the threads sidebar

Sidebar:

- `Enter` open thread, `n` new, `d` delete, `r` rename

Chat input:

- `Enter` send, `Ctrl-j` newline, `Ctrl-c` interrupt
- `Ctrl-p` / `Ctrl-n` prompt history
- `p` / `P` paste (file yanks become context chips)
- `gm` session config (mode, model), `gf` follow mode
- `/` on an empty input opens the command picker
- `y` / `a` / `n` answer permission prompts (keys are shown inline)

## Configuration

Defaults:

```lua
require("acp").setup({
  agents = {
    claude = { cmd = { "npx", "-y", "@agentclientprotocol/claude-agent-acp" }, icon = "✳" },
    codex  = { cmd = { "npx", "-y", "@agentclientprotocol/codex-acp" }, icon = "⬡" },
    -- gemini = { cmd = { "gemini", "--experimental-acp" }, icon = "◆" },
    -- entries may also set env = { KEY = "value" }
  },
  default_agent = "claude",
  mcp_servers = {},     -- MCP servers forwarded to every agent session
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
  transparently the next time you use the thread. Nothing is lost.
- Worktrees live in `.worktrees/<thread-name>` on a branch named
  `agents/<thread-name>`. Both are configurable. Deleting a thread offers to
  remove its worktree, with an extra confirmation if it has uncommitted
  changes.
- State is stored per project in `stdpath("data")/acp/`, keyed by the git
  root.
