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

Docked under the sidebar, a details panel keeps the current thread's vitals
in view: its branch with ahead/behind counts and diff size, the plan step
being worked on, running subagents with their runtime, queued prompts, and
the context counter.

## Features

- [x] One agent process per thread, different agents per thread
- [x] Optional git worktree and branch per thread
- [x] Streaming chat with live tool calls, diffs, and plans; unfinished tool
      calls spin in place of their icon until they land
- [x] Permission prompts answered inline in the chat
- [x] Agent reads and writes through your buffers, unsaved edits included
- [x] Editor-provided terminals with live command output
- [x] Context chips: pasted file yanks become `(file.txt 1-3)`; `<leader>cs`
      attaches a visual selection, `<leader>cd` a diagnostic, and `@` in the
      input completes project files into whole-file chips
- [x] Mode and model picker (`gm`), slash command picker (`/`)
- [x] Favourite model per agent: the last model you pick becomes the default
- [x] Sessions autostart when a thread is opened (spinner while booting)
- [x] Prompt queue shown in the input winbar, editable with `gq`
- [x] Plan panel (`gp`): the agent's current plan on demand, step count in
      the chat winbar
- [x] Subagent panel (`gs`): what the agent delegated, with status and
      runtime; running count in the chat winbar
- [x] Context counter in the chat winbar: `◔ 21%` of the model's window,
      reported by the agent
- [x] Details panel under the sidebar: branch, diff size, current plan step,
      running subagents, queue, and context at a glance
- [x] Follow mode: jump to where the agent is working (`gf`), pinned to the
      window you pick with `<leader>cf`
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
| `:AcpNew [name]`   | Create a thread: pick the agent, then the workspace (main checkout, any worktree, or a new named worktree) |
| `:AcpToggleChat`   | Show or hide the chat column                          |
| `:AcpFollow`       | Reveal the agent's edits in the current window (toggles) |
| `:AcpInterrupt`    | Interrupt the current thread's turn                   |
| `:checkhealth acp` | Verify agents, git, and Neovim setup                  |

## Keymaps

Global: `<leader>cc` focus chat, `<leader>ct` focus sidebar, `<leader>cs`
(visual) attach the selection to the chat as a context chip, `<leader>cd`
attach the diagnostic under the cursor, `<leader>cf` follow the agent in
this window.

Sidebar: `Enter` open, `n` new (inside a workspace section, the new thread
uses that workspace), `N` new thread in a brand-new worktree (names the
worktree, then the thread), `d` delete, `r` rename.

Chat input: `Enter` send, `Ctrl-j` newline, `Ctrl-c` interrupt, `Ctrl-p`/`Ctrl-n`
history, `gm` config, `gq` edit queued prompts, `gp` plan, `gs` subagents,
`gf` follow, `/` commands, `y`/`a`/`n` permissions. `Esc` in normal mode
interrupts too, in both the input and the transcript.

Chat transcript: `Enter` expand/collapse an entry — expanding a tool call
shows its whole diff, however long — `Shift-Enter` open a tool call's full
content in a float (`q` closes), `gd` jump to the code a tool call touched.

Messages sent while the agent is working are queued; the input winbar shows
the count. `gq` opens the queue as plain text in a floating buffer — edit,
reorder, or delete the `─`-separated blocks like any text and close the
window (or `:w`) to apply.

Agents that plan their work send their steps as they go. They land in the
transcript, but scroll away; `gp` opens the latest plan in a float (`○` not
started, `◐` in progress, `✓` done, `q` closes), and the chat winbar carries
the step count as `▤ 2/5` while a plan is live.

The chat winbar carries a context counter — `◔ 21%` of the model's context
window, straight from the agent — with the glyph filling up (`○ ◔ ◑ ◕ ●`) as
the window does. Agents that don't report usage simply have no counter.

With follow mode on, the code area jumps to whatever file and line the agent
touches. `<leader>cf` marks the window you run it in as the target, so the
agent works in that one — a scratch split, say — while the rest of your
layout is left alone. The marked window says `⟳ following claude` in its
winbar; `gf` in the chat pauses and resumes without losing the mark. Both
the mark and the on/off state are saved with the thread.

Work an agent delegates arrives as an ordinary tool call — ACP has no notion
of a subagent — so acp.nvim recognises them by title (`subagent_patterns`,
covering Claude Code's `Task` by default). Spawns get the `◇` icon in the
transcript, `gs` lists them with status and runtime, and the winbar shows
`◇ 2` while any are still running.

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
  -- tool calls whose title matches are treated as subagent spawns
  subagent_patterns = { "^Task%f[%W]", "^Agent%f[%W]", "^Explore%f[%W]", "[Ss]ubagent" },
  ui = {
    sidebar_width = 30,
    details_height = 7,      -- details panel under the sidebar; 0 hides it
    chat_width = 64,
    input_height = 5,
    hide_tabline = true,     -- threads are tabs, the sidebar replaces the tabline
    focus_on_open = "keep",  -- "keep" | "input" | "code" | "sidebar"
    show_thinking = true,
    show_diffs = true,
    terminal_max_lines = 24, -- tail of terminal output kept inline
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
    selection = "<leader>cs", -- (visual) attach the selection as a chip
    diagnostic = "<leader>cd", -- attach the diagnostic under the cursor
    follow = "<leader>cf",     -- follow the agent in this window
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
